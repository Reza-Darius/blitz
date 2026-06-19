const std = @import("std");
const utils = @import("utils.zig");
const DataUnit = @import("datatypes.zig").DataUnit;

const sys = std.os.linux;
const posix = std.posix;

const MessageError = error{ ParseError, EncodeError, AllocationError, EmptyMessage, InvalidDataLen, IncompleteMessage, HeaderParseError, InvalidVersion, InvalidCommand, InvalidMessageSize, InvalidRequest, InvalidResponse };

/// backing integer of the header
const HDR_INT = @typeInfo(Header).@"struct".backing_integer.?;
const HDR_SIZE = hdr_size();

const MAX_MSG_LEN = 512;

fn hdr_size() comptime_int {
    const bits = @bitSizeOf(HDR_INT);
    if (bits % 8 != 0) {
        @compileError("invalid header size");
    }
    return bits / 8;
}

// schema in bits: [2b Version][1b MsgType][5b CTRL data][16b pay len][...]
pub const Header = packed struct(u24) {
    version: Version = SUPPORTED_VERSION,
    ctrl: CTRL,
    pay_len: u16 = 0,
};

const SUPPORTED_VERSION = Version.V1;

pub const Version = enum(u2) {
    V1,
    _,
};

pub const CTRL = packed struct(u6) {
    msg_type: MsgType,
    data: packed union(u5) { Request: RequestCMD, Response: ResponseCode },

    pub const MsgType = enum(u1) {
        Request,
        Response,
    };

    pub const RequestCMD = enum(u5) {
        Get,
        Set,
        Del,
        Echo,
        // this field enables printing, should be deprecated
        _,
    };

    pub const ResponseCode = enum(u5) {
        Ok,
        Err,
        NotFound,
        InvalidData,
        // this field enables printing, should be deprecated
        _,
    };

    fn validate(ctrl: CTRL) MessageError!void {
        const req_fields_len = comptime @typeInfo(RequestCMD).@"enum".fields.len;

        inline for (0..req_fields_len) |idx| {
            const v = @typeInfo(RequestCMD).@"enum".fields[idx].value;
            if (v != idx) {
                @compileError("cant designate value to CTRL data field");
            }
        }

        const resp_fields_len = comptime @typeInfo(ResponseCode).@"enum".fields.len;

        inline for (0..resp_fields_len) |idx| {
            const v = @typeInfo(ResponseCode).@"enum".fields[idx].value;
            if (v != idx) {
                @compileError("cant designate value to CTRL data field");
            }
        }

        switch (ctrl.msg_type) {
            .Request => {
                const i = @intFromEnum(ctrl.data.Request);
                if (i >= req_fields_len) {
                    return error.InvalidRequest;
                }
            },
            .Response => {
                const i = @intFromEnum(ctrl.data.Response);
                if (i >= resp_fields_len) {
                    return error.InvalidRequest;
                }
            },
        }
        return;
    }
};

pub const Message = struct {
    data: [*]u8,

    pub fn parse(data: []u8) MessageError!Message {
        std.debug.assert(data.len != 0);

        if (data.len < HDR_SIZE) {
            return error.IncompleteMessage;
        }

        const hdr = try parse_header(data[0..HDR_SIZE]);

        if (hdr.pay_len + HDR_SIZE > data.len) {
            std.log.err("message incomplete, bytes missing: {}", .{hdr.pay_len - data.len - HDR_SIZE});
            return error.IncompleteMessage;
        }
        return .{ .data = data.ptr };
    }

    fn parse_header(data: *[HDR_SIZE]u8) MessageError!Header {
        if (data.len < HDR_SIZE) {
            std.log.err("invalid data size for parsing header", .{});
            return error.HeaderParseError;
        }

        const hdr_int = std.mem.readInt(HDR_INT, data, .big);
        const hdr: Header = @bitCast(hdr_int);

        if (hdr.version != SUPPORTED_VERSION) {
            return error.InvalidVersion;
        }

        try hdr.ctrl.validate();

        if (hdr.pay_len + HDR_SIZE > MAX_MSG_LEN) {
            return error.InvalidMessageSize;
        }

        return hdr;
    }

    fn write_header(out: *[HDR_SIZE]u8, hdr: Header) void {
        const hi: HDR_INT = @bitCast(hdr);
        // const le_bytes = std.mem.asBytes(&hi);
        // std.debug.print("header bytes lil endian: {} {} {}\n", .{ le_bytes[0], le_bytes[1], le_bytes[2] });
        std.mem.writeInt(HDR_INT, out, hi, .big);
        // std.debug.print("header bytes big endian: {} {} {}\n", .{ out[0], out[1], out[2] });
        return;
    }

    /// doesnt do any checks
    pub fn header(self: Message) Header {
        const hdr_int = std.mem.readInt(HDR_INT, self.data[0..HDR_SIZE], .big);
        return @bitCast(hdr_int);
    }

    pub fn print(self: Message) void {
        const hdr = self.header();
        std.debug.print("version={}, ctrl={}, pay_len={}, payload: {s}\n", .{ hdr.version, hdr.ctrl, hdr.pay_len, self.data[HDR_SIZE .. HDR_SIZE + hdr.pay_len] });
        return;
    }

    pub fn print_info(self: Message, msg: ?[]const u8) void {
        const hdr = self.header();
        if (msg) |m| {
            std.log.info("{s}version={}, ctrl={}, pay_len={}, payload: {s}\n", .{ m, hdr.version, hdr.ctrl, hdr.pay_len, self.data[HDR_SIZE .. HDR_SIZE + hdr.pay_len] });
        } else {
            std.log.info("version={}, ctrl={}, pay_len={}, payload: {s}\n", .{ hdr.version, hdr.ctrl, hdr.pay_len, self.data[HDR_SIZE .. HDR_SIZE + hdr.pay_len] });
        }
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
            .ctrl = .{ .msg_type = .Request, .data = .{ .Request = .Echo } },
            .pay_len = @as(u16, @intCast(str.len)),
        };

        Message.write_header(out[0..HDR_SIZE], hdr);
        @memcpy(out[HDR_SIZE .. HDR_SIZE + hdr.pay_len], str);

        return .{ .data = out.ptr };
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
        const hdr = self.header();
        return hdr.pay_len + HDR_SIZE;
    }

    pub fn payload(self: Message) []u8 {
        const hdr = self.header();
        return self.data[HDR_SIZE .. HDR_SIZE + hdr.pay_len];
    }

    /// returns Message pointer into written response
    pub fn write_response(out: []u8, code: CTRL.ResponseCode, data: ?[]u8) !Message {
        if (out.len < HDR_SIZE) {
            std.log.err("passed out buffer has insufficient size {}\n", .{out.len});
            return error.ResponseWriteErro;
        }

        var response_hdr: Header = .{ .version = SUPPORTED_VERSION, .ctrl = .{ .msg_type = .Response }, .pay_len = 0 };

        // write header
        switch (code) {
            .Ok => {
                response_hdr.ctrl = .{
                    .data = CTRL.ResponseCode.Ok,
                };
            },
            .Err => {
                response_hdr.ctrl = .{
                    .data = CTRL.ResponseCode.Err,
                };
            },
            .NotFound => {},
        }

        write_header(out[0..HDR_SIZE], response_hdr);

        if (data) |d| {
            response_hdr = @intCast(d.len());
            @memcpy(out[HDR_SIZE..out.len], d);
        }

        return .{
            .data = out.ptr,
        };
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
    std.debug.print("header {any}\n", .{encoded_msg.data[0..HDR_SIZE]});
    std.debug.print("pay len {x}\n", .{header.pay_len});

    try std.testing.expect(header.pay_len == message.len);
    try std.testing.expect(std.mem.eql(u8, encoded_msg.data[HDR_SIZE .. HDR_SIZE + header.pay_len], message[0..5]));
    encoded_msg.print();
}

test "faulty ctrl" {
    const allocator = std.testing.allocator;

    const message = "bad msg";
    var buf = try allocator.alloc(u8, HDR_SIZE + message.len);
    defer allocator.free(buf);

    const bad_ctrl: CTRL = .{
        .msg_type = .Request,
        .data = @bitCast(@as(u5, 30)),
    };
    const hdr: Header = .{
        .version = .V1,
        .ctrl = bad_ctrl,
        .pay_len = message.len,
    };
    Message.write_header(buf[0..HDR_SIZE], hdr);
    @memcpy(buf[HDR_SIZE..], message);
    const res = Message.parse(buf);

    try std.testing.expect(res == error.InvalidRequest);
}

test "faulty version" {
    const allocator = std.testing.allocator;

    const message = "bad msg";
    var buf = try allocator.alloc(u8, HDR_SIZE + message.len);
    defer allocator.free(buf);

    const bad_version: Version = @enumFromInt(@as(u2, 3));
    const hdr: Header = .{
        .version = bad_version,
        .ctrl = .{ .msg_type = .Request, .data = .{ .Request = .Echo } },
        .pay_len = message.len,
    };
    Message.write_header(buf[0..HDR_SIZE], hdr);
    @memcpy(buf[HDR_SIZE..], message);
    const res = Message.parse(buf);

    try std.testing.expect(res == error.InvalidVersion);
}

// test "endian memes" {
//     const buf: []u8 = undefined;
//     const a: u5 = 2;
//     std.mem.writePackedInt(u5, buf, 3, a, .native);
//     std.debug.print("le {b}", .{buf[0]});
// }
