const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("chunk.zig").Value;
const instruction = @import("instruction.zig");

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

    const ArithOp = enum { add, sub, mul, div, mod};
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

    pub fn runImmediate(self: *Self, inst: instruction.IInst, frame: *StackFrame) !void {
        const code: instruction.Opcode = @enumFromInt(inst.code);
        _ = self;
        switch (code) {
            .LOADI => frame.regs[inst.dst] = .{ .int = inst.imm },
            .LOADM => { return error.todo; },
            .STOREM => { return error.todo; },
            .LOADG => { return error.todo; },
            .STOREG => { return error.todo; },
            .NEG => { return error.todo; },
            .NOT => { return error.todo; },
            .SHL => { return error.todo; },
            .SHR => { return error.todo; },
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
            .AND => { return error.todo; },
            .OR => { return error.todo; },
            .XOR => { return error.todo; },
            .EQ => { return error.todo; },
            .NE, .GT => { return error.todo; },
            .GE => { return error.todo; },
            .LT => { return error.todo; },
            .LE => { return error.todo; },
            else => unreachable,
        }
    }

    pub fn runJump(self: *Self, inst: instruction.JInst, frame: *StackFrame) !void {
        const code: instruction.Opcode = @enumFromInt(inst.code);
        switch (code) {
            .JMP => { return error.todo; },
            .JE => { return error.todo; },
            .JNE => { return error.todo; },
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
                    return;
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
                .jmp => |i| try self.runJump(i, frame_ptr),
            }

            // frame_ptr is invalidated past here
            // due to potentially allocating a new stack frame.

            std.debug.print("{f}", .{self.frames.items[self.frames.items.len - 1]});
        }
        const elapsed = std.time.nanoTimestamp() - start;
        std.debug.print("main successfully ran in {d}us", .{@divTrunc(elapsed, 1_000)});
    }
};