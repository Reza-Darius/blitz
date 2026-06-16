const std = @import("std");
const utils = @import("utils.zig");

const sys = std.os.linux;
const posix = std.posix;

const MessageError = error { 
    ParseError,
    EncodeError,
    AllocationError,
    EmptyMessage,
    InvalidDataLen,
    IncompleteMessage,
    HeaderParseError,
    InvalidVersion,
    InvalidCommand,
    InvalidMessageSize
};

const HDR_SIZE = @sizeOf(Header);
const MAX_MSG_LEN = 512;
const PAYLOAD_MIN_SIZE = 1;

pub const Header = packed struct(u24) {
    version: Version,
    cmd: CMD,
    pay_len: u16,
};

pub const CMD = enum(u6) {
    Set = 0,
    Retrieve = 1,
    Msg = 2,
};

const SUPPORTED_VERSION = Version.V1;

pub const Version = enum(u2) {
    V1 = 0,
    _,
};

pub const Message = struct {
    data: [*]u8,

    pub fn try_parse(data: []u8) MessageError!Message {
        if (data.len < HDR_SIZE + PAYLOAD_MIN_SIZE) {
            return error.IncompleteMessage;
        }

        const hdr = try parse_header(data);

        if (hdr.pay_len + HDR_SIZE > data.len) {
            std.log.err("message incomplete, bytes missing: {}", .{hdr.pay_len - data.len - HDR_SIZE});
            return error.IncompleteMessage;
        }
        return .{ .data = data.ptr };
    }

    fn parse_header(data: []u8) MessageError!*align(1) Header {
        if (data.len < HDR_SIZE) {
            std.log.err("invalid data size for parsing header", .{});
            return error.HeaderParseError;
        }

        const hdr = std.mem.bytesAsValue(Header, data[0..HDR_SIZE]);

        if (hdr.version != SUPPORTED_VERSION) {
            return error.InvalidVersion;
        }

        _ = std.enums.fromInt(CMD, @intFromEnum(hdr.cmd)) orelse return error.InvalidCommand;

        if (hdr.pay_len + HDR_SIZE > MAX_MSG_LEN) {
            return error.InvalidMessageSize;
        }
        if (hdr.pay_len < PAYLOAD_MIN_SIZE) {
            std.log.err("invalid pay_len {}", .{hdr.pay_len});
            return error.HeaderParseError;
        }
        return hdr;
    }

    fn write_header(out: []u8, hdr: *const Header) void {
        std.debug.assert(out.len >= HDR_SIZE);
        std.debug.assert(hdr.pay_len != 0);

        @memcpy(out[0..HDR_SIZE], std.mem.asBytes(hdr));
        return;
    }

    /// doesnt do any checks
    pub fn header(self: Message) *align(1) Header {
        return std.mem.bytesAsValue(Header, self.data[0..HDR_SIZE]);
    }

    pub fn print(self: Message) void {
        const hdr = self.header();
        std.debug.print("version={}, cmd={}, pay_len={}, payload: {s}\n", .{ hdr.version, hdr.cmd, hdr.pay_len, self.data[HDR_SIZE .. HDR_SIZE + hdr.pay_len] });
        return;
    }

    pub fn print_info(self: Message, msg: ?[]const u8) void {
        const hdr = self.header();
        if (msg) |m| {
            std.log.info("{s}version={}, cmd={}, pay_len={}, payload: {s}\n", .{ m, hdr.version, hdr.cmd, hdr.pay_len, self.data[HDR_SIZE .. HDR_SIZE + hdr.pay_len] });
            return;
        }
        std.log.info("version={}, cmd={}, pay_len={}, payload: {s}\n", .{ hdr.version, hdr.cmd, hdr.pay_len, self.data[HDR_SIZE .. HDR_SIZE + hdr.pay_len] });
        return;
    }

    pub fn encode_msg(out: []u8, str: []const u8) MessageError!Message {
        if (str.len > MAX_MSG_LEN) {
            std.log.err("provided string exceeds max message length", .{});
            return error.EncodeError;
        }
        if (str.len + HDR_SIZE > out.len) {
            std.log.err("provided buffer is too small", .{});
            return error.EncodeError;
        }

        const hdr: Header = .{
            .version = .V1,
            .cmd = .Msg,
            .pay_len = @as(u16, @intCast(str.len)),
        };

        Message.write_header(out, &hdr);
        @memcpy(out[HDR_SIZE .. HDR_SIZE + hdr.pay_len], str);

        return .{ .data = out.ptr };
    }

    pub fn read_from_socket(self: *Message, socket: sys.fd_t) !void {
        var hdr: Header = undefined;
        try utils.read_socket(socket, std.mem.asBytes(&hdr));

        if (hdr.tot_len < 3) {
            return error.InvalidMessage;
        }

        self.payload = try self.allocator.alloc(u8, hdr.tot_len);
        self.write_header(&hdr);
        try utils.read_socket(socket, self.payload[HDR_SIZE..hdr.tot_len]);

        return;
    }

    pub fn write(self: Message, writer: *std.Io.Writer) !void {
        const hdr = self.header();
        const bytes = self.data[0 .. HDR_SIZE + hdr.pay_len];
        try writer.writeAll(bytes);
        return;
    }

    pub fn as_slice(self: Message) []u8 {
        const hdr = self.header();
        return self.data[0 .. HDR_SIZE + hdr.pay_len];
    }

    pub fn len(self: Message) u16 {
        return std.mem.readInt(u16, self.data[1..3], .little) + HDR_SIZE;
    }
};

test "Message Encoding" {
    const allocator = std.testing.allocator;
    const alloc = try allocator.alloc(u8, 10);
    defer allocator.free(alloc);

    const message = "hello";
    try std.testing.expect(message.len == 5);
    const encoded_msg = try Message.encode_msg(alloc, message);
    const header = encoded_msg.header();

    try std.testing.expect(header.pay_len == message.len);
    try std.testing.expect(std.mem.eql(u8, encoded_msg.data[HDR_SIZE .. HDR_SIZE + header.pay_len], message[0..5]));
    encoded_msg.print();
}
