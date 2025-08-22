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

const AdjacencyMatrix = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    size: usize,
    matrix: [][]usize,

    // Initializes an AdjacencyMatrix of a given size with zeros
    pub fn init(allocator: *std.mem.Allocator, size: usize) !Self {
        const matrix: [][]usize = try allocator.alloc([]usize, size);
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
        if (self.matrix) |*v| {
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
        pub const Path = struct { path: []const u8, name: []const u8 };
        edges: []Path,
    };

    allocator: *std.mem.Allocator,
    g_data: *GraphData,

    pub fn init(allocator: *std.mem.Allocator, g_data: *GraphData) Self {
        return .{
            .allocator = allocator,
            .g_data = g_data,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // self.g_data.deinit();
    }

    fn deserializeEdgeFile(self: *Self, path: []const u8) !EdgeFile {
        const input_file = try std.fs.cwd().openFile(path, .{});
        defer input_file.close();

        const file_stat = try input_file.stat();
        // defer self.allocator.destroy(file_stat);

        const input = try input_file.readToEndAllocOptions(self.allocator.*, file_stat.size, null, @sizeOf(u8), 0);
        std.debug.print("input size: {d}\ninput: {s}\n", .{ input.len, input });
        defer self.allocator.free(input);

        var status: std.zon.parse.Status = .{};
        defer status.deinit(self.allocator.*);
        const parsed = try std.zon.parse.fromSlice(EdgeFile, self.allocator.*, input, &status, .{ .free_on_error = true });

        return parsed;
    }

    // Constructs the path of the zon file holding the edges
    // result is owned by caller
    fn getEdgeFilePath(self: *Self, v: []const u8) ![]const u8 {
        const path = v;

        const file_name = try std.mem.concat(self.allocator.*, u8, &.{ path, ".zon" });
        return file_name;
    }

    // Constructs the path of the hurdy File holding the edges
    // result is owned by the caller
    fn getHurdyFilePath(self: *Self, v: []const u8) ![]const u8 {
        const path = v;

        const file_name = try std.mem.concat(self.allocator.*, u8, &.{ path, ".hurdy" });
        return file_name;
    }

    // Parses the DAG beginning at a root file recursively
    pub fn parse(self: *Self, root: EdgeFile.Path) !void {
        // Generate edges
        var edges = std.ArrayList(Edge).init(self.allocator.*);
        defer edges.deinit();
        var path = std.ArrayList([]const u8).init(self.allocator.*);
        defer path.deinit();
        try self.recursiveParse(&edges, &path, root);

        // Create adjacency Matrix
        const size = self.g_data.index_map.getCount();
        self.g_data.matrix = try AdjacencyMatrix.init(self.allocator, size);

        // Populate adjacency Matrix
        if (self.g_data.matrix) |matrix| {
            for (edges.items) |e| {
                matrix.matrix[e.from][e.to] = 1;
            }
        }
    }

    // Concat the paths of the given stack
    fn concatRelativePaths(self: *Self, stack: *std.ArrayList([]const u8)) ![]const u8 {
        const size = stack.items.len * 2 - 1;
        std.debug.print("path size: {d}\n", .{size});
        var parts: [][]const u8 = try self.allocator.alloc([]const u8, size);
        defer self.allocator.free(parts);

        for (0..parts.len) |i| {
            if (i % 2 != 0) {
                parts[i] = "/";
            } else {
                parts[i] = stack.items[i / 2];
            }
        }
        std.debug.print("path parts: {any}\n", .{parts});

        const full_path = try std.fs.path.join(self.allocator.*, parts);
        return full_path;
    }

    // Constructs the path without the suffix
    fn buildPath(self: *Self, stack: *std.ArrayList([]const u8), name: []const u8) ![]const u8 {
        const prefix = try self.concatRelativePaths(stack);
        defer self.allocator.free(prefix);

        const path = try std.fs.path.join(self.allocator.*, &.{ prefix, name });
        return path;
    }

    fn recursiveParse(self: *Self, edges: *std.ArrayList(Edge), path: *std.ArrayList([]const u8), v: EdgeFile.Path) !void {
        const index_map = &self.g_data.index_map;

        // Append current relative path to stack
        std.debug.print("v: {s}\n", .{v.path});
        try path.append(v.path);
        defer _ = path.pop();
        const full_path = try self.buildPath(path, v.name);
        std.debug.print("full path: {s}\n", .{full_path});
        defer self.allocator.free(full_path);

        // Get root index
        const root = try index_map.getOrCreate(full_path);

        // Add code path
        if (self.g_data.code_paths.get(root)) |_| {} else {
            // try self.g_data.code_paths.put(root, try self.getHurdyFilePath(v));
        }

        // Parse edge file
        const edge_path: []const u8 = try self.getEdgeFilePath(full_path);
        defer self.allocator.free(edge_path);
        const edge_file = self.deserializeEdgeFile(edge_path) catch {
            std.debug.print("path: '{s}'", .{edge_path});
            return error.FailureDeserializingEdgeFile;
        };
        // defer self.allocator.destroy(edge_file);
        // defer self.allocator.free(edge_file);

        // Convert Edge File into Edges
        for (edge_file.edges) |vertex| {
            try path.append(vertex.path);
            const leaf_path = try self.buildPath(path, vertex.name);
            defer self.allocator.free(leaf_path);
            _ = path.pop();
            const leaf = try index_map.getOrCreate(leaf_path);
            try edges.append(.{
                .from = root,
                .to = leaf,
            });

            try self.recursiveParse(edges, path, vertex);
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
        parser.parse(.{ .path = root, .name = "" });

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

test "AdjacencyMatrix" {
    var allocator = testing.allocator;

    var matrix = try AdjacencyMatrix.init(&allocator, 5);
    defer matrix.deinit();
}

test "DAG parsing" {
    var allocator = testing.allocator;

    var g_data = GraphData.init(&allocator);
    defer g_data.deinit();

    var parser = Parser.init(&allocator, &g_data);
    defer parser.deinit();

    try parser.parse(.{ .path = "./example_graph", .name = "root" });
}
