const std = @import("std");

const MessageError = error{ParseError, EncodeError};

const MAX_MSG_LEN = 512;

pub const Message = struct {
    data: []u8,

    pub const Header = packed struct {
        len: u16,
    };

    pub fn parse(data: []const u8) MessageError!Message {
        if (data.len < 3) {
            std.log.debug("parse error, data len {} is invalid", .{data.len});
            return error.ParseError;
        }
        const len = std.mem.readInt(u16, &data[0..2], .big);
        return .{ .data = data[0..len] };
    }

    pub fn header(self: *const Message) *Header {
        const hdr: *Header = @ptrCast(&self.data[0..2]);
        return hdr;
    }

    pub fn debug_print(self: *const Message) void {
        std.debug.print("len: {}, message: {s}", .{ self.header().len, self.data[2 .. 2 + self.data.len] });
        return;
    }

    /// encodes the given string, the caller is responsible for freeing the resulting pointer
    pub fn encode_string(allocator: std.mem.Allocator, str: []const u8) MessageError!*Message {
        if (str.len > MAX_MSG_LEN) {
            return error.EncodeError;
        }

        var buf = allocator.alloc(u8, str.len + 2);

        std.mem.writeInt(u16, buf, str.len, .big);
        @memcpy(buf[2..str.len + 2], str);

        return;
    }
};
