const std = @import("std");
const utils = @import("utils.zig");
const handler = @import("handler.zig");
const so = @import("socket.zig");
const message = @import("message.zig");

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
const Message = message.Message;

pub const MAX_EV: u16 = 1024;
pub const MAX_CON: u16 = 1024;
pub const CON_BUF_SIZE: u16 = 2048;

pub const Server = struct {
    addr: std.Io.net.IpAddress,
    allocator: Allocator,

    /// initializes a listening server
    pub fn init(allocator: Allocator, addr: std.Io.net.IpAddress) !Server {
        return .{
            .addr = addr,
            .allocator = allocator,
        };
    }

    /// runs the main server loop
    pub fn run(self: *Server) !void {
        const li_sock = try so.get_li_socket(self.addr, .{});
        defer utils.close_fd(li_sock);

        const epoll_fd: fd = try so.setup_epoll(li_sock);
        defer utils.close_fd(epoll_fd);

        const ev_list = try self.allocator.alloc(epoll_event, MAX_EV);
        defer self.allocator.free(ev_list);

        var con_table: []*Connection = try self.allocator.alloc(*Connection, MAX_CON);
        defer self.allocator.free(con_table);

        info("listening on {}", .{self.addr});

        // number of open fds
        var n_fds: u16 = 0;

        while (true) {
            // TODO: listen for signal for graceful shutdown

            // -1 for the timeout arguments causes epoll_wait() to block until an event occurs
            const n_ready = sys.epoll_wait(epoll_fd, ev_list.ptr, @intCast(MAX_EV), -1);

            switch (sys.errno(n_ready)) {
                .SUCCESS => {
                    debug("new event! n_ready = {}", .{n_ready});
                },
                .INTR => {
                    // TODO: handle interrupt
                    debug("interruped received", .{});
                    continue;
                },
                else => |err| {
                    l_err("epoll wait error {}", .{err});
                    break;
                },
            }

            for (0..n_ready) |idx| {
                const ev = ev_list[idx];
                const con = con_table[@intCast(ev.data.fd)];

                if (ev.data.fd == li_sock) {
                    const new_con = handler.accept_client(self.allocator, n_fds, li_sock, epoll_fd) catch |err| {
                        l_err("accept client error {}", .{err});
                        continue;
                    };
                    con_table[@intCast(new_con.fd)] = new_con;
                    n_fds += 1;
                    continue;
                }

                if (ev.events & (sys.EPOLL.HUP | sys.EPOLL.ERR) > 0) {
                    if (ev.data.fd == li_sock) {
                        l_err("listening socket error!", .{});
                        break;
                    }

                    warn("fd error, or hang up {}", .{ev.data.fd});

                    con.state = .wants_close;
                }

                if (ev.events & sys.EPOLL.IN > 0) {
                    // fd has data for us to read
                    debug("pollin event, fd={}", .{ev.data.fd});
                    handler.handle_read(con);
                }

                if (ev.events & sys.EPOLL.OUT > 0) {
                    // fd has data for us to write
                    debug("pollout event, fd={}", .{ev.data.fd});
                    handler.handle_write(con);
                }

                // change the fd interest based on connection state
                switch (con.state) {
                    .wants_write => {
                        if (ev.events & sys.EPOLL.OUT == 0) {
                            try utils.epoll_mod(sys.EPOLL.OUT, con.fd, epoll_fd);
                        }
                    },
                    .wants_read => {
                        if (ev.events & sys.EPOLL.IN == 0) {
                            try utils.epoll_mod(sys.EPOLL.IN, con.fd, epoll_fd);
                        }
                    },
                    .wants_close => {
                        n_fds -= 1;
                        utils.print_sockaddr("closing connection: ", &con.addr);
                        con.deinit();
                    },
                }
            }
        }
    }
};

pub const Connection = struct {
    state: ConState,
    fd: fd,
    addr: sys.sockaddr.in,
    al: std.heap.ArenaAllocator,

    snd_buf: utils.Buf,
    rcv_buf: utils.Buf,

    const ConState = enum {
        wants_read,
        wants_write,
        wants_close,
    };

    pub fn init(allocator: Allocator, client_fd: fd, addr: *sys.sockaddr.in) !*Connection {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const a = arena.allocator();
        const con = try a.create(Connection);
        con.* = .{
            .state = .wants_read,
            .fd = client_fd,
            .addr = addr.*,
            .al = arena,
            .snd_buf = try utils.Buf.init(a, CON_BUF_SIZE),
            .rcv_buf = try utils.Buf.init(a, CON_BUF_SIZE),
        };
        return con;
    }

    pub fn deinit(self: *Connection) void {
        utils.close_fd(self.fd);
        self.al.deinit();
        return;
    }
};

test "alloc slice" {
    const allocator = std.testing.allocator;
    const allocation = try allocator.alloc(u8, 10);
    defer allocator.free(allocation);
    try std.testing.expect(allocation.len == 10);

    const arr: [10]u8 = undefined;
    try std.testing.expect(arr.len == 10);
}
