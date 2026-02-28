const std = @import("std");

pub const TokenType = enum(u16) {
    Tilde,
    Bang,
    At,
    Pound,
    Dollar,
    Lparen,
    Rparen,
    Lbrace,
    Rbrace,
    Lbracket,
    Rbracket,
    Question,
    BackSlash,
    Colon,
    Semicolon,
    Comma,
    Assign,

    Arrow,
    Path,
    Dot,
    Range,
    RangeInc,

    Add,
    CompAdd,

    Sub,
    CompSub,

    Mul,
    CompMul,

    Div,
    CompDiv,

    Mod,
    CompMod,

    Lshift,
    CompLshift,

    Rshift,
    CompRshift,

    BitAnd,
    CompBitAnd,

    BitOr,
    CompBitOr,

    BitXor,
    CompBitXor,

    BitNot,
    CompBitNot,

    Neq,
    Eq,
    Gt,
    Lt,
    Ge,
    Le,
    And,
    Or,

    // container tokens (their raw values matter)
    Ident,
    String,
    Char,
    Numeric,

    // keywords
    True,
    False,
    Fn,
    Ret,
    Const,
    Struct,
    Enum,
    Let,
    Mut,
    If,
    Else,
    While,
    For,
    Loop,

    /// the length of the longest symbol.
    ///
    /// this is needed to ensure greedy matching
    pub const longest_symbol = 3;

    /// a map from string representations of symbols and operators,
    /// to their respective TokenType
    pub const symbol_map = std.StaticStringMap(TokenType).initComptime(.{
        .{"~", .Tilde},
        .{"!", .Bang},
        .{"@", .At},
        .{"#", .Pound},
        .{"$", .Dollar},
        .{"(", .Lparen},
        .{")", .Rparen},
        .{"{", .Lbrace},
        .{"}", .Rbrace},
        .{"[", .Lbracket},
        .{"]", .Rbracket},
        .{"?", .Question},
        .{"\\", .BackSlash},
        .{":", .Colon},
        .{";", .Semicolon},
        .{",", .Comma},
        .{"=", .Assign},
        .{"->", .Arrow},
        .{"::", .Path},
        .{".", .Dot},
        .{"..", .Range},
        .{"..=", .RangeInc},
        .{"+", .Add},
        .{"+=", .CompAdd},
        .{"-", .Sub},
        .{"-=", .CompSub},
        .{"*", .Mul},
        .{"*=", .CompMul},
        .{"/", .Div},
        .{"/=", .CompDiv},
        .{"%", .Mod},
        .{"%=", .CompMod},
        .{"<<", .Lshift},
        .{"<<=", .CompLshift},
        .{">>", .Rshift},
        .{">>=", .CompRshift},
        .{"&", .BitAnd},
        .{"&=", .CompBitAnd},
        .{"|", .BitOr},
        .{"|=", .CompBitOr},
        .{"^", .BitXor},
        .{"^=", .CompBitXor},
        .{"~=", .CompBitNot},
        .{"!=", .Neq},
        .{"==", .Eq},
        .{">", .Gt},
        .{"<", .Lt},
        .{">=", .Ge},
        .{"<=", .Le},
        .{"&&", .And},
        .{"||", .Or},
    });

    /// a map from string representations of keywords,
    /// to their respective TokenType
    pub const keyword_map = std.StaticStringMap(TokenType).initComptime(.{
        .{"true",   .True},
        .{"false",  .False},
        .{"fn",     .Fn},
        .{"ret",    .Ret},
        .{"const",  .Const},
        .{"struct", .Struct},
        .{"enum",   .Enum},
        .{"let",    .Let},
        .{"if",     .If},
        .{"else",   .Else},
        .{"while",  .While},
        .{"for",    .For},
        .{"loop",   .Loop},
    });
};

pub const Token = struct {
    type: TokenType,
    start: usize,
    raw: []const u8,

    pub fn format(self: Token, writer: *std.io.Writer) !void {
        try writer.print("{s}('{s}')", .{@tagName(self.type), self.raw});
    }
};