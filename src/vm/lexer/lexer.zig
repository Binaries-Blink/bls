const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;

pub const Lexer = @This();

src: []const u8,
pos: usize = 0,

const Self = @This();
const TokenizationError = error {
    UnexpectedEof,
    UnexpectedChar,

};

/// construct a new lexer from some null terminated input string
pub fn init(src: []const u8) Self {
    return .{.src = src};
}

inline fn eof(self: *Self) bool {
    return self.pos >= self.src.len;
}

/// returns the next byte in the source without advancing the lexer, if the end of the input is reached, `null` is returned instead.
inline fn peek(self: *Self) ?u8 {
    if (self.eof()) return null;
    return self.src[self.pos];
}

/// advance the lexer forward, returning the next byte from the source.
inline fn advance(self: *Self) u8 {
    const c = self.src[self.pos];
    self.pos += 1;
    return c;
}

fn skipWhitespace(self: *Self) void {
    while (!self.eof() and std.ascii.isWhitespace(self.peek().?)) {
        _ = self.advance();
    }
}

fn skipComment(self: *Self) void {
    const start = self.pos;
    if ((self.peek() orelse return) == '/') _ = self.advance()
    else {self.pos = start; return;}

    if ((self.peek() orelse return) == '/') _ = self.advance()
    else {self.pos = start; return;}

    // Consume until newline or EOF
    while (self.peek()) |c| {
        _ = self.advance();
        if (c == '\n') return;
        // Handle \r\n (Windows line endings)
        if (c == '\r') {
            if ((self.peek() orelse return) == '\n') _ = self.advance();
            return;
        }
    }
    return;
}

// skips all non code symbols (whitespace & comments)
fn skip(self: *Self) void {
    while (true) {
        const start = self.pos;
        self.skipWhitespace();
        self.skipComment();
        if (self.pos == start) break;
    }
}

fn number(self: *Self, start: usize) !Token {
    while (!self.eof()) {
        const c = self.peek();
        if (c == null) return TokenizationError.UnexpectedEof;
        if (!std.ascii.isDigit(c.?)) break;
        _ = self.advance();
    }

    // check for fractional portion
    const next = self.peek();
    if (next != '.') {
        return Token{
            .raw = self.src[start..self.pos],
            .start = start,
            .type = .Numeric,
        };
    }
    // consume '.'
    _ = self.advance();

    // consume fractional portion
    while (!self.eof()) {
        const c = self.peek();
        if (c == null) return TokenizationError.UnexpectedEof;
        if (!std.ascii.isDigit(c.?)) break;
        _ = self.advance();
    }

    return Token{
        .raw = self.src[start..self.pos],
        .start = start,
        .type = .Numeric,
    };
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn keywordOrIdent(self: *Self, start: usize) !Token {
    while (!self.eof()) {
        const peeked = self.peek();
        if (peeked) |c| {
            if (!Lexer.isIdentChar(c)) break;
        }
        _ = self.advance();
    }

    const raw = self.src[start..self.pos];

    return .{
        .raw = raw,
        .start = start,
        .type = TokenType.keyword_map.get(raw) orelse .Ident,
    };
}

fn symbol(self: *Self, start: usize) !Token {
    const max_len = @min(TokenType.longest_symbol, self.src.len - start);
    var len = max_len;
    while (len > 0) : (len -= 1) {
        const slice = self.src[start .. start + len];
        if (TokenType.symbol_map.get(slice)) |tok| {
            self.pos = start + len;
            return Token{
                .type = tok,
                .start = start,
                .raw = slice,
            };
        }
    }
    return TokenizationError.UnexpectedChar;
}

/// returns the next token that can be constructed from the input string, or any errors that are encountered while doing so.
fn nextToken(self: *Self) !?Token {
    // self.skipWhitespace();
    // self.skipComment();
    // self.skipWhitespace();
    self.skip();
    if (self.eof()) return null;

    const start = self.pos;
    const c = self.advance();

    switch (c) {
        'a'...'z', 'A'...'Z', '_' => return try self.keywordOrIdent(start),
        '0'...'9' => return try self.number(start),
        else => return try self.symbol(start),
    }
}

/// tokenizes the input string, writing all tokens to the provided buffer, and returning the number of tokens written.
///
/// returns any error encountered while tokenizing the source.
pub fn tokenize(self: *Self, tokens: []Token) !usize {
    var i: usize = 0;

    while (true) : (i += 1) {
        if (self.eof()) break;
        const next = try self.nextToken();
        if (next) |t| tokens[i] = t else break;
    }

    return i;
}