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
