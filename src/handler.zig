const std = @import("std");
const utils = @import("utils.zig");
const server = @import("server.zig");
const Message = @import("message.zig").Message;
const so = @import("socket.zig");
const HashMap = @import("hashmap.zig").HashMap;
const DataUnit = @import("datatypes.zig").DataUnit;
const ResponseCode = @import("message.zig").CTRL.ResponseCode;

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

pub fn accept_client(allocator: Allocator, n_fds: u16, li_fd: fd, epoll_fd: fd, map: *HashMap) !*Connection {
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

    const con = try Connection.init(allocator, con_fd, &client_addr, map);
    errdefer con.deinit();

    var event: epoll_event = undefined;
    event.data.fd = con_fd;
    event.events = sys.EPOLL.IN;
    rc = sys.epoll_ctl(epoll_fd, sys.EPOLL.CTL_ADD, con_fd, &event);
    try utils.check_syscall("epoll_creat1()", rc);

    utils.print_sockaddr("new connection from ", &client_addr);

    return con;
}

pub fn handle_read(con: *Connection) void {
    if (con.rcv_buf.is_full()) {
        l_err("rcv buffer is full, closing connection", .{});
        con.state = .wants_close;
    }

    // const cap: usize = con.rcv_buf.cap();
    // const buf: [*]u8 = con.rcv_buf.data.ptr + con.rcv_buf.hi;

    const buf = con.rcv_buf.get_free_slice().?;
    const rc = sys.read(con.fd, buf.ptr, buf.len);

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

    // pipeline width, amount of messages to be processed at a time
    const MAX_MSG = 3;
    var requests: [MAX_MSG]Message = undefined;
    var queued_msgs: u8 = 0;

    for (0..MAX_MSG) |i| {
        if (con.rcv_buf.get_data()) |s| {
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
            con.rcv_buf.move_lo(msg.len());

            requests[i] = msg;
        }
        queued_msgs += 1;
    }

    for (0..queued_msgs) |i| {
        try process_message(con, requests[i]);
    }

    if (con.rcv_buf.is_empty()) {
        con.rcv_buf.clear();
    }

    if (!con.snd_buf.is_empty()) {
        debug("writing {} responses\n", .{queued_msgs});
        handle_write(con);
    }
    return;
}

pub fn handle_write(con: *Connection) void {
    if (con.snd_buf.is_empty()) {
        warn("snd buffer is empty", .{});
        con.state = .wants_read;
    }
    const data = con.snd_buf.get_data().?;
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
            con.snd_buf.move_lo(@intCast(rc));
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

pub fn process_message(con: *Connection, msg: Message) !void {
    std.debug.assert(!con.snd_buf.is_full());

    const hdr = msg.header();
    const payload = msg.payload();

    if (hdr.ctrl.msg_type == .Response) {
        l_err("got a response, expected request", .{});
        return error.InvalidMessage;
    }

    var resp_code: ResponseCode = undefined;
    var resp_data: ?[]u8 = null;

    const req_data = DataUnit.decode(payload) catch |err| {
        l_err("invalid data for request {}\n", .{err});

        resp_code = .InvalidData;
        return;
    };

    switch (hdr.ctrl.data.Request) {
        .Echo => {
            info("processing echo request\n", .{});

            resp_code = .Ok;
            resp_data = msg.as_slice();
        },
        .Get => {
            info("processing get request\n", .{});

            if (con.map.get(payload[0..req_data.len()])) |e| {
                resp_code = .Ok;
                resp_data = e.get_val();
            } else {
                resp_code = .NotFound;
            }
        },
        .Set => {
            info("processing set request\n", .{});

            const value = try DataUnit.decode(payload[req_data.len()..@as(u32, @intCast(payload.len))]) catch |err| {
                l_err("invalid value data for set request {}\n", .{err});

                resp_code = .InvalidData;
                return;
            };

            try con.map.insert(req_data.as_slice(), value.as_slice());
            resp_code = .Ok;
        },
        .Del => {
            info("processing del request\n", .{});

            if (con.map.remove(req_data.as_slice())) |e| {
                resp_code = .Ok;
                // could alternatively return value that was removed
                e.destroy(con.al);
            } else {
                resp_code = .NotFound;
            }
        },

        else => unreachable,
    }

    const write_slice = con.snd_buf.get_free_slice();
    const resp = try Message.write_response(write_slice, resp_code, resp_data);
    con.snd_buf.move_lo(resp.len());

    return;
}
