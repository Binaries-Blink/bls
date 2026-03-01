const std = @import("std");
const bls = @import("bls");

pub fn main() !void {
    const root = try bls.compile("test.txt");
     _ = root;
}
