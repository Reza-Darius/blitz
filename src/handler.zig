const std = @import("std");
const utils = @import("utils.zig");
const server = @import("server.zig");
const Message = @import("message.zig").Message;
const so = @import("socket.zig");

const sys = std.os.linux;
const posix = std.posix;
const fd = sys.fd_t;
const epoll_event = sys.epoll_event;

const info = std.log.info;
const debug = std.log.debug;
const warn = std.log.warn;
const l_err = std.log.err;
const check = utils.check_syscall;

const Allocator = std.mem.Allocator;
const Connection = server.Connection;

pub fn accept_client(allocator: Allocator, n_fds: u16, li_fd: fd, epoll_fd: fd) !*Connection {
    var client_addr: sys.sockaddr.in = undefined;
    var addrlen: sys.socklen_t = @sizeOf(sys.sockaddr.in);
    var rc = sys.accept(li_fd, @ptrCast(&client_addr), &addrlen);

    try check("accept", rc);

    const con_fd: fd = @intCast(rc);
    errdefer utils.close_fd(con_fd);

    if (n_fds >= server.MAX_EV) {
        utils.close_fd(@intCast(rc));
        return error.MaximumConnectionsReached;
    }

    try so.set_fd_nonblock(con_fd);

    const alloc = try allocator.create(Connection);
    errdefer allocator.destroy(alloc);

    alloc.* = try Connection.init(allocator, con_fd, &client_addr);
    errdefer alloc.deinit();

    var event: epoll_event = undefined;
    event.data.fd = con_fd;
    event.events = sys.EPOLL.IN;
    rc = sys.epoll_ctl(epoll_fd, sys.EPOLL.CTL_ADD, con_fd, &event);
    try utils.check_syscall("epoll_creat1()", rc);

    utils.print_sockaddr("new connection from ", &client_addr);

    return alloc;
}

pub fn handle_read(con: *Connection) void {
    if (con.rcv_buf.is_full()) {
        l_err("rcv buffer is full, closing connection", .{});
        con.state = .wants_close;
    }

    const cap: usize = con.rcv_buf.cap();
    const buf: [*]u8 = con.rcv_buf.data.ptr + con.rcv_buf.hi;
    const rc = sys.read(con.fd, buf, cap);

    switch (sys.errno(rc)) {
        .SUCCESS => {
            if (rc == 0) {
                // socket shut down
                debug("connection closed in handle read", .{});
                con.state = .wants_close;
                return;
            }
            con.rcv_buf.hi += @intCast(rc);
            debug("success: read bytes: {}", .{rc});
        },
        .AGAIN => {
            // no data read, we wait for more
        },
        else => |err| {
            l_err("read error {}", .{err});
            con.state = .wants_close;
            return;
        },
    }

    while (con.rcv_buf.get_slice()) |s| {
        const msg = Message.parse(s) catch |err| {
            if (err == error.IncompleteMessage) {
                debug("couldnt parse message, waiting for more data, {}", .{err});
                break;
            } else {
                l_err("parse error {}", .{err});
                return;
            }
        };

        msg.print_info("received message ");
        write_response(con, &msg) catch |err| {
            l_err("couldnt write echo response, err {}", .{err});
        };

        con.rcv_buf.read_n(msg.len());
    }

    if (con.rcv_buf.is_empty()) {
        con.rcv_buf.clear();
    }

    if (!con.snd_buf.is_empty()) {
        debug("snd buffer, wanting to write", .{});
        handle_write(con);
    }
    return;
}

pub fn handle_write(con: *Connection) void {
    if (con.snd_buf.is_empty()) {
        warn("snd buffer is empty", .{});
        con.state = .wants_read;
    }
    const data = con.snd_buf.get_slice().?;
    const rc = sys.write(con.fd, data.ptr, data.len);

    switch (sys.errno(rc)) {
        .SUCCESS => {
            if (rc == 0) {
                // socket shut down
                debug("connection closed in handle write", .{});
                con.state = .wants_close;
                return;
            }
            debug("nbytes written: {}", .{rc});
            con.snd_buf.read_n(@intCast(rc));
        },
        .AGAIN => {
            // cant write at this time
        },
        else => |err| {
            l_err("write error {}", .{err});
            con.state = .wants_close;
            return;
        },
    }

    if (con.snd_buf.is_empty()) {
        debug("snd buffer is empty, waiting for reads again", .{});
        con.snd_buf.clear();
        con.state = .wants_read;
    } else {
        con.state = .wants_write;
    }
    return;
}

pub fn write_response(con: *Connection, msg: *const Message) !void {
    try con.snd_buf.append(msg.as_slice());

    return;
}
