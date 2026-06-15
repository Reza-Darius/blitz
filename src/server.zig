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

const MAX_EV: u16 = 512;

pub const Server = struct {
    listening_sock: fd,
    addr: std.Io.net.IpAddress,
    allocator: std.mem.Allocator,

    /// initializes a listening server
    pub fn init(allocator: std.mem.Allocator, addr: std.Io.net.IpAddress, opt: so.SocketOptions) !Server {
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

        while (true) {
            // TODO: listen for signal for graceful shutdown

            // TODO: check for EINTR rc

            // -1 for the timeout arguments causes epoll_wait() to block until an event occurs
            const n_ready = sys.epoll_wait(epoll_fd, ev_list.ptr, @intCast(MAX_EV), -1);
            try utils.check_syscall("epoll_wait()", n_ready);

            debug("new event! n_ready = {}", .{n_ready});

            for (0..n_ready) |idx| {
                if (ev_list[idx].data.fd == self.listening_sock) {
                    // new client
                    debug("new client!", .{});
                }

                if (ev_list[idx].events & (sys.EPOLL.HUP | sys.EPOLL.ERR) > 0) {
                    const err_fd = ev_list[idx].data.fd;
                    warn("fd error {}", .{err_fd});
                    utils.close_fd(err_fd);
                }

                if (ev_list[idx].events & sys.EPOLL.IN > 0) {
                    // fd has data for us to read
                }

                if (ev_list[idx].events & sys.EPOLL.OUT > 0) {
                    // fd has data for us to write
                }
            }
        }
    }
};

fn accept_client(n_fds: usize, li_fd: fd, epoll_fd: fd) !void {
    var client_addr: sys.sockaddr.in = undefined;
    var addrlen: sys.socklen_t = @sizeOf(sys.sockaddr.in);
    const rc = sys.accept(li_fd, @ptrCast(&client_addr), &addrlen);

    // we might want to react to different errors here
    try check("accept", rc);

    const con_fd: fd = @intCast(rc);

    if (n_fds >= MAX_EV) {
        warn("maximum connections reached, rejecting client, fd={}", .{con_fd});
        utils.close_fd(con_fd);
        return;
    }

    utils.print_sockaddr("new connection from ", &client_addr);

    try so.set_fd_nonblock(con_fd);

    var event: epoll_event = undefined;
    event.data.fd = con_fd;

    rc = sys.epoll_ctl(epoll_fd, sys.EPOLL.CTL_ADD, con_fd, &event);
    try utils.check_syscall("epoll_creat1()", rc);

    return;
}

