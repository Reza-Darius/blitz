const std = @import("std");
const utils = @import("utils.zig");
const message = @import("message.zig");

const linux = std.os.linux;
const posix = std.posix;
const fd = linux.fd_t;
const info = std.log.info;
const Allocator = std.mem.Allocator;

const CON_BUF_SIZE = 500;

pub fn handle_connections(alloc: Allocator, conn_fd: fd) !void {
    defer utils.close_fd(conn_fd);

    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var msg = message.Message.init(allocator);
    try msg.read_from_socket(conn_fd);

    msg.print();

    return;
}
