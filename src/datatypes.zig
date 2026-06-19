const std = @import("std");

const l_err = std.log.err;

// schema: [1 Byte DataType][x Bytes Data]
pub const DataUnit = union(DataType) {
    String: struct {
        len: u16,
        data: [*]const u8,
    },
    Integer: i64,
    Float: f64,
    Boolean: bool,

    Array: struct {
        len: u16,
        data: [*]const DataUnit,
    },

    pub const DataType = enum(u8) {
        String,
        Integer,
        Float,
        Boolean,

        Array,
    };

    /// size data type field
    const s_dt = @sizeOf(DataType);
    /// size string length
    const s_sl = @sizeOf(u16);
    /// size float
    const s_fl = @sizeOf(f64);
    /// size int
    const s_in = @sizeOf(i64);
    /// size bool
    const s_bo = @sizeOf(bool);

    /// decodes bytes, lifetime is tied to input for strings and arrays
    pub fn decode(data: []const u8) !DataUnit {
        std.debug.assert(data.len != 0);

        const dt = try read_type(data[0]);
        const slice = data[1..data.len];

        return switch (dt) {
            .String => parse_string(slice),
            .Integer => parse_int(slice),
            .Float => parse_float(slice),
            .Boolean => parse_bool(slice[0]),

            else => {
                @panic("not implemented yet");
            },
        };
    }

    fn parse_string(data: []const u8) !DataUnit {
        if (data.len < s_dt + s_sl) {
            l_err("infalid data len for string", .{});
            return error.StringParseError;
        }

        const slen = std.mem.readInt(u16, data[0..s_sl], .big);

        if (data.len < slen - s_sl) {
            l_err("infalid data len for string", .{});
            return error.StringParseError;
        }

        return DataUnit{ .String = .{
            .len = slen,
            .data = data.ptr + s_sl,
        } };
    }

    fn parse_int(data: []const u8) !DataUnit {
        if (data.len < @sizeOf(i64)) {
            l_err("infalid data len for integer", .{});
            return error.IntegerParseError;
        }
        return DataUnit{ .Integer = std.mem.readInt(i64, data[0..s_in], .big) };
    }

    fn parse_float(data: []const u8) !DataUnit {
        if (data.len < @sizeOf(f64)) {
            l_err("infalid data len for float", .{});
            return error.FloatParseError;
        }
        return DataUnit{ .Integer = std.mem.readInt(f64, data[0..s_fl], .big) };
    }

    fn parse_bool(data: u8) !DataUnit {
        if (data != 0 or data != 1) {
            l_err("invalid bit pattern for bool", .{});
            return error.BoolParseError;
        }
        return DataUnit{ .Boolean = if (data == 1) true else false };
    }

    fn read_type(data: u8) !DataType {
        if (std.enums.fromInt(DataType, data)) |r| {
            return r;
        } else {
            return error.InvalidDataTypeField;
        }
        // const dt_field_len = comptime @typeInfo(DataType).@"enum".fields.len;
        //
        // inline for (0..dt_field_len) |idx| {
        //     const v = @typeInfo(DataType).@"enum".fields[idx].value;
        //     if (v != idx) {
        //         @compileError("cant designate value to data type field");
        //     }
        // }
        //
        // if (data >= dt_field_len) {
        //     l_err("invalid data type field", .{});
        //     return error.InvalidDataTypeField;
        // } else {
        //     return std.enums.fromInt(DataType, data).?;
        // }
    }

    // writes the dataunit as bytes to out
    pub fn encode(self: DataUnit, out: []u8) !u32 {
        return switch (self) {
            .String => |v| encode_string(out, v.len, v.data),
            .Integer => |v| encode_int(out, v),
            .Float => |v| encode_float(out, v),
            .Boolean => |v| encode_bool(out, v),
        };
    }

    fn encode_string(out: []u8, slen: u16, data: [*]u8) !u32 {
        const size = slen + s_sl + s_dt;
        if (out.len < size) {
            l_err("invalid out length for string encoding");
            return error.EncodeStringError;
        }
        out[0] = @intFromEnum(DataType.String);
        std.mem.writeInt(u16, out[1..3], slen, .big);
        @memcpy(out[3 .. 3 + slen], data[0..slen]);
        return size;
    }

    fn encode_int(out: []u8, data: i64) !u32 {
        const size = s_in + s_dt;
        if (out.len < size) {
            l_err("invalid out length for integer encoding");
            return error.EncodeStringError;
        }
        out[0] = @intFromEnum(DataType.Integer);
        std.mem.writeInt(i64, out[1 .. 1 + s_in], data, .big);
        return size;
    }

    fn encode_float(out: []u8, data: f64) !u32 {
        const size = s_fl + s_dt;
        if (out.len < size) {
            l_err("invalid out length for float encoding");
            return error.EncodeStringError;
        }
        out[0] = @intFromEnum(DataType.Float);
        std.mem.writeInt(f64, out[1 .. 1 + s_fl], data, .big);
        return size;
    }

    fn encode_bool(out: []u8, data: bool) !u32 {
        const size = s_bo + s_dt;
        if (out.len < size) {
            l_err("invalid out length for bool encoding");
            return error.EncodeStringError;
        }
        out[0] = @intFromEnum(DataType.Boolean);
        out[1] = @intFromBool(data);
        return size;
    }

    pub fn len(self: *DataType) u32 {
        return switch (self) {
            .String => |*v| 1 + 2 + v.len,
            .Integer, .Float => 1 + 4,
            .Boolean => 1 + 1,
        };
    }

    pub fn string_to_unit(msg: []const u8,) DataUnit {
        return .{
            .String = .{
                .len = msg.len,
                .data = msg.ptr
            }
        };
    }
};
