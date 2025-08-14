const std = @import("std");

// Normalized a path (replaces '\\' with '/' and calls std.fs.path.resolve)
// Result is owned by caller
fn normalizePath(allocator: *std.mem.Allocator, path: []const u8) ![]const u8 {
    const buf = try allocator.dupe(u8, path);
    defer allocator.free(buf);
    for (buf) |*c| {
        if (c.* == '\\') c.* = '/';
    }

    return try std.fs.path.resolve(allocator.*, &[_][]const u8{buf});
}

// Bidirectional map for path to index and index to path
// Automatically sets index for new entries
const IndexMap = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    nextIndex: usize = 0,
    pathToIndex: std.StringHashMap(usize),
    indexToPath: std.AutoHashMap(usize, []const u8),

    pub fn init(allocator: *std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .pathToIndex = std.StringHashMap(usize).init(allocator.*),
            .indexToPath = std.AutoHashMap(usize, []const u8).init(allocator.*),
        };
    }

    pub fn deinit(self: *Self) void {
        self.pathToIndex.deinit();
        self.indexToPath.deinit();
    }

    // Adds a path-index pair to the map.
    // Index is automatically assigned.
    // When an error is returned the pair did not get added
    pub fn add(self: *Self, path: []const u8) !void {
        const s_path = try normalizePath(self.allocator, path);
        // defer self.allocator.free(s_path);

        try self.pathToIndex.put(s_path, self.nextIndex);
        self.indexToPath.put(self.nextIndex, s_path) catch |err| {
            _ = self.pathToIndex.remove(s_path);
            return err;
        };
        self.nextIndex += 1;
    }

    // Same as get but returns index of new entry
    pub fn addAndFetch(self: *Self, path: []const u8) !usize {
        try self.add(path);
        return self.nextIndex - 1;
    }

    // Removes a path-index pair from map using path as the key.
    // returns true if removal was successful, false if not
    pub fn removePath(self: *Self, path: []const u8) !bool {
        const s_path = try normalizePath(self.allocator, path);
        defer self.allocator.free(s_path);
        if (self.pathToIndex.fetchRemove(s_path)) |kv| {
            if (self.indexToPath.remove(kv.value)) {
                self.allocator.free(kv.key);
                return true;
            }
        }
        return false;
    }

    // Removes a path-index pair from map using index as the key.
    // returns true if removal was successful, false if not
    pub fn removeIndex(self: *Self, index: usize) bool {
        if (self.indexToPath.fetchRemove(index)) |kv| {
            if (self.pathToIndex.remove(kv.value)) {
                self.allocator.free(kv.value);
                return true;
            }
        }
        return false;
    }

    // Get the index associated with the given path
    // returns optional; null when entry isn't found
    pub fn getIndex(self: *Self, path: []const u8) !?usize {
        const s_path = try normalizePath(self.allocator, path);
        defer self.allocator.free(s_path);
        return self.pathToIndex.get(s_path);
    }

    // Get the path assoicated with the given index
    // returns optional; null when entry isn't found
    pub fn getPath(self: *Self, index: usize) ?[]const u8 {
        return self.indexToPath.get(index);
    }

    // Get the index associated with a path, if the path is not registered, register it
    pub fn getOrCreate(self: *Self, path: []const u8) !usize {
        if (try self.getIndex(path)) |index| {
            return index;
        }
        return self.addAndFetch(path);
    }

    pub fn getCount(self: *Self) usize {
        return self.nextIndex;
    }
};

// TODO: test
const AdjacencyMatrix = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    size: usize,
    matrix: [][]const usize,

    pub fn init(allocator: *std.mem.Allocator, size: usize) !Self {
        const matrix: [][]const usize = try allocator.alloc([]const usize, size);
        for (0..size) |i| {
            matrix[i] = try allocator.alloc(usize, size);
            for (0..size) |j| {
                matrix[i][j] = 0;
            }
        }

        return .{
            .allocator = allocator,
            .size = size,
            .matrix = matrix,
        };
    }

    pub fn deinit(self: *Self) void {
        for (0..self.size) |i| {
            self.allocator.free(self.matrix[i]);
        }
        self.allocator.free(self.matrix);
    }
};

// Contains data from Graph
const GraphData = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    index_map: IndexMap,
    matrix: ?AdjacencyMatrix,
    code_paths: std.hash_map.AutoHashMap(usize, []const u8),

    pub fn init(allocator: *std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .index_map = IndexMap.init(allocator),
            .matrix = null,
            .code_paths = std.hash_map.AutoHashMap(usize, []const u8).init(allocator.*),
        };
    }

    pub fn deinit(self: *Self) void {
        self.index_map.deinit();
        if (self.matrix) |v| {
            v.deinit();
        }
        self.code_paths.deinit();
    }

    pub fn getCodePath(self: *Self, index: usize) ![]const u8 {
        if (self.code_paths.get(index)) |path| {
            return path;
        }
        return error.CodePathNotRegistered;
    }
};

// const Vertex = struct {
//     path: []const u8,
//     name: []const u8,
// };

// Parses a file structure into a DAG (Fills out a GraphData struct)
// TODO: Add cycle checking (trace path using stack)
// TODO: test
pub const Parser = struct {
    const Self = @This();

    const Edge = struct {
        from: usize,
        to: usize,
    };

    const EdgeFile = struct {
        edges: [][]const u8,
    };

    allocator: *std.mem.Allocator,
    g_data: *const GraphData,

    pub fn init(allocator: *std.mem.Allocator, g_data: *const GraphData) Self {
        return .{
            .allocator = allocator,
            .g_data = g_data,
        };
    }

    pub fn deinit(self: *Self) void {
        self.g_data.deinit();
    }

    fn deserializeEdgeFile(self: *Self, path: []const u8) !EdgeFile {
        const input_file = try std.fs.cwd().openFile(path, .{});
        defer input_file.close();

        const file_stat = try input_file.stat();

        const input = try input_file.readToEndAlloc(self.alloactor, file_stat.size);
        defer self.allocator.free(input);

        var status: std.zon.parse.Status = .{};
        defer status.deinit(self.allocator);
        const parsed = try std.zon.parse.fromSlice(EdgeFile, self.allocator, input, &status, .{ .free_on_error = true });

        return parsed;
    }

    // Constructs the path of the zon file holding the edges
    // result is owned by caller
    fn getEdgeFilePath(self: *Self, v: []const u8) ![]const u8 {
        const name = v;

        const file_name = try std.mem.concat(self.allocator.*, u8, &.{ name, ".zon" });
        return file_name;
    }

    // Constructs the path of the hurdy File holding the edges
    // result is owned by the caller
    fn getHurdyFilePath(self: *Self, v: []const u8) ![]const u8 {
        const name = v;

        const file_name = try std.mem.concat(self.allocator.*, u8, &.{ name, ".hurdy" });
        return file_name;
    }

    // Parses the DAG beginning at a root file recursively
    pub fn parse(self: *Self, root: []const u8) !void {
        // Generate edges
        const edges = std.ArrayList(Edge).init(self.allocator.*);
        defer edges.deinit();
        try self.recursiveParse(root, edges);

        // Create adjacency Matrix
        const size = self.g_data.index_map.getCount();
        self.g_data.matrix = AdjacencyMatrix.init(self.allocator, size);

        // Populate adjacency Matrix
        for (edges) |e| {
            self.g_data.matrix[e.from][e.to] = 1;
        }
    }

    fn recursiveParse(self: *Self, edges: std.ArrayList(Edge), v: []const u8) !void {
        const index_map = &self.g_data.index_map;

        // Get root index
        const root = try index_map.getOrCreate(v);

        // Add code path
        if (self.g_data.code_paths.get(root)) |_| {} else {
            try self.g_data.code_paths.put(root, try self.getHurdyFilePath(v));
        }

        // Parse edge file
        const edge_path = try self.getEdgeFilePath(v);
        defer self.allocator.free(edge_path);
        const edge_file = self.deserializeEdgeFile(edge_path) catch {
            return error.FailureDeserializingEdgeFile;
        };
        defer self.allocator.free(edge_file);

        // Convert Edge File into Edges
        for (edge_file.edges) |vertex| {
            const leaf = try index_map.getOrCreate(vertex);
            edges.append(.{
                .from = root,
                .to = leaf,
            });

            self.recursiveParse(edges, vertex);
        }
    }
};

pub const Graph = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    data: GraphData,

    pub fn parse(allocator: *std.mem.Allocator, root: []const u8) Self {
        const g_data = GraphData.init(allocator);
        defer g_data.deinit();

        const parser = Parser.init(allocator, *g_data);
        defer parser.deinit();
        parser.parse(root);

        return .{
            .allocator = allocator,
            .data = g_data,
        };
    }
};

const testing = std.testing;

test "IndexMap" {
    var allocator = testing.allocator;

    // Create IndexMap
    var map = IndexMap.init(&allocator);
    defer map.deinit();

    // Add test entries
    try map.add("foo");
    // try map.add("bar");
    const index = try map.getOrCreate("bar");

    // Test getters
    try testing.expect((try map.getIndex("foo")).? == 0);
    try testing.expect(std.mem.eql(u8, map.getPath(index).?, "bar"));

    // Test removes
    try testing.expect(try map.removePath("foo"));
    try testing.expect(map.removeIndex(try map.getOrCreate("bar")));
}
