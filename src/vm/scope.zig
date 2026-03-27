const std = @import("std");
const Value = @import("chunk.zig").Value;

pub const Symbol = union(enum) {
    register: u6,
    constant: Value,
};

pub const Scope = struct {
    /// name -> symbol
    symbols: std.StringHashMap(Symbol),

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) Scope {
        return .{
            .symbols = std.StringHashMap(Symbol).init(alloc)
        };
    }

    pub fn deinit(self: *Self) void {
        self.symbols.deinit();
    }

    /// add a symbol with the given name to the scope
    pub fn put(self: *Self, name: []const u8, sym: Symbol) !void {
        try self.symbols.put(name, sym);
    }

    /// get the symbol corresponding to the given name,
    /// returns null if the name is not defined
    pub fn get(self: *Self, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }


};