const std = @import("std");

pub const Graph = struct {
    // Contains data from Graph
    pub const GraphData = struct {
        // Bidirectional map for path to index and index to path
        // Automatically sets index for new entries
        pub const IndexMap = struct {
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

            // Normalized a path (replaces '\\' with '/' and calls std.fs.path.resolve)
            // Result is owned by caller
            fn normalizePath(self: *Self, path: []const u8) ![]const u8 {
                const buf = try self.allocator.dupe(u8, path);
                defer self.allocator.free(buf);
                for (buf) |*c| {
                    if (c.* == '\\') c.* = '/';
                }

                return try std.fs.path.resolve(self.allocator.*, &[_][]const u8{buf});
            }

            // Adds a path-index pair to the map.
            // Index is automatically assigned.
            // When an error is returned the pair did not get added
            pub fn add(self: *Self, path: []const u8) !void {
                const s_path = try self.normalizePath(path);
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
                const s_path = try self.normalizePath(path);
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
                const s_path = try self.normalizePath(path);
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
        };
    };
    pub const Parser = struct {
        pub fn parseMatrix() void {}
    };
};

const testing = std.testing;

test "IndexMap" {
    var allocator = testing.allocator;

    // Create IndexMap
    var map = Graph.GraphData.IndexMap.init(&allocator);
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
    try testing.expect(map.removeIndex(index));
}
