const std = @import("std");
const blitz = @import("blitz");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const arg_slice = try init.minimal.args.toSlice(arena);

    if (arg_slice.len == 1) {
        return error.NoAddressProvided;
    }
    const addr = try std.Io.net.IpAddress.parseLiteral(arg_slice[1]);

    var server = try blitz.Server.init(gpa, addr);
    try server.run();
}
