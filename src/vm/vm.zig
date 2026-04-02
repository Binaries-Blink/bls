const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("chunk.zig").Value;
const instruction = @import("instruction.zig");

/// the value returned by the main chunk
pub const ExitValue  = struct {
    val: Value
};

pub const StackFrame = struct {
    /// the chunk that this frame is responsible for
    chunk: *const Chunk,
    regs: [64]Value,
    /// which register the return value is placed in
    ret: u6 = 0,
    pc: usize = 0,

    fn drawHeader(writer: *std.Io.Writer, text: []const u8) !void {
        const inner_width = 50;

        const text_len = text.len;
        const total_padding = inner_width - text_len;
        const left = total_padding / 2;
        const right = total_padding - left;

        try writer.writeAll("┌");
        for (0..left) |_| try writer.writeAll("─");
        try writer.writeAll(text);
        for (0..right) |_| try writer.writeAll("─");
        try writer.writeAll("┐\n");
    }

    fn drawFooter(writer: *std.Io.Writer) !void {
        try writer.writeAll("└");
        for (0..50) |_| try writer.writeAll("─");
        try writer.writeAll("┘\n");
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try drawHeader(writer, self.chunk.name);
        const inner_width = 50;

        for (self.regs, 0..) |val, i| {
            if (val == .void) continue;
            var buf: [128]u8 = undefined;
            const content = std.fmt.bufPrint(
                &buf,
                "r{d:0>2} : {f}", .{ i, val }
            ) catch unreachable;

            try writer.writeAll("│");
            try writer.writeAll(content);

            if (content.len < inner_width) {
                for (0..(inner_width - content.len)) |_| {
                    try writer.writeAll(" ");
                }
            }

            try writer.writeAll("│\n");
        }

        try drawFooter(writer);
    }
};

pub const Vm = struct {
    alloc: std.mem.Allocator,
    frames: std.ArrayList(StackFrame),

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Vm {
        return .{
            .alloc = alloc,
            .frames = try std.ArrayList(StackFrame).initCapacity(alloc, 1),
        };
    }

    pub fn deinit(self: Self) void {
        self.frames.deinit(self.alloc);
    }

    pub fn truthy(val: Value) bool {
        return switch (val) {
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .bool => |b| b,
            else => false,
        };
    }

    const ArithOp = enum { add, sub, mul, div, mod };
    fn arithmeticOp(op: ArithOp, a: Value, b: Value) !Value {
        switch (a) {
            .int => |lhs| {
                const rhs = if (b == .int) b.int else return error.TypeError;
                return .{ .int = switch (op) {
                    .add => lhs +% rhs,
                    .sub => lhs -% rhs,
                    .mul => lhs *% rhs,
                    .div => if (rhs == 0) return error.DivisionByZero else @divTrunc(lhs, rhs),
                    .mod => if (rhs == 0) return error.DivisionByZero else @rem(lhs, rhs),
                }};
            },
            .float => |lhs| {
                const rhs = if (b == .float) b.float else return error.TypeError;
                return .{ .float = switch (op) {
                    .add => lhs + rhs,
                    .sub => lhs - rhs,
                    .mul => lhs * rhs,
                    .div => lhs / rhs,
                    .mod => @rem(lhs, rhs),
                }};
            },
            else => return error.TypeError
        }
    }

    const cmpOp = enum { eq, neq, lt, le, gt, ge };
    fn comparisonOp(op: cmpOp, a: Value, b: Value) !Value {
        switch (a) {
            .int => |lhs| {
                const rhs = if (b == .int) b.int else return error.TypeError;
                return .{.bool = switch (op) {
                    .eq => lhs == rhs,
                    .neq => lhs != rhs,
                    .lt => lhs < rhs,
                    .le => lhs <= rhs,
                    .gt => lhs > rhs,
                    .ge => lhs >= rhs,
                }};
            },
            .float => |lhs| {
                const rhs = if (b == .float) b.float else return error.TypeError;
                return .{.bool = switch (op) {
                    .eq => lhs == rhs,
                    .neq => lhs != rhs,
                    .lt => lhs < rhs,
                    .le => lhs <= rhs,
                    .gt => lhs > rhs,
                    .ge => lhs >= rhs,
                }};
            },
            .bool => |lhs| {
                const rhs = if (b == .bool) b.bool else return error.TypeError;
                return .{.bool = switch (op) {
                    .eq => lhs == rhs,
                    .neq => lhs != rhs,
                    else => return error.UnsupportedOp,
                }};
            },
            else => return error.TypeError,
        }
    }

    const bitOp = enum { @"and", @"or", xor, shl, shr };
    fn bitwiseOp(op: bitOp, a: Value, b: Value) !Value {
        const lhs = if (a == .int) a.int else return error.TypeError;
        const rhs = if (b == .int) b.int else return error.TypeError;

        return .{.int = switch (op) {
            .@"and" => lhs & rhs,
            .@"or" => lhs | rhs,
            .xor => lhs ^ rhs,
            .shl => blk: {
                if (rhs < 0 or rhs > 63) return error.TypeError;
                break :blk lhs << @intCast(rhs);
            },
            .shr => blk: {
                if (rhs < 0 or rhs > 63) return error.TypeError;
                break :blk lhs >> @intCast(rhs);
            },
        }};
    }

    pub fn runImmediate(self: *Self, inst: instruction.IInst, frame: *StackFrame) !void {
        const code: instruction.Opcode = @enumFromInt(inst.code);
        _ = self;
        switch (code) {
            .LOADI => frame.regs[inst.dst] = .{ .int = inst.imm },
            .LOADM => { return error.todo; },
            .STOREM => { return error.todo; },
            .ITOF => { return error.todo; },
            .FTOI => { return error.todo; },
            .ARG => {
                // will be consumed by call,
                // it will come back to collect them later.
            },
            .ALLOC => { return error.todo; },
            else => unreachable,
        }
    }

    pub fn runRegister(self: *Self, inst: instruction.RInst, frame: *StackFrame) !void {
        const code: instruction.Opcode = @enumFromInt(inst.code);
        _ = self;
        switch (code) {
            .LOADR => frame.regs[inst.dst] = frame.regs[inst.src1],
            .ADD => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try arithmeticOp(.add, lhs, rhs);
            },
            .SUB => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try arithmeticOp(.sub, lhs, rhs);
            },
            .MUL => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try arithmeticOp(.mul, lhs, rhs);
            },
            .DIV => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try arithmeticOp(.div, lhs, rhs);
            },
            .MOD, => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try arithmeticOp(.mod, lhs, rhs);
            },
            .NEG => {
                frame.regs[inst.dst] = switch (frame.regs[inst.src1]) {
                    .int => |i| .{.int = -i},
                    .float => |f| .{.float = -f},
                    else => return error.TypeError,
                };
            },
            .POS => {
                frame.regs[inst.dst] = switch (frame.regs[inst.src1]) {
                    .int => |i| .{ .int = if (i < 0) -i else i },
                    .float => |f| .{ .float = if (f < 0) -f else f },
                    else => return error.TypeError,
                };
            },
            .NOT => { return error.todo; },
            .AND => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try bitwiseOp(.@"and", lhs, rhs);
            },
            .OR => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try bitwiseOp(.@"or", lhs, rhs);
            },
            .XOR => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try bitwiseOp(.xor, lhs, rhs);
            },
            .SHL => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try bitwiseOp(.shl, lhs, rhs);
            },
            .SHR => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try bitwiseOp(.shr, lhs, rhs);
            },
            .EQ => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try comparisonOp(.eq, lhs, rhs);
            },
            .NE => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try comparisonOp(.neq, lhs, rhs);
            },
            .GT => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try comparisonOp(.gt, lhs, rhs);
            },
            .GE => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try comparisonOp(.ge, lhs, rhs);
            },
            .LT => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try comparisonOp(.lt, lhs, rhs);
            },
            .LE => {
                const lhs = frame.regs[inst.src1];
                const rhs = frame.regs[inst.src2];
                frame.regs[inst.dst] = try comparisonOp(.le, lhs, rhs);
            },
            else => unreachable,
        }
    }

    pub fn runJump(self: *Self, inst: instruction.JInst, frame: *StackFrame) !?ExitValue {
        const code: instruction.Opcode = @enumFromInt(inst.code);
        switch (code) {
            .JMP => frame.pc = @intCast(@as(i64, @intCast(frame.pc)) + inst.offset),
            .JE => {
                const clause = frame.regs[inst.reg];
                if (truthy(clause)) {
                    frame.pc = @intCast(@as(i64, @intCast(frame.pc)) + inst.offset);
                }
            },
            .JNE => {
                const clause = frame.regs[inst.reg];
                if (!truthy(clause)) {
                    frame.pc = @intCast(@as(i64, @intCast(frame.pc)) + inst.offset);
                }
            },
            .LOADF => { return error.todo; },
            .LOADC => { return error.todo; },
            .RET => {
                const result = frame.regs[inst.reg];
                const dst = frame.ret;
                _ = self.frames.pop();

                if (self.frames.items.len > 0) {
                    const caller = &self.frames.items[self.frames.items.len - 1];
                    // std.debug.print("returning to {s} with value {f} in r{d}\n", .{caller.chunk.name, result, dst});
                    caller.regs[dst] = result;
                } else {
                    // returned from top level, program is done
                    // in the future we can have this return the
                    // value as the exit code.
                    return .{ .val = result };
                }

            },
            .CALL => {
                // backtrack and collect args
                var regs = [_]Value{.void} ** 64;
                var argc: u6 = 0;
                var scan: usize = frame.pc - 1;
                while (argc < 64) : (argc += 1) {
                    scan -= 1;
                    const arg: instruction.RInst = @bitCast(frame.chunk.code.items[scan]);
                    const op: instruction.Opcode = @enumFromInt(arg.code);
                    if (op != .ARG) break;
                    regs[arg.dst] = frame.regs[arg.src1];
                }

                // create a new stack frame for the function call
                const idx: usize = @intCast(inst.offset);
                const fn_chunk = frame.chunk.functions.items[idx];

                try self.frames.append(self.alloc, .{
                    .chunk = fn_chunk,
                    .regs = regs,
                    .ret = inst.reg,
                });
            },
            .RET_VOID => { return error.todo; },
            else => unreachable,
        }
        return null;
    }

    /// run the program
    pub fn run(self: *Self, main: *const Chunk) !void {
        const start = std.time.nanoTimestamp();
        try self.frames.append(self.alloc, .{
            .chunk = main,
            .regs = [_]Value{.void} ** 64,
        });

        while (self.frames.items.len > 0) {
            const frame_ptr = &self.frames.items[self.frames.items.len - 1];

            if (frame_ptr.pc >= frame_ptr.chunk.code.items.len) {
                _ = self.frames.pop();
                continue;
            }

            const code = frame_ptr.chunk.code.items[frame_ptr.pc];
            frame_ptr.*.pc += 1;

            const inst = instruction.Instruction.decode(code);

            switch (inst) {
                .reg => |i| try self.runRegister(i, frame_ptr),
                .imm => |i| try self.runImmediate(i, frame_ptr),
                .jmp => |i| blk: {
                    const exit = try self.runJump(i, frame_ptr) orelse break :blk;
                    std.debug.print("main completed with exit value: {f}", .{exit.val});
                },
            }

            // frame_ptr is invalidated past here
            // due to potentially allocating a new stack frame.

            std.debug.print("{f}", .{self.frames.items[self.frames.items.len - 1]});
        }
        const elapsed = std.time.nanoTimestamp() - start;
        std.debug.print("main successfully ran in {d}us", .{@divTrunc(elapsed, 1_000)});
    }
};