const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("chunk.zig").Value;
const Instruction = @import("instruction.zig").Instruction;

pub const StackFrame = struct {
    /// the chunk that this frame is responsible for
    chunk: *const Chunk,
    regs: [64]Value,
    /// which register the return value is placed in
    ret: u6 = 0,
    pc: usize = 0,
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

    /// run the program
    pub fn run(self: *Self, main: *const Chunk) !void {
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

            const inst = Instruction.decode(code);

            switch (inst) {
                .reg => std.debug.print("REGISTER\n", .{}),
                .imm => std.debug.print("IMMEDIATE\n", .{}),
                .jmp => std.debug.print("JUMP\n", .{}),
            }
        }
    }
};