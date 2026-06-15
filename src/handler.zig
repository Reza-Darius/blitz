const std = @import("std");
const utils = @import("utils.zig");
const Message = @import("message.zig").Message;

const sys = std.os.linux;
const posix = std.posix;
const fd = sys.fd_t;
const info = std.log.info;
const Allocator = std.mem.Allocator;

const CON_BUF_SIZE = 500;

const Connection = struct {
    fd_state: FdState,
    read_buf: []u8,
    write_buf: []u8,

    const FdState = enum {
        wants_read,
        wants_write
    };
};

pub fn handle_connections(alloc: Allocator, conn_fd: fd) !void {
    defer utils.close_fd(conn_fd);

    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var msg = Message.init(allocator);
    try msg.read_from_socket(conn_fd);

    msg.print();

    return;
}
