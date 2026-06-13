const std = @import("std");
const blitz = @import("blitz");
const sock = @import("socket.zig");
const linux = std.os.linux;

const print = std.debug.print;

pub fn main(init: std.process.Init) !void {
    // const io = init.io;
    const gpa = init.gpa;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const arg_slice = try init.minimal.args.toSlice(arena.allocator());
    var addr: std.Io.net.IpAddress = undefined;

    if (arg_slice.len == 1) {
        return error.NoAddressProvided;
    }

    for (1..arg_slice.len) |idx| { 
        const arg = arg_slice[idx];
        std.log.info("arg: {s}", .{arg});
        addr = try .parseLiteral(arg);
    }

    const socket = try sock.get_socket(&addr);

    std.log.info("listening on {}", .{addr});
    _ = std.os.linux.accept(socket, null, null);
}


