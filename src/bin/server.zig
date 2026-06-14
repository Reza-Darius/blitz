const std = @import("std");
const blitz = @import("blitz");

pub fn main(init: std.process.Init) !void {
    // const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const arg_slice = try init.minimal.args.toSlice(arena);
    var addr: std.Io.net.IpAddress = undefined;

    if (arg_slice.len == 1) {
        return error.NoAddressProvided;
    }

    for (1..arg_slice.len) |idx| {
        const arg = arg_slice[idx];
        std.log.info("arg: {s}", .{arg});
        addr = try .parseLiteral(arg);
    }
    var server = try blitz.Server.init(gpa, addr, .{ .socket_type = .TCP, .reuse_addr = true, .nonblock = false });
    try server.run();
}
