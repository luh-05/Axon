const std = @import("std");
pub const vertex = @import("dag/vertex.zig");

pub fn foo() void {
    std.debug.print("Hello Axon!\n", .{});
}
