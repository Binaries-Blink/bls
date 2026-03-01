const std = @import("std");
const Token = @import("../lexer/token.zig").Token;
const TokenType = @import("../lexer/token.zig").TokenType;
const AstNode = @import("ast.zig").AstNode;

pub const Parser = @This();

alloc: std.mem.Allocator,
tokens: []const Token,
pos: usize = 0,

const Self = @This();

const ParseError = error {
    UnexpectedToken,
};

/// initialize a new parser with a given slice of tokens
pub fn init(alloc: std.mem.Allocator, tokens: []const Token) Parser {
    return .{
        .alloc = alloc,
        .tokens = tokens,
    };
}

inline fn end(self: *Self) bool {
    return self.pos >= self.num_tokens;
}

/// return the next token in the stream if it exists, and advance the parser's position.
inline fn advance(self: *Self) Token {
    const tok = self.tokens[self.pos];
    self.pos += 1;
    return tok;
}

/// return the next token in the stream if it exists, without advancing the parser's position.
inline fn peek(self: *Self) ?Token {
    if (self.end()) return null;
    return self.tokens[self.pos];
}

/// expect the given token type, if it is not next in the token stream and
/// error is returned, if it is, its consumed and returned
fn expect(self: *Self, ttype: TokenType) !Token {
    const peeked = self.peek() orelse return ParseError.UnexpectedEndOfTokens;
    if (peeked.type != ttype) {
        std.debug.print("{f}", .{peeked});
        return ParseError.UnexpectedToken;
    }
    return self.advance();
}

pub fn ParseRoot(self: *Self) !*AstNode {
    var nodes = try std.ArrayList(*AstNode).initCapacity(self.alloc, self.num_tokens / 2);
    defer nodes.deinit(self.alloc);

    // parse until no tokens remain
    while (!self.end()) {
        const node = try switch (self.tokens[self.pos].type) {
            else => {
                std.debug.print("{any}", .{self.peek()});
                return ParseError.UnexpectedToken;
            },
        };
        try nodes.append(self.alloc, node);
    }

    return AstNode.create(.{
        .root = try nodes.toOwnedSlice(self.alloc)
    });
}