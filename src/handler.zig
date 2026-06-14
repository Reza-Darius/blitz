const std = @import("std");
const utils = @import("utils.zig");

const linux = std.os.linux;
const posix = std.posix;
const fd = linux.fd_t;
const info = std.log.info;
const Allocator = std.mem.Allocator;

const CON_BUF_SIZE = 200;

pub fn handle_connections(alloc: Allocator, conn_fd: fd) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const allocator = arena.allocator();
    const buf = try allocator.alloc(u8, CON_BUF_SIZE);

    try utils.read_socket(conn_fd, buf);

    info("buf: {s}", .{buf});

    return;
}
