const std = @import("std");
const blitz = @import("blitz");

const print = std.debug.print;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const aa = arena.allocator();
    _ = try vec_action(aa, "men will manage their memory!");

    var buf = try gpa.alloc(u8, 100);
    gpa.free(buf);

    const std_out = std.Io.File.stdout();
    defer std_out.close(io);

    var iter = init.minimal.args.iterate();
    while (iter.next()) |arg| { 
        std.log.info("arg: {s}", .{arg});
    }

    var writer = std_out.writer(io, buf[0..buf.len]);
    try writer.interface.writeAll("hello world\n");
    print("byte 1: {}, byte 2: {}\n", .{ buf[0], buf[1] });

    writer.flush() catch |err| {
        print("{}\n", .{err});
        return err;
    };

    const num = blitz.rex(5, 10);
    print("{}\n", .{num});
}

fn vec_action(allocator: std.mem.Allocator, str: [:0]const u8) !u8 {
    var list: std.ArrayList(u8) = try .initCapacity(allocator, 100);
    defer list.deinit(allocator);

    try list.append(allocator, str[0]);
    print("{}\n", .{list.items[0]});

    return list.items[0];
}
