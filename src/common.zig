const std = @import("std");

pub fn BoundedArray(T: type, max_size: comptime_int) type {
    return struct {
        len: std.math.IntFittingRange(0, max_size) = 0,
        buffer: [max_size]T = undefined,

        pub fn push(self: *@This(), item: T) void {
            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn slice(self: *const @This()) []T {
            return self.buffer[0..self.len];
        }
    };
}
