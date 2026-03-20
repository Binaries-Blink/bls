const std = @import("std");

const Lexer = @import("lexer/lexer.zig").Lexer;
const Token = @import("lexer/token.zig").Token;
const Parser = @import("parser/parser.zig").Parser;
const AstNode = @import("blast").AstNode;
const Analyzer = @import("blast").Analyzer;

/// "compile" a file from some path into an AST
pub fn compile(path: []const u8) !*AstNode {
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
    const root = try parser.parseRoot();

    // semantic analysis
    var analyzer = try Analyzer.init(alloc);
    try analyzer.analyze(root);

    const table = analyzer.table;

    const elapsed = std.time.nanoTimestamp() - start;
    std.debug.print("compiled in {d} microseconds\n", .{@divFloor(elapsed, 1000)});
    std.debug.print("{f}\n", .{root});
    std.debug.print("{f}\n", .{table});

    return root;
}