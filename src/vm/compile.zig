const std = @import("std");

const Lexer = @import("lexer/lexer.zig").Lexer;
const Token = @import("lexer/token.zig").Token;
const Parser = @import("parser/parser.zig").Parser;
const AstNode = @import("parser/ast.zig").AstNode;

/// compile a file from some path
pub fn compile(path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    const alloc = arena.allocator();

    const start = std.time.nanoTimestamp();

    // allocate buffer for file
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const size = (try file.stat()).size;
    const content = try file.readToEndAlloc(alloc, size);

    // tokenize
    var lexer = Lexer.init(content);
    const tokens_buf = try alloc.alloc(Token, size / 2);
    const num_tokens = try lexer.tokenize(tokens_buf);
    const tokens = tokens_buf[0..num_tokens];

    // parse
    var parser = Parser.init(alloc, tokens);
    const root = try parser.ParseRoot();
    _ = root;

    const elapsed = std.time.nanoTimestamp() - start;

    std.debug.print("compiled in {d} microseconds", .{@divFloor(elapsed, 1000)});
}