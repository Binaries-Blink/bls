const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("chunk.zig").Value;

pub const StackFrame = struct {
    /// the chunk that this frame is responsible for
    chunk: *Chunk,
    pc: usize,
    regs: [64]Value,
    /// which register the return value is placed in
    ret: u6
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
    pub fn run(self: *Self, main: Chunk) !void {
        _ = self;
        _ = main;
        return error.todo;
    }
};