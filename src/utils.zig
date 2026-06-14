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
