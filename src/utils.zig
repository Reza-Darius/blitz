const std = @import("std");
const sys = std.os.linux;

pub fn close_fd(fd: sys.fd_t) void {
    const rc = sys.close(fd);
    switch (sys.errno(rc)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("close error: {}", .{err});
        },
    }
}

pub fn print_sockaddr(msg: []const u8, sockaddr: *sys.sockaddr.in) void {
    const ip_bytes = std.mem.asBytes(&sockaddr.addr);
    const port = std.mem.bigToNative(u16, sockaddr.port);

    std.log.info("{s}{}.{}.{}.{}:{}", .{ msg, ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3], port });

    return;
}

/// reads bytes into the slice
pub fn read_socket(socket: sys.fd_t, buf: []u8) !void {
    var idx: usize = 0;
    var read_bytes: usize = 0;

    while (idx < buf.len) {
        const rc = sys.read(socket, buf.ptr + idx, buf.len - idx);
        switch (sys.errno(rc)) {
            .SUCCESS => read_bytes = rc,
            .AGAIN => continue,
            else => |err| {
                std.log.err("read error {}", .{err});
                return error.ReadError;
            },
        }

        // EOF or disconnected
        if (read_bytes == 0) return;

        idx += read_bytes;
    }
}

/// attempts to write the entire slice
pub fn write_socket(socket: sys.fd_t, buf: []const u8) !void {
    var idx: usize = 0;
    var written_bytes: usize = 0;

    while (idx < buf.len) {
        const rc = sys.write(socket, buf.ptr + idx, buf.len - idx);
        switch (sys.errno(rc)) {
            .SUCCESS => written_bytes = rc,
            .AGAIN => continue,
            else => |err| {
                std.log.err("write error {}", .{err});
                return error.WriteError;
            },
        }

        // EOF or disconnected
        if (written_bytes == 0) return;

        idx += written_bytes;
    }
}

/// checks the return code
pub fn check_syscall(context: []const u8, rc: usize) !void {
    switch (sys.errno(rc)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("{s} error {}", .{ context, err });
            return error.SysCallError;
        },
    }
}

pub const Buf = struct {
    data: []u8,
    lo: u16,
    len: u16,
    al: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Buf {
        const data = try allocator.alloc(u8, capacity);
        return .{
            .data = data,
            .lo = 0,
            .len = 0,
            .al = allocator,
        };
    }

    /// doesnt grow the buffer and errors if the cap would be exceeded
    pub fn append(self: *Buf, data: []u8) !void {
        const i = self.len + self.lo;
        if (data.len + i > self.data.len) {
            return error.CapOverflow;
        }
        @memcpy(self.data[i .. i + data.len], data);
        self.len += @intCast(data.len);
        return;
    }

    /// gets a to the written unread data
    pub fn as_slice(self: Buf) ?[]u8 {
        if (self.len == 0) {
            return null;
        }
        return self.data[self.lo..self.lo + self.len];
    }

    pub fn clear(self: *Buf) void {
        self.len = 0;
        self.lo = 0;
        return;
    }

    pub fn is_full(self: *Buf) bool {
        return self.len >= self.data.len;
    }

    pub fn is_empty(self: *Buf) bool {
        return self.len == self.lo;
    }

    /// consuming read
    pub fn read_n(self: *Buf, n: u16) void {
        if (n > self.len or self.is_empty()) {
            @panic("out of bounds read_n()");
        }
        self.lo += n;
        self.len -= n;
        std.debug.assert(self.lo <= self.len);
        return;
    }

    pub fn consume_n(self: *Buf, n: u16) ?[]u8 {
        if (n > self.len or self.is_empty()) {
            return null;
        }
        const s = self.data[self.lo .. self.lo + n];
        self.lo += n;
        self.len -= n;
        std.debug.assert(self.lo <= self.len);
        return s;
    }

    pub fn deinit(self: Buf) void {
        self.al.free(self.data);
        return;
    }

    pub fn cap(self: Buf) u16 {
        return self.data.len;
    }
};

pub fn epoll_mod(flag: u32, fd: sys.fd_t, epoll_fd: sys.fd_t) !void {
    var event: sys.epoll_event = undefined;
    event.data.fd = fd;
    event.events = flag;
    const rc = sys.epoll_ctl(epoll_fd, sys.EPOLL.CTL_MOD, fd, &event);
    try check_syscall("epoll_ctrl() mod ", rc);
}
