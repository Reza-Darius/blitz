const std = @import("std");
const utils = @import("utils.zig");

const sys = std.os.linux;
const posix = std.posix;

const MessageError = error{ ParseError, EncodeError, AllocationError, EmptyMessage };

pub const Message = struct {
    data: []u8,
    allocator: std.mem.Allocator,

    const HDR_SIZE: u16 = @sizeOf(Header);
    const MAX_MSG_LEN = 512;

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

    pub fn header(self: Message) MessageError!*Header {
        if (self.data.len == 0) {
            return error.EmptyMessage;
        }
        const hdr: *Header = @ptrCast(@alignCast(self.data[0..HDR_SIZE]));
        return hdr;
        // const slice = self.data[0..HDR_SIZE];
        // const len = std.mem.readInt(u16, slice, .little);
        // return .{
        //     .tot_len = len,
        // };
    }

    fn write_header(self: *Message, hdr: *const Header) void {
        std.debug.assert(hdr.tot_len != 0);
        @memcpy(self.data[0..HDR_SIZE], std.mem.asBytes(hdr));
        return;
    }

    pub fn print(self: Message) void {
        const hdr = self.header() catch unreachable;
        std.debug.print("len: {}, message: {s}\n", .{ hdr.tot_len, self.data[HDR_SIZE..hdr.tot_len] });
        return;
    }

    pub fn encode_string(self: *Message, str: []const u8) MessageError!void {
        if (str.len + HDR_SIZE > MAX_MSG_LEN) {
            return error.EncodeError;
        }

        const hdr: Header = .{
            .tot_len = HDR_SIZE + @as(u16, @intCast(str.len)),
        };

        self.data = self.allocator.alloc(u8, hdr.tot_len) catch {
            return error.AllocationError;
        };

        self.write_header(&hdr);

        @memcpy(self.data[HDR_SIZE..hdr.tot_len], str);

        return;
    }

    pub fn read_from_socket(self: *Message, socket: sys.fd_t) !void {
        var hdr: Header = undefined;
        try utils.read_socket(socket, std.mem.asBytes(&hdr));

        if (hdr.tot_len < 3) {
            return error.InvalidMessage;
        }

        self.data = try self.allocator.alloc(u8, hdr.tot_len);
        self.write_header(&hdr);
        try utils.read_socket(socket, self.data[HDR_SIZE..hdr.tot_len]);

        return;
    }

    pub fn write(self: Message, writer: *std.Io.Writer) !void {
        try writer.writeAll(self.data);
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
