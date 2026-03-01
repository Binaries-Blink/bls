const std = @import("std");

const Token = @import("../lexer/token.zig").Token;

pub const AstNode = union(enum) {
    /// a slice of all top level nodes
    root: []*AstNode,
    /// constant declaration
    @"const": Decl,
    /// variable declaration
    let: Decl,
    /// return statement
    ret: RetStmt,
    /// expressions
    expr: Expr,

    const Self = @This();

    /// standard constant / variable declaration
    pub const Decl = struct {
        name: Token,
        expr: *AstNode,
    };

    pub const Func = struct {
        name: Token,
        params: []*AstNode,
        ret_type: *AstNode,
        body: *AstNode,
    };

    pub const Expr = union(enum) {
        unary: Unary,
        binary: Binary,

        pub const Unary = struct {
            op: Token,
            expr: *Expr,
        };

        pub const Binary = struct {
            op: Token,
            left: *Expr,
            right: *Expr,
        };
    };

    pub const RetStmt = struct {
        expr: *AstNode,
    };

    /// construct and return a pointer to a new node
    pub fn create(alloc: std.mem.Allocator, node: Self) !*Self {
        const ptr = try alloc.create(Self);
        ptr.* = node;
        return ptr;
    }
};