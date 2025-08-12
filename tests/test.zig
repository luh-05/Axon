const axon = @import("axon");
const std = @import("std");
const expect = std.testing.expect;

test "add" {
    try expect(2 + 2 == 4);
}
