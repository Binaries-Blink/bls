const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;

const AstNode = @import("blast").AstNode;
const NodeKind = @import("blast").AstNode.NodeKind;

pub const Parser = @This();

alloc: std.mem.Allocator,
tokens: []const Token,
pos: usize = 0,

const Self = @This();

const ParseError = error {
    UnexpectedToken,
    UnexpectedEndOfTokens,
    InvalidOperaotr,
    OutOfMemory,
};

/// initialize a new parser with a given slice of tokens
pub fn init(alloc: std.mem.Allocator, tokens: []const Token) Parser {
    return .{
        .alloc = alloc,
        .tokens = tokens,
    };
}

inline fn end(self: *Self) bool {
    return self.pos >= self.tokens.len;
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

/// peek the next token, returning an error of it is null
inline fn peekNoEnd(self: *Parser) !Token {
    return self.peek() orelse ParseError.UnexpectedEndOfTokens;
}

/// expect the given token type, if it is not next in the token stream and
/// error is returned, if it is, its consumed and returned
fn expect(self: *Self, ttype: TokenType) !Token {
    const peeked = try self.peekNoEnd();
    if (peeked.type != ttype) {
        std.debug.print("{f}", .{peeked});
        return ParseError.UnexpectedToken;
    }
    return self.advance();
}

/// parse out a list of some kind of AstNode, separated by `sep` returning the list as a slice.
/// parsing will end when the next token in the stream is of the same type as `until`
fn parseList(self: *Self, comptime T: type, sep: TokenType, until: TokenType) ![]*AstNode {
    // select the method that will be used to parse list items
    const parser = comptime switch (T) {
        AstNode.NodeKind.Param => parseParam,
        else => @compileError("cannot generate parser for type: " ++ @typeName(T))
    };

    var items = try std.ArrayList(*AstNode).initCapacity(self.alloc, 0);

    while (true) {
        var peeked = try self.peekNoEnd();
        if (peeked.type == until) break;

        try items.append(self.alloc, try parser(self));

        peeked = try self.peekNoEnd();
        if (peeked.type == sep) { _ = self.advance(); } else break;
    }
    if ((try self.peekNoEnd()).type != until) return ParseError.UnexpectedToken;

    return items.toOwnedSlice(self.alloc);
}

fn parseTypeExpr(self: *Self) !*AstNode {
    // todo : optionals & errors
    const name = try self.expect(.Ident);
    return AstNode.create(self.alloc, .{ .ty_expr = .{ .name = name.raw }});
}

fn parseParam(self: *Self) !*AstNode {
    const name = try self.expect(.Ident);
    _ = try self.expect(.Colon);
    const ty = try self.parseTypeExpr();

    return AstNode.create(self.alloc, .{ .param = .{
        .name = name.raw,
        .type_expr = ty,
    }});
}

fn binaryPrecedence(tt: TokenType) ?u8 {
    return switch (tt) {
        .Assign, .CompAdd, .CompSub,
        .CompMul, .CompDiv, .CompMod,
        .CompBitNot, .CompBitOr, .CompBitXor,
        .CompBitAnd, .CompLshift, .CompRshift => 1,
        .Or => 2,
        .And => 3,
        .BitOr => 4,
        .BitXor => 5,
        .BitAnd => 6,
        .Eq, .Neq => 7,
        .Gt, .Ge, .Lt, .Le, => 8,
        .Lshift, .Rshift => 9,
        .Add, .Sub => 10,
        .Mul, .Div, .Mod => 11,
        .Dot => 99, // temp value, but this must be the max lol
        else => null,
    };
}

fn primary(self: *Self) !*AstNode {
    const peeked = try self.peekNoEnd();
    return switch(peeked.type) {
        // todo : handle unary ops
        .Numeric => AstNode.create(self.alloc, .{ .expr = .{ .literal = .{
            .kind = .numeric,
            .val = self.advance().raw,
        }}}),
        .Ident => {
            const tok = self.advance();
            // check for function call
            if ((try self.peekNoEnd()).type == .Lparen) {
                var args = try std.ArrayList(*AstNode).initCapacity(self.alloc, 0);
                defer args.deinit(self.alloc);

                _ = try self.expect(.Lparen);
                while (true) {
                    if ((try self.peekNoEnd()).type == .Rparen) break;
                    try args.append(self.alloc, try self.parseExpr());
                    if ((try self.peekNoEnd()).type == .Comma) _ = self.advance();
                }
                _ = try self.expect(.Rparen);

                return AstNode.create(self.alloc, .{ .expr = .{ .call = .{
                    .name = tok.raw,
                    .args = try args.toOwnedSlice(self.alloc),
                }}});
            }

            return AstNode.create(self.alloc, .{ .expr = .{ .ident = .{
                .name = tok.raw,
            }}});
        },
        .Lparen => {
            _ = try self.expect(.Lparen);
            const expr = try self.expression(0);
            _ = try self.expect(.Rparen);
            return expr;
        },
        .True, .False => AstNode.create(self.alloc, .{ .expr = .{ .literal = .{
            .kind = .bool,
            .val = self.advance().raw,
        }}}),
        .If => self.parseIf(),
        else => {
            const tok = self.advance();
            std.debug.print("{f}", .{tok});
            return ParseError.UnexpectedToken;
        },
    };
}

/// expression parsing helper, via precedence climbing
fn expression(self: *Self, min_prec: u8) ParseError!*AstNode {
    var result = try self.primary();

    while (true) {
        const current = self.peek() orelse return ParseError.UnexpectedEndOfTokens;

        const prec = binaryPrecedence(current.type) orelse break;
        if (prec < min_prec) break;
        _ = self.advance();

        const rhs = try self.expression(prec);

        const op = current.type.toOperator() orelse return error.InvalidOperaotr;

        result = try AstNode.create(self.alloc, .{ .expr =
            .{ .binary = .{
                .op = op,
                .left = result,
                .right = rhs,
            }}
        });
    }

    return result;
}

fn parseExpr(self: *Self) ParseError!*AstNode {
    const peeked = (try self.peekNoEnd()).type;
    if (peeked == .Lbrace) return try self.parseBlock();
    if (peeked == .If) return try self.parseIf();
    return try self.expression(0);
}

fn parseFn(self: *Self) !*AstNode {
    _ = try self.expect(.Fn);
    const name = try self.expect(.Ident);
    _ = try self.expect(.Lparen);
    const params = try self.parseList(AstNode.NodeKind.Param, .Comma, .Rparen);
    _ = try self.expect(.Rparen);
    const ret_ty = try self.parseTypeExpr();
    _ = try self.expect(.Assign);
    const body = try self.parseExpr();

    return AstNode.create(self.alloc, .{ .@"fn" = .{
        .name = name.raw,
        .params = params,
        .ret = ret_ty,
        .body = body,
    }});
}

fn parseConst(self: *Self) !*AstNode {
    _ = self;
    return ParseError.UnexpectedEndOfTokens;
}

fn parseLet(self: *Self) !*AstNode {
    _ = try self.expect(.Let);
    const name = (try self.expect(.Ident)).raw;

    const ty = if (self.peek()) |t| expr: {
        if (t.type == .Colon) {
            _ = self.advance();
            break :expr try self.parseTypeExpr();
        }
        break :expr null;
    } else null;

    _ = try self.expect(.Assign);
    const expr = try self.parseExpr();
    _ = try self.expect(.Semicolon);

    return AstNode.create(self.alloc, .{ .let = .{
        .name = name,
        .type_expr = ty,
        .value = expr,
    }});
}

fn parseRet(self: *Self) !*AstNode {
    _ = try self.expect(.Ret);
    const expr = try self.parseExpr();
    _ = try self.expect(.Semicolon);

    return AstNode.create(self.alloc, .{ .ret = .{ .value = expr }});
}

pub fn parseBlock(self: *Self) !*AstNode {
    _ = try self.expect(.Lbrace);
    var nodes = try std.ArrayList(*AstNode).initCapacity(self.alloc, 1);
    while ((try self.peekNoEnd()).type != .Rbrace) {
        const node = switch ((try self.peekNoEnd()).type) {
            .Lbrace => try self.parseBlock(),
            .Const => try self.parseConst(),
            .Let => try self.parseLet(),
            .Ret => try self.parseRet(),
            else => try self.parseExpr(),
        };
        try nodes.append(self.alloc, node);
    }
    _ = try self.expect(.Rbrace);

    return AstNode.create(self.alloc, .{.expr = .{.block =
        .{ .contents = try nodes.toOwnedSlice(self.alloc) }
    }});
}

pub fn parseRoot(self: *Self) !*AstNode {
    var nodes = try std.ArrayList(*AstNode).initCapacity(self.alloc, self.tokens.len / 2);
    defer nodes.deinit(self.alloc);

    // parse until no tokens remain
    while (!self.end()) {
        const node = try switch (self.tokens[self.pos].type) {
            .Fn => self.parseFn(),
            .Let => self.parseLet(),
            else => self.parseExpr(),
        };
        try nodes.append(self.alloc, node);
    }

    return AstNode.create(self.alloc, .{
        .root = try nodes.toOwnedSlice(self.alloc)
    });
}

pub fn parseIf(self: *Self) !*AstNode {
    _ = try self.expect(.If);

    const clause = try self.parseExpr();
    const then = try self.parseExpr();

    const else_branch = if ((try self.peekNoEnd()).type == .Else) blk: {
        _ = try self.expect(.Else);
        break :blk try self.parseExpr();
    } else blk: {
        break :blk null;
    };

    return AstNode.create(self.alloc, .{.expr = .{.@"if" = .{
        .clause = clause,
        .then = then,
        .@"else" = else_branch,
    }}});
}