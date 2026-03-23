const std = @import("std");

const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const Parser = @import("parser.zig").Parser;
const AstNode = @import("blast").AstNode;
const Analyzer = @import("blast").Analyzer;
const Chunk = @import("chunk.zig").Chunk;
const inst = @import("instruction.zig");

/// parse a file from some path into an AST
pub fn parse(alloc: std.mem.Allocator, path: []const u8) !*AstNode {
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

const Compiler = struct {
    alloc: std.mem.Allocator,
    chunks: std.ArrayList(Chunk),

    const Self = @This();

    fn opcode(code: u32) inst.Opcode {
        return @enumFromInt(@as(u8, @intCast(code >> 24)));
    }

    /// create a new chunk, return its index
    fn beginChunk(self: *Self) !usize {
        const idx = self.chunks.items.len;

        try self.chunks.append(self.alloc, Chunk {
            .alloc = self.alloc,
            .code = try std.ArrayList(u32).initCapacity(self.alloc, 0),
        });

        return idx;
    }

    /// ensure the given chunk properly returns,
    /// adding a RET_VOID instruction if its final
    /// instruction it not some other return
    fn endChunk(self: *Self, idx: usize) !void {
        var chunk = self.chunks.items[idx];
        const last = chunk.code.getLastOrNull();
        if (last == null or opcode(last.?) != .RET) {
            try chunk.emitJ(.RET_VOID, 0, 0);
        }
    }

    fn compileNode(self: *Self, node: *AstNode, chunk: usize) !void {
        _ = self;
        _ = node;
        _ = chunk;
        return error.NotImplemented;
    }
};

/// compile an Ast into bytecode,
pub fn compile(alloc: std.mem.Allocator, root: *AstNode) ![]Chunk {
    var compiler = Compiler {
        .alloc = alloc,
        .chunks = try std.ArrayList(Chunk).initCapacity(alloc, 0),
    };

    const top = try compiler.beginChunk();
    try compiler.compileNode(root, top);
    try compiler.endChunk(top);

    return compiler.chunks.toOwnedSlice(alloc);
}