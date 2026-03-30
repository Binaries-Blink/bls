const std = @import("std");
const bls = @import("bls");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    const alloc = arena.allocator();

    const root = try bls.parse(alloc, "test.txt");
    const main_chunk = try bls.compile(alloc, root);

    std.debug.print("{f}", .{main_chunk});

    var vm = try bls.Vm.init(alloc);
    try vm.run(main_chunk);
}
