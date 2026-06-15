const std = @import("std");
const utils = @import("utils.zig");
const handler = @import("handler.zig");

const sys = std.os.linux;
const print = std.debug.print;
const check = utils.check_syscall;

const fd = sys.fd_t;
const info = std.log.info;
const debug = std.log.debug;
const l_err = std.log.err;
const warn = std.log.warn;

pub const SocketOptions = struct {
    socket_type: SockType,
    nonblock: bool = true,
    reuse_addr: bool = true,

    const SockType = enum { TCP, UDP };
};

pub fn get_socket(opt: SocketOptions) !fd {
    const sock_type: u32 = switch (opt.socket_type) {
        .TCP => sys.SOCK.STREAM,
        .UDP => sys.SOCK.DGRAM,
    };

    const rc = sys.socket(sys.AF.INET, sock_type, 0);

    try check("socket", rc);

    const socket: fd = @intCast(rc);

    if (opt.reuse_addr) {
        const val: u32 = 1;
        std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&val)) catch |err| {
            std.log.err("setsockopt error {}", .{err});
            return err;
        };
    }

    if (opt.nonblock) try set_fd_nonblock(socket);

    return socket;
}

pub fn set_fd_nonblock(socket: fd) !void {
    const socket_flags = sys.fcntl(socket, sys.F.GETFL, 0);

    try check("fcntl get", socket_flags);

    const non_block_flag: u32 = @bitCast(sys.O{ .NONBLOCK = true });
    const rc = sys.fcntl(socket, sys.F.SETFL, socket_flags | @as(usize, non_block_flag));

    try check("fcntl set", rc);
}
