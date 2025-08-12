const std = @import("std");

pub const Vertex = struct {
    const Self = @This();

    allocator: *const std.mem.Allocator,
    name: []const u8,
    path: []const u8,
    edges: std.ArrayList(*Self),

    pub fn init(allocator: *const std.mem.Allocator, name: []const u8, path: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .path = path,
            .edges = std.ArrayList(*Self).init(allocator.*),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.edges.items) |v| {
            v.deinit();
        }
        self.edges.deinit();
    }

    pub fn addEdge(self: *Self, item: *Self) !void {
        try self.edges.append(item);
    }

    // Reutrns the vertex ('.hurdy') path
    // RESULT NEEDS TO BE DELETED MANUALLY
    pub fn getVertexPath(self: *Self) ![]const u8 {
        const filename = try std.mem.concat(self.allocator.*, u8, &.{ self.name, ".hurdy" });
        defer self.allocator.free(filename);

        const full_path = try std.fs.path.join(self.allocator.*, &.{ self.path, filename });
        return full_path;
    }

    // Reutrns the edge ('.zon') path
    // RESULT NEEDS TO BE DELETED MANUALLY
    pub fn getEdgePath(self: *Self) ![]const u8 {
        const filename = try std.mem.concat(self.allocator.*, u8, &.{ self.name, ".zon" });
        defer self.allocator.free(filename);

        const full_path = try std.fs.path.join(self.allocator.*, &.{ self.path, filename });
        return full_path;
    }
};
