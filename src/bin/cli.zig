const std = @import("std");
const blitz = @import("blitz");

const DataUnit = blitz.DataUnit;
const Message = blitz.Message;
const eql = std.mem.eql;

const MAX_MSG_LEN = blitz.MAX_MSG_LEN;
const HDR_SIZE = blitz.HDR_SIZE;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const arg_slice = try init.minimal.args.toSlice(arena);

    const cli: CLI = try .parse_args(io, gpa, arg_slice[1..arg_slice.len]);
    try cli.run();
}

const CLI = struct {
    mode: ?Mode = null,
    addr: ?std.Io.net.IpAddress = null,

    srv_cmds: ?SrvCmd = null,
    srv_opts: ?SrvOpts = null,

    client_cmd: ?blitz.CMD = null,
    key: ?DataUnit = null,
    value: ?DataUnit = null,

    stderr: *std.Io.Writer,
    io: std.Io,
    al: std.mem.Allocator,

    const Mode = enum {
        Server,
        Client,
    };

    const SrvOpts = enum {
        Background,
    };

    const SrvCmd = enum {
        Stop,
    };

    fn parse_args(io: std.Io, al: std.mem.Allocator, args: []const []const u8) !CLI {
        const stderr = try std.Io.lockStderr(io, &.{}, null);
        const stderr_writer = &stderr.file_writer.interface;
        defer std.Io.unlockStderr(io);

        var cli: CLI = .{
            .stderr = stderr_writer,
            .io = io,
            .al = al,
        };

        if (args.len == 1) {
            cli.print_help() catch {
                std.log.err("print help error", .{});
            };
            return std.process.exit(0);
        }

        if (args.len < 2) {
            try cli.stderr.writeAll("invalid input: not enough arguments\n");
            return error.NotEnoughArgs;
        }

        if (eql(u8, args[0], "-s") or eql(u8, args[0], "--server")) {
            cli.mode = .Server;
        } else if (eql(u8, args[0], "-c") or eql(u8, args[0], "--client")) {
            cli.mode = .Client;
        }

        if (cli.mode == null) {
            try cli.stderr.writeAll("invalid input: no mode provided\nrun -h to see example usage\n");
            return error.NoModeProvided;
        }

        if (cli.mode.? == Mode.Server) {
            try cli.parse_server(args[1..args.len]);
        } else {
            try cli.parse_client(args[1..args.len]);
        }
        return cli;
    }

    fn parse_server(cli: *CLI, args: []const []const u8) !void {
        if (eql(u8, args[0], "stop")) {
            cli.srv_cmds = .Stop;
            if (args.len > 1) {
                try cli.stderr.writeAll("invalid input: too many arguments\n");
                return error.TooManyArgs;
            } else {
                return;
            }
        }

        cli.addr = std.Io.net.IpAddress.parseLiteral(args[0]) catch |err| {
            try cli.stderr.print("invalid ip address {s} {}\n", .{ args[0], err });
            return error.InvalidIpAddr;
        };

        if (args.len == 1) {
            return;
        }

        // options
        if (eql(u8, args[1], "-bg")) {
            cli.srv_opts = .Background;
        } else {
            try cli.stderr.writeAll("invalid input: invalid argumen\n");
            return error.InvalidArgument;
        }

        if (args.len > 3) {
            try cli.stderr.writeAll("invalid input: too many arguments\n");
            return error.TooManyArgs;
        }

        return;
    }

    fn parse_client(cli: *CLI, args: []const []const u8) !void {
        if (args.len < 3) {
            try cli.stderr.writeAll("invalid input: not enough arguments, for client mode provide an address, command and key/value\n");
            return error.NotEnoughArgs;
        }

        cli.addr = std.Io.net.IpAddress.parseLiteral(args[0]) catch |err| {
            try cli.stderr.print("invalid ip address {s} {}\n", .{ args[0], err });
            return error.InvalidIpAddr;
        };

        if (eql(u8, args[1], "get")) {
            cli.client_cmd = .Get;
        } else if (eql(u8, args[1], "set")) {
            cli.client_cmd = .Set;
        } else if (eql(u8, args[1], "del")) {
            cli.client_cmd = .Del;
        }

        if (cli.client_cmd == null) {
            try cli.stderr.writeAll("invalid input: no valid command provided, see help for available commands\n");
            return error.InvalidClientCMD;
        }

        cli.key = parse_datatype(args[2]) catch {
            try cli.stderr.print("invalid input: invalid data provided {s}\n", .{args[2]});
            return error.InvalidInput;
        };

        if (cli.client_cmd == .Set) {
            if (args.len < 4) {
                try cli.stderr.writeAll("invalid input: value missing for set command\n");
                return error.NotEnoughArgs;
            }

            cli.value = parse_datatype(args[3]) catch {
                try cli.stderr.writeAll("invalid input: invalid data provided\n");
                return error.InvalidInput;
            };
        }

        return;
    }

    fn parse_datatype(arg: []const u8) !DataUnit {
        if (arg.len == 0) {
            return error.EmptyDataString;
        }

        if (eql(u8, arg, "true")) {
            return .{
                .Boolean = true,
            };
        } else if (eql(u8, arg, "false")) {
            return .{
                .Boolean = false,
            };
        }

        if (std.mem.containsAtLeastScalar2(u8, arg, '.', 1)) {
            if (std.fmt.parseFloat(f64, arg)) |v| {
                return .{ .Float = v };
            } else |_| {}
        }

        if (std.fmt.parseInt(i64, arg, 10)) |v| {
            return .{ .Integer = v };
        } else |_| {}

        return .{ .String = .{
            .data = arg.ptr,
            .s_len = @intCast(arg.len),
        } };
    }

    fn print_help(cli: CLI) !void {
        const stdout = std.Io.File.stdout();
        const buf = try cli.al.alloc(u8, 200);
        defer cli.al.free(buf);

        var so_r = stdout.writer(cli.io, buf);
        var writer = &so_r.interface;

        try writer.writeAll("Blitz - fast and convenient key value store\n\n");
        try writer.writeAll("Usage: \n\n");
        try writer.writeAll("server mode:\nstart a blitz server listening on [IpAddress]: -s [IpAddress]\n");
        try writer.writeAll("to run the server in the background, pass: -bg\n");
        try writer.writeAll("to stop a server running in the background run: blitz stop\n\n");
        try writer.writeAll("client mode:\nto test a server as a client run: -c [IpAddr] [CMD] [Key] [Value]\n");

        try so_r.flush();
        return;
    }

    fn run(self: CLI) !void {
        switch (self.mode.?) {
            .Client => try self.run_client(),
            .Server => try self.run_server(),
        }
    }

    fn run_client(self: CLI) !void {
        var con = try self.addr.?.connect(self.io, .{ .mode = .stream });
        defer con.close(self.io);

        var w_int = con.writer(self.io, &.{});
        var sock_writer = &w_int.interface;

        // form and write request to socket
        const buf = try self.al.alloc(u8, MAX_MSG_LEN);
        defer self.al.free(buf);
        const req = try Message.new_request(buf, self.client_cmd.?, self.key.?, self.value);

        try sock_writer.writeAll(req.as_slice());
        try sock_writer.flush();

        // read header from socket
        const read_buf = try self.al.alloc(u8, MAX_MSG_LEN);
        defer self.al.free(read_buf);
        var r_int = con.reader(self.io, &.{});
        var socket_reader = &r_int.interface;

        try socket_reader.readSliceAll(read_buf[0..HDR_SIZE]);
        const hdr = try Message.parse_header(read_buf[0..HDR_SIZE]);
        try socket_reader.readSliceAll(read_buf[HDR_SIZE .. HDR_SIZE + hdr.pay_len]);

        // parse response
        const resp = try Message.parse(read_buf);

        // write response to stdout
        const stdout = std.Io.File.stdout();
        const stdout_buf = try self.al.alloc(u8, MAX_MSG_LEN);
        defer self.al.free(stdout_buf);

        var so_r = stdout.writer(self.io, buf);
        const stdout_writer = &so_r.interface;

        try resp.write(stdout_writer);
        return;
    }

    fn run_server(cli: *const CLI) !void {
        var srv = try blitz.Server.init(cli.al, cli.addr.?);
        // TODO: run in the background logic
        try srv.run();
        return;
    }
};

test "cli parsing" {
    std.testing.log_level = .debug;
    const io = std.testing.io;
    const al = std.testing.allocator;

    const server_args = [_][]const u8{ "-s", "127.0.0.1:3000" };
    const s = try CLI.parse_args(io, al, &server_args);
    try std.testing.expect(s.mode == .Server);
    try std.testing.expect(s.addr != null);

    const client_args = [_][]const u8{ "-c", "127.0.0.1:3000", "get", "\"hello\"" };
    const c = try CLI.parse_args(io, al, &client_args);
    try std.testing.expect(c.mode == .Client);
    try std.testing.expect(c.addr != null);
    try std.testing.expect(c.client_cmd == .Get);

    const bad_args = [_][]const u8{ "-c", "127.0.0.1:3000", "get" };
    const e = CLI.parse_args(io, al, &bad_args);
    try std.testing.expectError(error.NotEnoughArgs, e);
}
