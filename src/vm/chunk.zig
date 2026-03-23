const std = @import("std");
const inst = @import("instruction.zig");

pub const Chunk = struct {
    alloc: std.mem.Allocator,
    /// the actual bytecode for this chunk
    code: std.ArrayList(u32),

    const Self = @This();

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
    pub fn emitJ(self: *Self, op: inst.Opcode, dst: u6, offset: i18) !void {
        try self.code.append(self.alloc, inst.JInst.encode(.{
            .code = @intFromEnum(op),
            .dst = dst,
            .offset = offset,
        }));
    }
};