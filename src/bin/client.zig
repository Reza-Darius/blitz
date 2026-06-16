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
    const write_buf = try arena.alloc(u8, 100);

    var encoded_msg = try blitz.Message.encode_msg(write_buf, "hello from the client");
    encoded_msg.print();

    const con = try addr.connect(io, .{ .mode = .stream });
    defer con.close(io);

    std.log.info("connected to {}\n", .{addr});

    var writer = con.writer(io, &.{});
    try encoded_msg.write(&writer.interface);

    const read_buf = try arena.alloc(u8, 100);
    var reader = con.reader(io, read_buf);

    const res = try reader.interface.readAlloc(arena, encoded_msg.len());
    const resp_msg = try blitz.Message.try_parse(res);
    resp_msg.print_info("got in response: ");
}
