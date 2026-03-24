const std = @import("std");
const inst = @import("instruction.zig");

pub const Value = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
};

pub const Chunk = struct {
    alloc: std.mem.Allocator,
    /// the actual bytecode for this chunk
    code: std.ArrayList(u32),
    constants: std.ArrayList(Value),
    functions: std.ArrayList(*Chunk),

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Chunk {
        return .{
            .alloc = alloc,
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
                    try self.emitI(.LOADI, dst, 0, i);
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
        }
    }

    /// emit an instruction to load a given function
    pub fn emitLoadFn(self: *Self, dst: u6, idx: u18) !void {
        try self.emitJ(.LOADF, dst, @bitCast(idx));
    }
};