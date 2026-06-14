const std = @import("std");
const linux = std.os.linux;

pub fn close_fd(fd: linux.fd_t) void {
    const rc = linux.close(fd);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("close error: {}", .{err});
        },
    }
}

pub fn print_sockaddr(msg: []const u8, sockaddr: *linux.sockaddr.in) void {
    const ip_bytes = std.mem.asBytes(&sockaddr.addr);
    const port = std.mem.bigToNative(u16, sockaddr.port);

    std.log.info("{s}{}.{}.{}.{}:{}", .{ msg, ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3], port });

    return;
}

/// reads bytes into the slice
pub fn read_socket(socket: linux.fd_t, buf: []u8) !void {
    var idx: usize = 0;
    var read_bytes: usize = 0;

    while (idx < buf.len) {
        const rc = linux.read(socket, buf.ptr + idx, buf.len - idx);
        switch (linux.errno(rc)) {
            .SUCCESS => read_bytes = rc,
            else => |err| {
                std.log.err("read error {}", .{err});
                return error.ReadError;
            },
        }
        if (read_bytes == 0) return;
        idx += read_bytes;
    }
}

/// attempts to write the entire slice
pub fn write_socket(socket: linux.fd_t, buf: []const u8) !void {
    var idx: usize = 0;
    var written_bytes: usize = 0;

    while (idx < buf.len) {
        const rc = linux.write(socket, buf.ptr + idx, buf.len - idx);
        switch (linux.errno(rc)) {
            .SUCCESS => written_bytes = rc,
            else => |err| {
                std.log.err("write error {}", .{err});
                return error.WriteError;
            },
        }
        if (written_bytes == 0) return;
        idx += written_bytes;
    }
}

pub fn check_syscall(context: []const u8, rc: usize) !void {
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("{s} error {}", .{ context, err });
            return error.SysCallError;
        },
    }
}
