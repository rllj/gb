const std = @import("std");
const SM83 = @import("SM83.zig");

pub fn main() void {
    std.testing.refAllDeclsRecursive(SM83);
}
