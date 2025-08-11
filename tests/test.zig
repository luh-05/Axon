const axon = @import("axon");
const std = @import("std");
const expect = std.testing.expect;

test "add" {
    try expect(2 + 2 == 4);
}

test "create vertex" {
    const alloc = std.testing.allocator;

    var v: axon.vertex.Vertex = axon.vertex.Vertex.init(&alloc, "test", ".");
    defer v.deinit();
}

test "create edges" {
    const alloc = std.testing.allocator;

    var v0: axon.vertex.Vertex = axon.vertex.Vertex.init(&alloc, "root", ".");
    defer v0.deinit();

    var v1 = axon.vertex.Vertex.init(&alloc, "1", ".");
    try v0.addEdge(&v1);
    var v2 = axon.vertex.Vertex.init(&alloc, "2", ".");
    try v1.addEdge(&v2);
    var v3 = axon.vertex.Vertex.init(&alloc, "3", ".");
    try v0.addEdge(&v3);
}

test "get vertex and edge path" {
    const alloc = std.testing.allocator;

    var v: axon.vertex.Vertex = axon.vertex.Vertex.init(&alloc, "bar", "foo");
    defer v.deinit();

    const v_path = try v.getVertexPath();
    defer alloc.free(v_path);

    const e_path = try v.getEdgePath();
    defer alloc.free(e_path);

    try expect(std.mem.eql(u8, v_path, "foo/bar.hurdy"));
    try expect(std.mem.eql(u8, e_path, "foo/bar.zon"));
}
