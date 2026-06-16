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
    socket_type: SockType = .TCP,
    nonblock: bool = true,
    reuse_addr: bool = true,

    const SockType = enum { TCP, UDP };
};

pub fn setup_epoll(li_sock: sys.fd_t) !sys.fd_t {
    var rc = sys.epoll_create1(0);
    try utils.check_syscall("epoll_creat1()", rc);

    const epoll_fd: fd = @intCast(rc);
    errdefer utils.close_fd(epoll_fd);

    var event: sys.epoll_event = undefined;
    event.events = sys.EPOLL.IN;
    event.data.fd = li_sock;

    rc = sys.epoll_ctl(epoll_fd, sys.EPOLL.CTL_ADD, li_sock, &event);
    try utils.check_syscall("epoll_creat1()", rc);
    return epoll_fd;
}

pub fn get_li_socket(addr: std.Io.net.IpAddress, opt: SocketOptions) !fd {
    const sock_type: u32 = switch (opt.socket_type) {
        .TCP => sys.SOCK.STREAM,
        .UDP => sys.SOCK.DGRAM,
    };

    var rc = sys.socket(sys.AF.INET, sock_type, 0);

    try check("socket", rc);

    const socket: fd = @intCast(rc);
    errdefer utils.close_fd(socket);

    if (opt.reuse_addr) {
        const val: u32 = 1;
        std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&val)) catch |err| {
            std.log.err("setsockopt error {}", .{err});
            return err;
        };
    }

    if (opt.nonblock) try set_fd_nonblock(socket);

    const ip_adrr: u32 = std.mem.readInt(u32, &addr.ip4.bytes, .little);
    const sockaddr: sys.sockaddr.in = .{ .addr = ip_adrr, .port = std.mem.nativeToBig(u16, addr.ip4.port) };
    rc = sys.bind(socket, @ptrCast(&sockaddr), @sizeOf(sys.sockaddr.in));

    try check("bind", rc);

    rc = sys.listen(socket, 1024);
    try check("listen", rc);

    return socket;
}

pub fn set_fd_nonblock(socket: fd) !void {
    const socket_flags = sys.fcntl(socket, sys.F.GETFL, 0);

    try check("fcntl get", socket_flags);

    const non_block_flag: u32 = @bitCast(sys.O{ .NONBLOCK = true });
    const rc = sys.fcntl(socket, sys.F.SETFL, socket_flags | @as(usize, non_block_flag));

    try check("fcntl set", rc);
}
