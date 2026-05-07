const std = @import("std");
const assert = std.debug.assert;

pub fn BoundedArray(T: type, max_size: comptime_int) type {
    return struct {
        len: std.math.IntFittingRange(0, max_size) = 0,
        buffer: [max_size]T = undefined,

        pub fn push(self: *@This(), item: T) void {
            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn last(self: *@This()) ?T {
            return if (self.len > 0) self.buffer[self.len - 1] else null;
        }

        pub fn pop(self: *@This()) T {
            assert(self.len > 0);
            self.len -= 1;
            return self.buffer[self.len];
        }

        pub fn slice(self: *@This()) []T {
            return self.buffer[0..self.len];
        }
    };
}
