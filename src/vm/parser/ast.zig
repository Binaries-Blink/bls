const std = @import("std");

pub const AstNode = union(enum) {
    /// a slice of all top level nodes
    root: []*AstNode,

    const Self = @This();

    /// construct and return a pointer to a new node
    pub fn create(alloc: std.mem.Allocator, node: Self) !*Self {
        const ptr = try alloc.create(Self);
        ptr.* = node;
        return ptr;
    }
};