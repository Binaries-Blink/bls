const std = @import("std");
const inst = @import("instruction.zig");
const RegisterAllocator = @import("register.zig").RegisterAllocator;
const writeInstruction = @import("instruction.zig").writeInstruction;

pub const Value = union(enum) {
    /// uninitialized
    void,
    int: i64,
    float: f64,
    bool: bool,
    fn_ref: u18,

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        switch (self) {
            .int => |i| try writer.print("{d}\n", .{i}),
            .float => |f| try writer.print("{d}\n", .{f}),
            .bool => |b| try writer.print("{any}\n", .{b}),
            .fn_ref => |f| try writer.print("fn -> {d}\n", .{f}),
            .void => try writer.print("void\n", .{}),
        }
    }
};

pub const Chunk = struct {
    alloc: std.mem.Allocator,
    name: []const u8,
    /// the actual bytecode for this chunk
    code: std.ArrayList(u32),
    constants: std.ArrayList(Value),
    functions: std.ArrayList(*Chunk),
    regs: RegisterAllocator = .{},

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, name: []const u8) !Chunk {
        return .{
            .alloc = alloc,
            .name = name,
            .code = try std.ArrayList(u32).initCapacity(alloc, 0),
            .constants = try std.ArrayList(Value).initCapacity(alloc, 0),
            .functions = try std.ArrayList(*Chunk).initCapacity(alloc, 0),
        };
    }

    /// add some constant to the chunk
    pub fn addConst(self: *Self, val: Value) !u18 {
        const idx = self.constants.items.len;
        try self.constants.append(self.alloc, val);
        return @intCast(idx);
    }

    /// add some function to the chunk
    pub fn addFn(self: *Self, func: *Self) !u18 {
        const idx = self.functions.items.len;
        try self.functions.append(self.alloc, func);
        return @intCast(idx);
    }

    /// add a register instruction to the code
    pub fn emitR(self: *Self, op: inst.Opcode, dst: u6, src1: u6, src2: u6) !void {
        try self.code.append(self.alloc, inst.RInst.encode(.{
            .code = @intFromEnum(op),
            .dst = dst,
            .src1 = src1,
            .src2 = src2,
        }));
    }

    /// add an immediate instruction to the code
    pub fn emitI(self: *Self, op: inst.Opcode, dst: u6, src: u6, imm: i12) !void {
        try self.code.append(self.alloc, inst.IInst.encode(.{
            .code = @intFromEnum(op),
            .dst = dst,
            .src = src,
            .imm = imm,
        }));
    }

    /// add a jump instruction to the code
    pub fn emitJ(self: *Self, op: inst.Opcode, reg: u6, offset: i18) !void {
        try self.code.append(self.alloc, inst.JInst.encode(.{
            .code = @intFromEnum(op),
            .reg = reg,
            .offset = offset,
        }));
    }

    /// emit a standard jump instruction
    pub fn emitJump(self: *Self, offset: i18) !void {
        try self.emitJ(.JMP, 0, offset);
    }

    /// emit a conditional jump instruction, returning its position
    pub fn emitJumpIf(self: *Self, op: inst.Opcode, cond: u6) !usize {
        const idx = self.code.items.len;
        // emit the jump instruction with an offset of zero,
        // to be updated later when we know where to go
        try self.emitJ(op, cond, 0);
        return idx;
    }

    /// update the given jump instruction with an offset
    /// pointing to the current position in the code
    ///
    /// example usage:
    /// ```
    /// if (x < 2) {
    ///     ...
    /// } else {
    ///     ...
    /// }
    /// ```
    ///
    /// here we would create a conditional jump after encoding the condition,
    /// then we would encode the then body, after this we will update the jump
    /// with the position of the else body.
    pub fn updateJump(self: *Self, idx: usize) !void {
        const offset: i18 = @intCast(self.code.items.len - idx - 1);
        const jump: inst.JInst = @bitCast(self.code.items[idx]);

        self.code.items[idx] = inst.JInst.encode(.{
            .code = jump.code,
            .reg = jump.reg,
            .offset = offset,
        });
    }

    /// emit a return instruction
    pub fn emitRet(self: *Self, reg: u6) !void {
        try self.emitJ(.RET, reg, 0);
    }

    /// emit a return void instruction
    pub fn emitRetVoid(self: *Self) !void {
        try self.emitJ(.RET_VOID, 0, 0);
    }

    /// emit a load instruction based on the value provided,
    /// small values use `LOADI`, while large values are added
    /// as constants and `LOADC` is used
    pub fn emitLoad(self: *Self, dst: u6, val: Value) !void {
        switch (val) {
            .int => |i| {
                if (i >= std.math.minInt(i12) and i <= std.math.maxInt(i12)) {
                    try self.emitI(.LOADI, dst, 0, @as(i12, @intCast(i)));
                } else {
                    const idx = try self.addConst(val);
                    try self.emitJ(.LOADC, dst, @bitCast(idx));
                }
            },
            .float => {
                const idx = try self.addConst(val);
                try self.emitJ(.LOADC, dst, @bitCast(idx));
            },
            .bool => |b| try self.emitI(.LOADI, dst, 0, if (b) 1 else 0),
            .fn_ref => |r| {
                try self.emitJ(.LOADF, dst, @intCast(r));
            },
            // this is technically a FREE, which will be handles separately
            .void => {},
        }
    }

    /// emit an instruction to load a given function
    pub fn emitLoadFn(self: *Self, dst: u6, idx: u18) !void {
        try self.emitJ(.LOADF, dst, @bitCast(idx));
    }

    fn writeIndent(writer: *std.io.Writer, i: usize) !void {
        for (0..i) |_| {
            try writer.print("  ", .{});
        }
    }

    fn fmtChunk(self: @This(), writer: *std.io.Writer, name: []const u8, depth: usize) !void {
        if (self.constants.items.len > 0) {
            try writeIndent(writer, depth);
            try writer.print(".constants\n", .{});
            for (self.constants.items, 0..) |c, i| {
                try writeIndent(writer, depth + 1);
                try writer.print("{d}: {f}\n", .{i, c});
            }
        }

        if (self.functions.items.len > 0) {
            for (self.functions.items, 0..) |f, i| {
                _ = i;
                const chunk_name = std.mem.concat(
                    self.alloc, u8, &.{"fn ", f.name}
                ) catch unreachable; // can only fail if we run out of memory
                try f.fmtChunk(writer, chunk_name, depth);
                try writer.writeByte('\n');
            }
         }

        try writeIndent(writer, depth);
        try writer.print(".{s}\n", .{name});
        try writeIndent(writer, depth + 1);
        try writer.print(".code\n", .{});
        for (self.code.items) |i| {
            try writeIndent(writer, depth + 2);
            try writeInstruction(i, writer, &self);
            try writer.writeByte('\n');
        }
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try self.fmtChunk(writer, "main", 0);
    }
};