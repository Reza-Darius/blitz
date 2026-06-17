const std = @import("std");
const utils = @import("utils.zig");

const info = std.log.info;
const debug = std.log.debug;
const l_err = std.log.err;
const warn = std.log.warn;

const MAP_SIZE = map_size(1024);

// asserts that capacity is power of 2 for faster modulo operation
fn map_size(n: comptime_int) comptime_int {
    comptime std.debug.assert((n & (n - 1)) == 0);
    return n;
}

pub const HashMap = struct {
    len: u32,
    data: []Bucket,
    al: std.mem.Allocator,

    const Hash = u64;
    const Entry = []const u8;
    const KEY = "super duper secret key";

    const Bucket = struct {
        /// probe sequence length
        psl: u8 = 0,
        /// 64 bit integer generaed by siphash
        hash: Hash = 0,
        entry: ?Entry = null,
    };

    pub fn init(allocator: std.mem.Allocator, cap: usize) !HashMap {
        const data = try allocator.alloc(Bucket, cap);
        @memset(data, .{ .psl = 0, .hash = 0, .entry = null });
        return .{
            .len = 0,
            .data = data,
            .al = allocator,
        };
    }

    pub fn deinit(self: *HashMap) void {
        // loop over entire map for deallocation?
        self.al.free(self.data);
        return;
    }

    fn print(self: HashMap) void {
        for (0..self.data.len) |i| {
            std.debug.print("No {}: {}\n", .{ i, self.data[i] });
        }
        return;
    }

    pub fn insert(self: *HashMap, key: []const u8, elem: Entry) void {
        // not sure if its worth it to return an error
        std.debug.assert(self.len < self.data.len);

        const c = self.data.len;
        var b: Bucket = .{
            .psl = 0,
            .hash = hash(key),
            .entry = elem,
        };
        debug("inserting {any}\n", .{b});
        var i: u32 = index(c, b.hash);

        while (self.data[i].entry != null) {
            debug("checking idx {} with psl {}\n", .{ i, b.psl });
            debug("colliding with bucket {any}, at {}\n", .{ self.data[i], i });

            // INV: For any i, the values that hash to bucket i precede the values
            // that hash to bucket i+1 (this naturally includes wraparound)
            if (b.psl > self.data[i].psl) {
                debug("swapping at {}\n", .{i});
                std.mem.swap(Bucket, &self.data[i], &b);
                debug("checking for {any} now", .{b});
            }

            i = index(c, i + 1);
            b.psl += 1;
        }

        self.data[i] = b;
        debug("found place at {}\n", .{i});
        self.len += 1;
        return;
    }

    pub fn get(self: HashMap, key: []const u8) ?Entry {
        const c = self.data.len;
        var psl: u8 = 0;
        const h = hash(key);
        var i: u32 = index(c, h);

        while (self.data[i].entry != null) {
            if (psl > self.data[i].psl) {
                return null;
            }
            if (self.data[i].hash == h) {
                return self.data[i].entry;
            }
            i = index(c, i + 1);
            psl += 1;
        }
        return null;
    }

    pub fn remove(self: *HashMap, key: []const u8) ?Entry {
        const c = self.data.len;

        const h = hash(key);
        var i = index(c, h);
        var psl: u8 = 0;

        var r: ?Entry = null;
        while (self.data[i].entry != null) {
            if (psl > self.data[i].psl) {
                // the key is not there
                break;
            }
            if (self.data[i].hash == h) {
                r = self.data[i].entry;
                break;
            }
            i = index(c, i + 1);
            psl += 1;
        }

        if (r == null) {
            debug("key not found", .{});
            return null;
        }

        debug("removing {any} at {}\n", .{ r, i });

        var j: u32 = index(c, i + 1);
        while (self.data[j].entry != null) {
            debug("checking neighbor at {any}\n", .{j});
            if (self.data[j].psl > 0) {
                self.data[j].psl -= 1;
                debug("swapping with neighbor {any} at {any}\n", .{ self.data[j], j });
                std.mem.swap(Bucket, &self.data[j], &self.data[j - 1]);
            } else {
                break;
            }
            j = index(c, j + 1);
        }
        debug("returning {any}\n", .{r});

        self.len -= 1;
        return r;
    }

    fn grow() void {}

    fn hash(elem: Entry) Hash {
        var hasher: std.hash.SipHash64(2, 4) = .init(KEY[0..16]);
        hasher.update(elem);
        return hasher.finalInt();
    }

    fn vpsl(c: usize, h: Hash, i: u32) u32 {
        return index(c, h + i);
    }

    fn load(self: HashMap) f32 {
        return self.len / self.data.len;
    }

    inline fn index(c: usize, h: Hash) u32 {
        // only power of two capacity values are permitted to enable faster modulo
        std.debug.assert((c & (c - 1)) == 0);
        return @intCast(h & (c - 1));
    }
};

test "hashmap insert/get" {
    std.testing.log_level = .debug;

    const alloc = std.testing.allocator;
    const c = 8;
    std.debug.assert((c & (c - 1)) == 0);

    var map = try HashMap.init(alloc, c);
    defer map.deinit();

    const data = [_]u16{ 2, 5, 7, 10, 42, 120 };

    for (0..data.len) |i| {
        const bytes = std.mem.asBytes(&data[i]);
        map.insert(bytes, bytes);
    }
    try std.testing.expect(map.len == data.len);

    map.print();

    for (0..data.len) |i| {
        const bytes = std.mem.asBytes(&data[i]);
        const res = map.get(bytes);
        const r = std.mem.readInt(u16, res.?[0..2], .little);

        try std.testing.expect(r == data[i]);
    }
}

test "hashmap delete" {
    std.testing.log_level = .debug;

    const alloc = std.testing.allocator;
    const c = 8;
    std.debug.assert((c & (c - 1)) == 0);

    var map = try HashMap.init(alloc, c);
    defer map.deinit();

    const data = [_]u16{ 2, 5, 7, 10, 42, 120 };

    for (0..data.len) |i| {
        const bytes = std.mem.asBytes(&data[i]);
        map.insert(bytes, bytes);
    }
    try std.testing.expect(map.len == data.len);

    map.print();

    for (0..data.len) |i| {
        std.log.debug("testing {}\n", .{data[i]});

        const bytes = std.mem.asBytes(&data[i]);
        const res = map.remove(bytes);
        const r = std.mem.readInt(u16, res.?[0..2], .little);

        try std.testing.expect(r == data[i]);
    }
    try std.testing.expect(map.len == 0);
}
