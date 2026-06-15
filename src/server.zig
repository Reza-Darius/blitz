const std = @import("std");
const utils = @import("utils.zig");
const handler = @import("handler.zig");
const so = @import("socket.zig");

const sys = std.os.linux;
const print = std.debug.print;
const check = utils.check_syscall;

const info = std.log.info;
const debug = std.log.debug;
const l_err = std.log.err;
const warn = std.log.warn;

const fd = sys.fd_t;
const epoll_event = sys.epoll_event;
const Allocator = std.mem.Allocator;

const MAX_EV: u16 = 512;
const CON_BUF_SIZE: u16 = 1024;
const MAX_CON: u16 = 512;

pub const Server = struct {
    listening_sock: fd,
    addr: std.Io.net.IpAddress,
    allocator: Allocator,
    con_table: []*Connection,

    /// initializes a listening server
    pub fn init(allocator: Allocator, addr: std.Io.net.IpAddress, opt: so.SocketOptions) !Server {
        const socket = try so.get_socket(opt);

        const ip_adrr: u32 = std.mem.readInt(u32, &addr.ip4.bytes, .little);
        const sockaddr: sys.sockaddr.in = .{ .addr = ip_adrr, .port = std.mem.nativeToBig(u16, addr.ip4.port) };
        var rc = sys.bind(socket, @ptrCast(&sockaddr), @sizeOf(sys.sockaddr.in));

        try check("bind", rc);

        rc = sys.listen(socket, 1024);
        try check("listen", rc);

        return .{
            .listening_sock = socket,
            .addr = addr,
            .allocator = allocator,
            .con_table = undefined,
        };
    }

    /// runs the main server loop
    pub fn run(self: *Server) !void {
        defer utils.close_fd(self.listening_sock);

        // creat epoll() fd
        var rc = sys.epoll_create1(0);
        try utils.check_syscall("epoll_creat1()", rc);
        const epoll_fd: fd = @intCast(rc);
        defer utils.close_fd(epoll_fd);

        // set up event we are interested in
        var event: epoll_event = undefined;
        event.events = sys.EPOLL.IN;
        event.data.fd = self.listening_sock;

        // add listen socket to list
        rc = sys.epoll_ctl(epoll_fd, sys.EPOLL.CTL_ADD, self.listening_sock, &event);
        try utils.check_syscall("epoll_creat1()", rc);

        const ev_list = try self.allocator.alloc(epoll_event, MAX_EV);
        defer self.allocator.free(ev_list);
        std.debug.assert(ev_list.len == 0);

        info("listening on {}", .{self.addr});

        // number of open fds
        var n_fds: u16 = 0;

        while (true) {
            // TODO: listen for signal for graceful shutdown

            // TODO: check for EINTR rc

            // -1 for the timeout arguments causes epoll_wait() to block until an event occurs
            const n_ready = sys.epoll_wait(epoll_fd, ev_list.ptr, @intCast(MAX_EV), -1);
            try utils.check_syscall("epoll_wait()", n_ready);

            debug("new event! n_ready = {}", .{n_ready});

            for (0..n_ready) |idx| {
                const ev = ev_list[idx];
                const con = self.con_table[@intCast(ev.data.fd)];

                if (ev.events & (sys.EPOLL.HUP | sys.EPOLL.ERR) > 0) {
                    const err_fd = ev.data.fd;

                    if (err_fd == self.listening_sock) {
                        l_err("listening socket error!", .{});
                        break;
                    }

                    warn("fd error, or hang up {}", .{err_fd});
                    n_fds -= 1;

                    con.deinit();
                    self.allocator.destroy(con);
                }

                if (ev.data.fd == self.listening_sock) {
                    debug("new client!", .{});

                    accept_client(self.allocator, &n_fds, self.listening_sock, epoll_fd, self.con_table) catch |err| {
                        warn("accept client error {}", .{err});
                        continue;
                    };
                }

                if (ev.events & sys.EPOLL.IN > 0) {
                    // fd has data for us to read
                }

                if (ev.events & sys.EPOLL.OUT > 0) {
                    // fd has data for us to write
                }
            }
        }
    }
};

fn accept_client(allocator: Allocator, n_fds: *u16, li_fd: fd, epoll_fd: fd, con_table: []*Connection) !void {
    if (n_fds.* >= MAX_EV) {
        warn("maximum connections reached, rejecting client", .{});
        return error.MaxConnections;
    }

    var client_addr: sys.sockaddr.in = undefined;
    var addrlen: sys.socklen_t = @sizeOf(sys.sockaddr.in);
    var rc = sys.accept(li_fd, @ptrCast(&client_addr), &addrlen);

    try check("accept", rc);

    const con_fd: fd = @intCast(rc);
    errdefer utils.close_fd(con_fd);

    try so.set_fd_nonblock(con_fd);

    var event: epoll_event = undefined;
    event.data.fd = con_fd;
    event.events = sys.EPOLL.IN;

    const alloc = try allocator.create(Connection);
    errdefer allocator.destroy(alloc);

    alloc.* = try Connection.init(allocator, con_fd, &client_addr);
    errdefer alloc.deinit();

    rc = sys.epoll_ctl(epoll_fd, sys.EPOLL.CTL_ADD, con_fd, &event);
    try utils.check_syscall("epoll_creat1()", rc);

    utils.print_sockaddr("new connection from ", &client_addr);

    con_table[@intCast(alloc.fd)] = alloc;
    n_fds.* += 1;
    return;
}

const Connection = struct {
    state: ConState,
    fd: fd,
    addr: sys.sockaddr.in,
    al: Allocator,

    snd_buf: []u8,
    rcv_buf: []u8,

    const ConState = enum {
        wants_read,
        wants_write,
    };

    pub fn init(allocator: Allocator, client_fd: fd, addr: *sys.sockaddr.in) !Connection {
        return .{
            .state = .wants_read,
            .fd = client_fd,
            .addr = addr.*,
            .al = allocator,
            .snd_buf = try allocator.alloc(u8, CON_BUF_SIZE),
            .rcv_buf = try allocator.alloc(u8, CON_BUF_SIZE),
        };
    }

    pub fn deinit(self: *Connection) void {
        self.al.free(self.snd_buf);
        self.al.free(self.rcv_buf);
        utils.close_fd(self.fd);
        return;
    }

    pub fn handle_read(_: *Connection) void {}
    pub fn handle_write(_: *Connection) void {}
};
