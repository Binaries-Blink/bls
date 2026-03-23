//! The library containing the bls Vm and other utils

pub const parse = @import("vm/compile.zig").parse;
pub const compile = @import("vm/compile.zig").compile;