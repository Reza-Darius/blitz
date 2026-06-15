const std = @import("std");

const MessageError = error{ ParseError, EncodeError, AllocationError, EmptyMessage };

const MAX_MSG_LEN = 512;

pub const Message = struct {
    data: []u8,
    allocator: std.mem.Allocator,

    const HDR_SIZE: u16 = @sizeOf(Header);

    pub const Header = packed struct {
        /// total length of the message
        tot_len: u16,
    };

    pub fn init(allocator: std.mem.Allocator) Message {
        return .{
            .data = undefined,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Message) void {
        self.allocator.free(self.data);
        return;
    }

    pub fn header(self: Message) MessageError!Header {
        if (self.data.len == 0) {
            return error.EmptyMessage;
        }
        const slice = self.data[0..HDR_SIZE];
        const len = std.mem.readInt(u16, slice, .little);
        return .{
            .tot_len = len,
        };
    }

    fn write_header(self: *Message, hdr: *const Header) void {
        std.debug.assert(hdr.tot_len != 0);
        @memcpy(self.data[0..HDR_SIZE], std.mem.asBytes(hdr));
        return;
    }

    pub fn debug_print(self: Message) void {
        std.debug.print("len: {}, message: {s}", .{ self.header().len, self.data[HDR_SIZE .. HDR_SIZE + self.data.len] });
        return;
    }

    pub fn encode_string(self: *Message, str: []const u8) MessageError!void {
        if (str.len > MAX_MSG_LEN) {
            return error.EncodeError;
        }

        var buf = self.allocator.alloc(u8, str.len + 2) catch {
            return error.AllocationError;
        };

        self.data = buf;
        self.write_header(&.{ .tot_len = @as(u16, @intCast(str.len)) + HDR_SIZE });

        @memcpy(buf[HDR_SIZE .. str.len + HDR_SIZE], str);

        return;
    }
};

test "Message Encoding" {
    const allocator = std.testing.allocator;
    const message = "hello";
    try std.testing.expect(message.len == 5);
    var encoded_msg = Message.init(allocator);
    defer encoded_msg.deinit();
    try encoded_msg.encode_string(message);

    try std.testing.expect(encoded_msg.data.len == 7);
    try std.testing.expect(std.mem.eql(u8, encoded_msg.data[2 .. 2 + 5], message[0..5]));
    const header = try encoded_msg.header();
    try std.testing.expect(header.tot_len == 7);
}
