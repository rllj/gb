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

pub fn build_bitstring(comptime T: type, substrings: anytype) T {
    comptime switch (@typeInfo(T)) {
        .int => |info| if (info.signedness != .unsigned)
            @compileError("Bitstring must be an unsigned integer"),
        else => @compileError("Bitstring must be an unsigned integer"),
    };

    const ArgsType = @TypeOf(substrings);
    const fields_info = switch (@typeInfo(ArgsType)) {
        .@"struct" => |s| s.fields,
        else => @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType)),
    };

    comptime {
        var bits = 0;
        for (fields_info) |field| {
            bits += switch (@typeInfo(field.type)) {
                .int => |info| if (info.signedness == .unsigned) info.bits else @compileError("all arguments must be unsigned integers"),
                else => @compileError("all arguments must be unsigned integers"),
            };
        }
        if (bits != @typeInfo(T).int.bits) {
            @compileError(std.fmt.comptimePrint(
                "substrings bit length must add up to the bitstrings bit length.\nTotal substring length: {d}\nBitstring length: {d}\n",
                .{ bits, @typeInfo(T).int.bits },
            ));
        }
    }

    const Packed = comptime blk: {
        var names: [fields_info.len][]const u8 = undefined;
        var types: [fields_info.len]type = undefined;
        for (fields_info, 0..) |field, i| {
            names[fields_info.len - 1 - i] = field.name;
            types[fields_info.len - 1 - i] = field.type;
        }
        break :blk @Struct(.@"packed", T, &names, &types, &@splat(std.builtin.Type.StructField.Attributes{}));
    };

    var result: Packed = undefined;
    inline for (@typeInfo(Packed).@"struct".fields) |field| {
        @field(result, field.name) = @field(substrings, field.name);
    }

    return @bitCast(result);
}
