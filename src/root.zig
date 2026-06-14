const std = @import("std");
const sock = @import("socket.zig");
const handler = @import("handler.zig");
const utils = @import("utils.zig");

const linux = std.os.linux;

pub fn run_server(allocator: std.mem.Allocator, addr: std.Io.net.IpAddress) !void {
    const sock_opts: sock.SockOptions = .{ .socket_type = .TCP, .nonblock = false, .reuse_addr = true };
    const socket: linux.fd_t = try sock.get_socket(&addr, sock_opts);
    defer utils.close_fd(socket);

    var rc = linux.listen(socket, 1024);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("listen error: {}", .{err});
            return error.ListenError;
        },
    }

    std.log.info("listening on {}", .{addr});

    while (true) {
        var client_addr: linux.sockaddr.in = undefined;
        var addrlen: linux.socklen_t = @sizeOf(linux.sockaddr.in);
        rc = std.os.linux.accept(socket, @ptrCast(&client_addr), &addrlen);

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
        handler.handle_connections(allocator, client_fd) catch |err| {
            std.log.err("error when handling connection {}", .{err});
        };
    }
}


