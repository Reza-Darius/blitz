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

pub fn check_syscall(context: []const u8, rc: usize) !void {
    switch (sys.errno(rc)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("{s} error {}", .{ context, err });
            return error.SysCallError;
        },
    }
}
