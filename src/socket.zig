const std = @import("std");
const linux = std.os.linux;
const fd = linux.fd_t;

const socket_error = error {
    CouldntCreateSocket
};

pub fn get_socket() !std.os.linux.fd_t {
    const res = linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0);

    if (linux.errno(res) != .SUCCESS) {
        return error.socket_error;
    }
    const socket: std.os.linux.fd_t = @intCast(res);

    return ;
}

