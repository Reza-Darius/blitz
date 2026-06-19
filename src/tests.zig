const std = @import("std");
const Message = @import("root.zig").Message;

test "echo request" {
    std.testing.log_level = .err;
    const al = std.testing.allocator;
    const io = std.testing.io;

    const n_msgs = 10;

    const addr = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:4000");
    const write_buf = try al.alloc(u8, 200);
    defer al.free(write_buf);

    std.debug.assert(write_buf.len > 11);
    var encoded_msg = try Message.echo_req(write_buf, "hello from the client");

    const con = try addr.connect(io, .{ .mode = .stream });
    defer con.close(io);

    std.log.info("connected to {}\n", .{addr});

    var writer = con.writer(io, &.{});

    for (0..n_msgs) |_| {
        try writer.interface.writeAll(encoded_msg.as_slice());
    }

    var reader = con.reader(io, &.{});

    for (0..n_msgs) |_| {
        const res = try reader.interface.readAlloc(al, encoded_msg.len());
        defer al.free(res);

        const resp_msg = try Message.parse(res);
        resp_msg.print_info("got in response: ");
    }
}
