const std = @import("std");
const Message = @import("root.zig").Message;
const DataUnit = @import("datatypes.zig").DataUnit;

const SRV_ADDR = "127.0.0.1:4000";

test "echo request" {
    std.testing.log_level = .err;
    const al = std.testing.allocator;
    const io = std.testing.io;

    const n_msgs = 10;

    const addr = try std.Io.net.IpAddress.parseLiteral(SRV_ADDR);
    const write_buf = try al.alloc(u8, 200);
    defer al.free(write_buf);

    std.debug.assert(write_buf.len > 11);
    var encoded_msg = try Message.echo_req(write_buf, "hello from the client");

    const con = try addr.connect(io, .{ .mode = .stream });
    defer con.close(io);
    var writer = con.writer(io, &.{});

    for (0..n_msgs) |_| {
        try writer.interface.writeAll(encoded_msg.as_slice());
    }

    var reader = con.reader(io, &.{});

    for (0..n_msgs) |_| {
        const res = try reader.interface.readAlloc(al, encoded_msg.len());
        defer al.free(res);

        const resp_msg = try Message.parse(res);
        try std.testing.expect(std.mem.eql(u8, resp_msg.payload(), encoded_msg.payload()));
    }
}

test "set, get, del" {
    std.testing.log_level = .err;
    const al = std.testing.allocator;
    const io = std.testing.io;

    const addr = try std.Io.net.IpAddress.parseLiteral(SRV_ADDR);

    const write_buf = try al.alloc(u8, 200);
    defer al.free(write_buf);

    const con = try addr.connect(io, .{ .mode = .stream });
    defer con.close(io);
    var writer = con.writer(io, &.{});
    var reader = con.reader(io, &.{});

    const set_req = try Message.new_request(write_buf, .Set, .string_to_unit("Key"), .string_to_unit("Value"));
    try writer.interface.writeAll(set_req.as_slice());

    const set_res = try reader.interface.readAlloc(al, 3);
    defer al.free(set_res);

    const set_resp = try Message.parse(set_res);
    const set_hdr = set_resp.header();

    try std.testing.expect(set_hdr.ctrl.msg_type == .Response);
    try std.testing.expect(set_hdr.is_ok());


    const get_req = try Message.new_request(write_buf, .Get, .string_to_unit("Key"), null);
    try writer.interface.writeAll(get_req.as_slice());

    const get_res = try reader.interface.readAlloc(al, 11);
    defer al.free(get_res);

    const get_resp = try Message.parse(get_res);
    const get_hdr = get_resp.header();
    const get_pay = get_resp.payload();
    const du = try DataUnit.decode(get_pay);

    try std.testing.expect(get_hdr.ctrl.msg_type == .Response);
    try std.testing.expect(get_hdr.is_ok());
    try std.testing.expect(du == DataUnit.String);
    try std.testing.expect(du.len() == 3 + 5);
    try std.testing.expect(std.mem.eql(u8, get_pay[3..get_pay.len], "Value"));

    const del_req = try Message.new_request(write_buf, .Del, .string_to_unit("Key"), null);
    try writer.interface.writeAll(del_req.as_slice());

    const del_res = try reader.interface.readAlloc(al, 3);
    defer al.free(del_res);

    const del_resp = try Message.parse(del_res);
    const del_hdr = del_resp.header();

    try std.testing.expect(del_hdr.ctrl.msg_type == .Response);
    try std.testing.expect(del_hdr.is_ok());
}
