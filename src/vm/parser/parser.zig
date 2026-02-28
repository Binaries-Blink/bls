const std = @import("std");
const Token = @import("../lexer/token.zig").Token;
const TokenType = @import("../lexer/token.zig").TokenType;
const AstNode = @import("ast.zig").AstNode;

pub const Parser = @This();

alloc: std.mem.Allocator,
tokens: []const Token,

const Self = @This();

/// initialize a new parser with a given slice of tokens
pub fn init(alloc: std.mem.Allocator, tokens: []const Token) Parser {
    return .{
        .alloc = alloc,
        .tokens = tokens,
    };
}

pub fn ParseRoot(self: *Self) !*AstNode {
    _ = self;
    return error.NotImplemented;
}