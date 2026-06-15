const std = @import("std");
const blitz = @import("blitz");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const arg_slice = try init.minimal.args.toSlice(arena);

    if (arg_slice.len == 1) {
        return error.NoAddressProvided;
    }
    const addr = try std.Io.net.IpAddress.parseLiteral(arg_slice[1]);

    var encoded_msg = blitz.Message.init(arena);
    defer encoded_msg.deinit();
    try encoded_msg.encode_string("hello from the client");
    encoded_msg.print();

    const con = try addr.connect(io, .{ .mode = .stream });
    defer con.close(io);

    std.log.info("connected to {}\n", .{addr});

    var writer = con.writer(io, &.{});
    try encoded_msg.write(&writer.interface);
}
