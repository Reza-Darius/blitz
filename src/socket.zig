const std = @import("std");
const utils = @import("utils.zig");
const handler = @import("handler.zig");

const linux = std.os.linux;
const print = std.debug.print;
const check = utils.check_syscall;

pub const Server = struct {
    socket: linux.fd_t,
    addr: std.Io.net.IpAddress,
    allocator: std.mem.Allocator,

    pub const SockOptions = struct {
        socket_type: SockType,
        nonblock: bool = true,
        reuse_addr: bool = true,

        const SockType = enum { TCP, UDP };
    };

    /// initializes a listening server
    pub fn init(allocator: std.mem.Allocator, addr: std.Io.net.IpAddress, opt: SockOptions) !Server {
        var rc = switch (opt.socket_type) {
            .TCP => linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0),
            .UDP => linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0),
        };

        try check("socket", rc);

        const socket: linux.fd_t = @intCast(rc);

        if (opt.reuse_addr) {
            const val: u32 = 1;
            std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&val)) catch |err| {
                std.log.err("setsockopt error {}", .{err});
                return err;
            };
        }

        if (opt.nonblock) try set_non_blocking(socket);

        const ip_adrr: u32 = std.mem.readInt(u32, &addr.ip4.bytes, .little);
        const sockaddr: linux.sockaddr.in = .{ .addr = ip_adrr, .port = std.mem.nativeToBig(u16, addr.ip4.port) };
        rc = linux.bind(socket, @ptrCast(&sockaddr), @sizeOf(linux.sockaddr.in));

        try check("bind", rc);

        rc = linux.listen(socket, 1024);
        try check("listen", rc);

        return .{
            .socket = socket,
            .addr = addr,
            .allocator = allocator,
        };
    }

    /// runs the main server loop
    pub fn run(self: *Server) !void {
        defer utils.close_fd(self.socket);

        std.log.info("listening on {}", .{self.addr});

        while (true) {
            var client_addr: linux.sockaddr.in = undefined;
            var addrlen: linux.socklen_t = @sizeOf(linux.sockaddr.in);
            const rc = std.os.linux.accept(self.socket, @ptrCast(&client_addr), &addrlen);

            // we might want to react to different errors here
            check("accept", rc) catch {
                continue;
            };

            utils.print_sockaddr("new connection from ", &client_addr);

            const client_fd: linux.fd_t = @intCast(rc);
            handler.handle_connections(self.allocator, client_fd) catch |err| {
                std.log.err("error when handling connection {}", .{err});
            };
        }
    }
};

fn set_non_blocking(socket: linux.fd_t) !void {
    const socket_flags = linux.fcntl(socket, linux.F.GETFL, 0);

    try check("fcntl get", socket_flags);

    const non_block_flag: u32 = @bitCast(linux.O{ .NONBLOCK = true });
    const rc = linux.fcntl(socket, linux.F.SETFL, socket_flags | @as(usize, non_block_flag));

    try check("fcntl set", rc);
}
