const std = @import("std");
const bls = @import("bls");

pub fn main() !void {
    _ = try bls.compile("test.txt");
}
