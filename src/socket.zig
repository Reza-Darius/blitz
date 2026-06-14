const std = @import("std");
const utils = @import("utils.zig");
const handler = @import("handler.zig");

const linux = std.os.linux;
const print = std.debug.print;

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

        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => |err| {
                std.log.err("socket error: {}", .{err});
                return error.SocketError;
            },
        }

        const socket: linux.fd_t = @intCast(rc);

        if (opt.reuse_addr) {
            const val: u32 = 1;
            std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&val)) catch |err| {
                std.log.err("setsockopt error {}", .{err});
                return err;
            };
        }

        if (opt.nonblock) try set_non_blocking(socket);

        const sockaddr: linux.sockaddr.in = .{ .addr = std.mem.readInt(u32, &addr.ip4.bytes, .little), .port = std.mem.nativeToBig(u16, addr.ip4.port) };
        rc = linux.bind(socket, @ptrCast(&sockaddr), @sizeOf(linux.sockaddr.in));

        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => |err| {
                std.log.err("bind error: {}", .{err});
                return error.BindError;
            },
        }

        rc = linux.listen(socket, 1024);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => |err| {
                std.log.err("listen error: {}", .{err});
                return error.ListenError;
            },
        }
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

            switch (linux.errno(rc)) {
                .SUCCESS => {},
                else => |err| {
                    std.log.err("accept error: {}", .{err});
                    break;
                },
            }

            utils.print_sockaddr("new connection from ", &client_addr);

            const client_fd: linux.fd_t = @intCast(rc);
            defer utils.close_fd(client_fd);
            handler.handle_connections(self.allocator, client_fd) catch |err| {
                std.log.err("error when handling connection {}", .{err});
            };
        }
    }
};

fn set_non_blocking(socket: linux.fd_t) !void {
    const socket_flags = linux.fcntl(socket, linux.F.GETFL, 0);
    switch (linux.errno(socket_flags)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("fcntl get error: {}", .{err});
            return error.FcntlGetError;
        },
    }

    const non_block_flag: u32 = @bitCast(linux.O{ .NONBLOCK = true });
    const rc = linux.fcntl(socket, linux.F.SETFL, socket_flags | @as(usize, non_block_flag));
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("fcntl set error: {}", .{err});
            return error.FcntlSetError;
        },
    }
}
