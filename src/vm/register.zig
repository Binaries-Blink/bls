const std = @import("std");

/// an allocator responsible for tracking and updating register usage
pub const RegisterAllocator = struct {
    /// a bitmask of all registers currently in use
    used: u64 = 0,

    const Self = @This();

    /// allocate the lowest free register returning its index,
    /// if none are available return an error
    pub fn alloc(self: *Self) !u6 {
        const free_regs = ~self.used;
        if (free_regs == 0) return error.RegistersFull;
        const reg: u6 = @intCast(@ctz(free_regs));
        self.used |= @as(u64, 1) << reg;
        return reg;
    }

    /// mark a register as no longer in use
    pub fn free(self: *Self, reg: u6) void {
        self.used &= ~(@as(u64, 1) << reg);
    }

    /// mark a register as in use without allocating
    pub fn markUsed(self: *Self, reg: u6) void {
        self.used |= @as(u64, 1) << reg;
    }

    /// free all registers specified by mask
    pub fn freeAll(self: *Self, mask: u64) void {
        self.used &= ~mask;
    }
};