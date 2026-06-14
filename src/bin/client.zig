const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

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

    const con = try addr.connect(io, .{.mode = .stream});
    defer con.close(io);

    std.log.info("connected to {}\n", .{addr});

    var writer = con.writer(io, &.{});
    try writer.interface.writeAll("hello from the client!");
}
