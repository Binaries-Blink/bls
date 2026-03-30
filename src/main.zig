const std = @import("std");
const bls = @import("bls");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    const alloc = arena.allocator();

    const root = try bls.parse(alloc, "test.txt");
    const chunks = try bls.compile(alloc, root);
    for (chunks) |chunk| {
        std.debug.print("{f}", .{chunk});
    }

    var vm = bls.Vm.init(alloc);
    vm.run(chunks);
}
