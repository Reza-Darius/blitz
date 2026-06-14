const std = @import("std");

const linux = std.os.linux;
const posix = std.posix;
const fd = linux.fd_t;
const info = std.log.info;
const Allocator = std.mem.Allocator;

pub fn handle_connections(alloc: Allocator, conn_fd: fd) !void {
    const buf = try alloc.alloc(u8, 200);
    defer alloc.free(buf);

    const bytes_read  = try posix.read(conn_fd, buf);

    info("bytes read: {}", .{bytes_read});
    info("buf: {s}", .{buf});

    return;
}
