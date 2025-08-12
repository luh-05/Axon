const std = @import("std");

pub fn foo() void {
    std.debug.print("Hello Axon!\n", .{});
}

test "a" {
    try std.testing.expect(true);
}

test {
    _ = @import("dag/graph.zig");
}
