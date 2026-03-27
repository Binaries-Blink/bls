const std = @import("std");

const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const Parser = @import("parser.zig").Parser;
const AstNode = @import("blast").AstNode;
const Analyzer = @import("blast").Analyzer;
const Chunk = @import("chunk.zig").Chunk;
const inst = @import("instruction.zig");
const Scope = @import("scope.zig").Scope;
const Symbol = @import("scope.zig").Symbol;

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
    scopes: std.ArrayList(Scope),

    const Self = @This();

    const Error = error {
        NullMeta,
        ExpectedChunk,
        ExpectedExpression,
        RegistersFull,
        invalidTypeForNumber,
        UndefinedIdent,
        UndefinedFunction,
        NotAFunction,
        InvalidOp,

        OutOfMemory,
        Overflow,
        InvalidCharacter,

        NotImplemented,
    };

    fn opcode(code: u32) inst.Opcode {
        return @enumFromInt(@as(u8, @intCast(code >> 24)));
    }

    /// create a new chunk, return its index
    fn beginChunk(self: *Self) Error!usize {
        const idx = self.chunks.items.len;
        try self.chunks.append(self.alloc, try Chunk.init(self.alloc));
        return idx;
    }

    /// ensure the given chunk properly returns,
    /// adding a RET_VOID instruction if its final
    /// instruction it not some other return
    fn endChunk(self: *Self, idx: usize) Error!void {
        var chunk = self.chunks.items[idx];
        const last = chunk.code.getLastOrNull();
        if (last == null or opcode(last.?) != .RET) {
            try chunk.emitJ(.RET_VOID, 0, 0);
        }
    }

    /// add a new scope to the stack
    fn pushScope(self: *Self) Error!void {
        try self.scopes.append(self.alloc, Scope.init(self.alloc));
    }

    /// pop a scope off the stack
    fn popScope(self: *Self) void {
        var scope = self.scopes.pop() orelse return;
        scope.deinit();
    }

    /// define a new symbol in the current scope
    fn define(self: *Self, name: []const u8, sym: Symbol) Error!void {
        // var current = self.scopes.getLastOrNull() orelse return;
        var current = &self.scopes.items[self.scopes.items.len - 1];
        try current.put(name, sym);
    }

    /// return a pointer to the current chunk
    fn getChunk(self: *Self, idx: usize) *Chunk {
        return &self.chunks.items[idx];
    }

    /// lookup some symbol across all scopes in the stack
    fn lookup(self: *Self, name: []const u8) ?Symbol {
        var i = self.scopes.items.len - 1;
        while (i > 0) : (i -= 1) {
            if (self.scopes.items[i].get(name)) |s| return s;
        }
        return null;
    }

    fn compileNode(self: *Self, node: *AstNode, chunk_idx: usize) Error!void {
        switch (node.*.kind) {
            .root => |ns| for (ns) |n| try self.compileNode(n, chunk_idx),
            .@"const" => |_| {
                // todo : evaluate rhs and define the result
                // i need to implement a constEval function
            },
            .let => |l| {
                const reg = try self.compileExpr(l.value, chunk_idx);
                try self.define(l.name, .{ .register = reg });
            },
            .@"fn" => |f| {
                const body_idx = try self.beginChunk();
                try self.pushScope();
                const body_chunk = self.getChunk(body_idx);

                // place each param in a register
                for (f.params, 0..) |param, i| {
                    const reg: u6 = @intCast(i);
                    body_chunk.regs.markUsed(reg);
                    try self.define(param.kind.param.name, .{ .register = reg });
                }

                try self.compileNode(f.body, body_idx);
                self.popScope();
                try self.endChunk(body_idx);

                const fn_chunk = self.chunks.pop() orelse return error.ExpectedChunk;
                const fn_ptr = try self.alloc.create(Chunk);
                fn_ptr.* = fn_chunk;
                const fn_idx = try self.getChunk(chunk_idx).addFn(fn_ptr);
                
                try self.define(f.name, .{ .constant = .{ .fn_ref = fn_idx }});
            },
            .expr => _ = try self.compileExpr(node, chunk_idx),
            else => {
                std.debug.print("{s}\n", .{@tagName(node.kind)});
                return error.NotImplemented;
            }
        }
    }

    /// expression specific compilation
    fn compileExpr(self: *Self, node: *AstNode, chunk_idx: usize) Error!u6 {
        const chunk = self.getChunk(chunk_idx);
        const meta = node.meta orelse return error.NullMeta;

        if (node.kind != .expr) return error.ExpectedExpression;
        return switch (node.kind.expr) {
            .literal => |lit| {
                const dst = try chunk.regs.alloc();
                switch (lit.kind) {
                    .numeric => {
                        switch (meta.ty.*.primitive) {
                            .int_literal, .int => {
                                const n = try std.fmt.parseInt(i64, lit.val, 10);
                                try chunk.emitLoad(dst, .{ .int = n });
                            },
                            .float_literal, .f32, .f64, .f80, .f128  => {
                                const n = try std.fmt.parseFloat(f64, lit.val);
                                try chunk.emitLoad(dst, .{ .float = n });
                            },
                            else => return Error.invalidTypeForNumber,
                        }
                    },
                    .bool => {
                        return Error.NotImplemented;
                    },
                    .char => {
                        return Error.NotImplemented;
                    },
                    .string => {
                        return Error.NotImplemented;
                    },
                }
                return dst;
            },
            .ident => |id| {
                const sym = self.lookup(id.name) orelse {
                    std.debug.print("{s}\n", .{id.name});
                    return error.UndefinedIdent;
                };
                switch (sym) {
                    .register => |r| return r,
                    .constant => |v| {
                        const dst = try chunk.regs.alloc();
                        try chunk.emitLoad(dst, v);
                        return dst;
                    },
                }
            },
            .call => |c| {
                const sym = self.lookup(c.name) orelse return error.UndefinedFunction;
                const fn_idx = switch (sym) {
                    .constant => |val| switch (val) {
                        .fn_ref => |r| r,
                        else => return error.NotAFunction,
                    },
                    else => return error.NotAFunction,
                };

                for (c.args) |arg| {
                    const reg = try self.compileExpr(arg, chunk_idx);
                    try chunk.emitR(.ARG, 0, reg, 0);
                }

                const dst = try chunk.regs.alloc();
                try chunk.emitJ(.CALL, dst, @intCast(fn_idx));
                return dst;
            },
            .unary => |_| {
                return Error.NotImplemented;
            },
            .binary => |b| {
                const lhs = try self.compileExpr(b.left, chunk_idx);
                const rhs = try self.compileExpr(b.right, chunk_idx);
                const dst = try chunk.regs.alloc();
                const op = inst.OpToCode(b.op) orelse return error.InvalidOp;
                try chunk.emitR(op, dst, lhs, rhs);
                chunk.regs.free(lhs);
                chunk.regs.free(rhs);
                return dst;
            },
            .@"if" => |_| {
                return Error.NotImplemented;
            },
            .block => |_| {
                return Error.NotImplemented;
            },
        };
    }
};

/// compile an Ast into bytecode,
pub fn compile(alloc: std.mem.Allocator, root: *AstNode) Compiler.Error![]Chunk {
    var compiler = Compiler {
        .alloc = alloc,
        .chunks = try std.ArrayList(Chunk).initCapacity(alloc, 0),
        .scopes = try std.ArrayList(Scope).initCapacity(alloc, 0),
    };

    try compiler.pushScope();
    const top = try compiler.beginChunk();
    try compiler.compileNode(root, top);
    try compiler.endChunk(top);
    compiler.popScope();

    return compiler.chunks.toOwnedSlice(alloc);
}