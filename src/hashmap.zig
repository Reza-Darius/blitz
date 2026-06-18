const std = @import("std");
const utils = @import("utils.zig");

const info = std.log.info;
const debug = std.log.debug;
const l_err = std.log.err;
const warn = std.log.warn;

const MAP_SIZE = map_size(1024);
const MAX_KEY_SIZE = 2024;
const MAX_VALUE_SIZE = 2024;

// asserts that capacity is power of 2 for faster modulo operation
fn map_size(n: comptime_int) comptime_int {
    comptime std.debug.assert((n & (n - 1)) == 0);
    return n;
}

/// a managed hash table
pub const HashMap = struct {
    len: u32,
    data: []Bucket,
    al: std.mem.Allocator,

    const Hash = u64;
    const HASH_KEY = "super duper secret key";
    const LOAD_THRESH = 0.9;

    const Bucket = struct {
        /// probe sequence length
        psl: u8 = 0,
        /// 64 bit integer
        hash: Hash = 0,
        entry: ?*Entry = null,
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
        for (0..self.data.len) |i| {
            const slot = self.data[i];

            if (slot.entry) |e| {
                e.destroy(self.al);
            }
        }
        self.al.free(self.data);
        return;
    }

    /// primarily for debug purposes
    fn print(self: HashMap) void {
        for (0..self.data.len) |i| {
            const slot = self.data[i];
            if (slot.entry) |e| {
                std.debug.print("No {}: psl={} key={s}, val={s}\n", .{ i, slot.psl, e.get_key(), e.get_val() });
            } else {
                std.debug.print("No {}: empty\n", .{i});
            }
        }
        return;
    }

    /// insert a new entry, supplied data is copied and allocated
    pub fn insert(self: *HashMap, key: []const u8, value: []const u8) !void {
        std.debug.assert(self.len < self.data.len);
        std.debug.assert(key.len != 0);
        std.debug.assert(value.len != 0);

        const e = try Entry.encode(self.al, key, value);
        self.insert_helper(e);
        self.len += 1;
        try self.check_grow();
        return;
    }

    fn insert_helper(self: *HashMap, e: *Entry) void {
        const c = self.data.len;
        var cur_bucket: Bucket = .{
            .psl = 0,
            .hash = hash(e.get_key()),
            .entry = e,
        };

        debug("inserting {any}\n", .{cur_bucket});

        var i: u32 = index(c, cur_bucket.hash);

        while (self.data[i].entry != null) {
            debug("checking idx {} with psl {}\n", .{ i, cur_bucket.psl });
            debug("colliding with bucket {any}, at {}\n", .{ self.data[i], i });

            // INV: For any i, the values that hash to bucket i precede the values
            // that hash to bucket i+1 (this naturally includes wraparound)
            if (cur_bucket.psl > self.data[i].psl) {
                debug("swapping at {}\n", .{i});

                std.mem.swap(Bucket, &self.data[i], &cur_bucket);

                debug("checking for {any} now", .{cur_bucket});
            }

            i = index(c, i + 1);
            cur_bucket.psl += 1;
        }

        debug("found place at {}\n", .{i});

        self.data[i] = cur_bucket;
        return;
    }

    /// retrieves an entry from the table, the caller is not responsible for deallocation
    pub fn get(self: HashMap, key: []const u8) ?*Entry {
        std.debug.assert(key.len != 0);

        const c = self.data.len;
        const cur_hash = hash(key);

        var psl: u8 = 0;
        var i: u32 = index(c, cur_hash);

        while (self.data[i].entry != null) {
            if (psl > self.data[i].psl) {
                return null;
            }
            if (self.data[i].hash == cur_hash) {
                return self.data[i].entry;
            }
            i = index(c, i + 1);
            psl += 1;
        }
        return null;
    }

    /// removes an entry from the hashmap if it exists, the caller is responsible for calling entry.destroy();
    pub fn remove(self: *HashMap, key: []const u8) ?*Entry {
        std.debug.assert(key.len != 0);

        const c = self.data.len;

        const h = hash(key);
        var i = index(c, h);
        var psl: u8 = 0;

        var r: ?*Entry = null;
        while (self.data[i].entry != null) {
            if (psl > self.data[i].psl) {
                // the key is not there
                break;
            }
            if (self.data[i].hash == h) {
                r = self.data[i].entry;
                self.data[i].entry = null;
                break;
            }
            i = index(c, i + 1);
            psl += 1;
        }

        if (r == null) {
            debug("key not found", .{});
            return null;
        }

        debug("removing {s} at {}\n", .{ r.?.get_key(), i });

        var j: u32 = index(c, i + 1);
        while (self.data[j].entry != null) {
            debug("checking neighbor at {any}\n", .{j});
            if (self.data[j].psl > 0) {
                self.data[j].psl -= 1;
                debug("swapping with neighbor {any} at {any}\n", .{ self.data[j], j });

                const dest = index(c, j + c - 1);

                std.mem.swap(Bucket, &self.data[j], &self.data[dest]);
            } else {
                break;
            }
            j = index(c, j + 1);
        }
        debug("returning {any}\n", .{r});

        self.len -= 1;
        return r;
    }

    fn check_grow(self: *HashMap) !void {
        const load: f32 = @as(f32, @floatFromInt(self.len)) / @as(f32, @floatFromInt(self.data.len));
        if (load > LOAD_THRESH) {
            warn("hashmap grow triggered!, cur len={}", .{self.len});
            self.print();
            try self.grow();
        }
        return;
    }

    fn grow(self: *HashMap) !void {
        const old_map = self.data;
        const old_cap = old_map.len;
        defer self.al.free(old_map);

        // we double the capacity
        self.data = try self.al.alloc(Bucket, old_cap * 2);
        @memset(self.data, .{ .psl = 0, .hash = 0, .entry = null });

        for (0..self.len) |i| {
            const slot = old_map[i];
            if (slot.entry) |e| {
                self.insert_helper(e);
            }
        }

        info("hashmap grow successful, new cap: {}", .{self.data.len});
        self.print();
    }

    fn hash(key: []const u8) Hash {
        var hasher: std.hash.SipHash64(2, 4) = .init(HASH_KEY[0..16]);
        hasher.update(key);
        return hasher.finalInt();
    }

    pub fn is_empty(self: HashMap) bool {
        return self.len == 0;
    }

    inline fn index(c: usize, x: u64) u32 {
        // only power of two capacity values are permitted to enable faster modulo
        std.debug.assert((c & (c - 1)) == 0);
        return @intCast(x & (c - 1));
    }
};

// schema: [key len: usize][val len: usize][data u8]
pub const Entry = struct {
    data: [*]u8,

    const s = @sizeOf(u32);

    fn encode(al: std.mem.Allocator, key: []const u8, value: []const u8) !*Entry {
        std.debug.assert(key.len != 0);
        std.debug.assert(value.len != 0);

        if (key.len > MAX_KEY_SIZE) {
            return error.KeySizeExceeded;
        }

        if (value.len > MAX_VALUE_SIZE) {
            return error.ValueSizeExceeded;
        }

        const kl: u32 = @intCast(key.len);
        const vl: u32 = @intCast(value.len);

        const data = try al.alignedAlloc(u8, .@"8", kl + vl + (s * 2));

        std.mem.writeInt(u32, data[0..s], kl, .little);
        std.mem.writeInt(u32, data[s .. s * 2], vl, .little);

        @memcpy(data[s * 2 .. s * 2 + kl], key);
        @memcpy(data[s * 2 + kl .. s * 2 + kl + vl], value);

        const e: *Entry = @ptrCast(data.ptr);

        std.debug.assert(@intFromPtr(e) == @intFromPtr(data.ptr));
        return e;
    }

    fn key_len(self: *Entry) u32 {
        const data: [*]u8 = @ptrCast(self);
        return std.mem.readInt(u32, data[0..s], .little);
    }

    fn val_len(self: *Entry) u32 {
        const data: [*]u8 = @ptrCast(self);
        return std.mem.readInt(u32, data[s .. s * 2], .little);
    }

    pub fn get_key(self: *Entry) []const u8 {
        const data: [*]u8 = @ptrCast(self);
        const kl = self.key_len();
        return data[s * 2 .. s * 2 + kl];
    }

    pub fn get_val(self: *Entry) []const u8 {
        const data: [*]u8 = @ptrCast(self);
        const kl = self.key_len();
        const vl = self.val_len();
        return data[s * 2 + kl .. s * 2 + kl + vl];
    }

    pub fn print(self: *Entry) void {
        const kl = self.key_len();
        const vl = self.val_len();
        const k = self.get_key();
        const v = self.get_val();

        std.debug.print("Entry: klen = {}, vlen = {}, key = {s}, val = {s}\n", .{ kl, vl, k, v });

        return;
    }

    pub fn len(self: *Entry) u32 {
        const kl = self.key_len();
        const vl = self.val_len();
        return 2 * s + kl + vl;
    }

    pub fn destroy(self: *Entry, al: std.mem.Allocator) void {
        const data: [*]align(8) u8 = @ptrCast(self);
        al.free(data[0..self.len()]);
        return;
    }
};

test Entry {
    std.testing.log_level = .debug;
    const alloc = std.testing.allocator;
    const k = "hello";
    const v = "world";

    const e = try Entry.encode(alloc, k, v);
    defer e.destroy(alloc);
    e.print();

    try std.testing.expect(std.mem.eql(u8, e.get_key(), k));
    try std.testing.expect(std.mem.eql(u8, e.get_val(), v));
}

test "hashmap insert/get" {
    std.testing.log_level = .debug;

    const alloc = std.testing.allocator;
    const c = 8;
    std.debug.assert((c & (c - 1)) == 0);

    var map = try HashMap.init(alloc, c);
    defer map.deinit();

    const data = [_][]const u8{ "2", "5", "7", "10", "42", "120" };

    for (0..data.len) |i| {
        const bytes = data[i];
        try map.insert(bytes, bytes);
    }
    try std.testing.expect(map.len == data.len);

    map.print();

    for (0..data.len) |i| {
        const bytes = data[i];
        const res = map.get(bytes).?;

        try std.testing.expect(std.mem.eql(u8, bytes, res.get_key()));
        std.debug.print("key found {s}!\n", .{res.get_key()});
    }
}

test "hashmap delete" {
    std.testing.log_level = .debug;

    const alloc = std.testing.allocator;
    const c = 8;
    std.debug.assert((c & (c - 1)) == 0);

    var map = try HashMap.init(alloc, c);
    defer map.deinit();

    const data = [_][]const u8{ "2", "5", "7", "10", "42", "120" };

    for (0..data.len) |i| {
        const bytes = data[i];
        try map.insert(bytes, bytes);
    }
    try std.testing.expect(map.len == data.len);

    map.print();

    for (0..data.len) |i| {
        std.log.debug("testing {s}\n", .{data[i]});

        const bytes = data[i];
        const res = map.remove(bytes).?;
        defer res.destroy(alloc);

        try std.testing.expect(std.mem.eql(u8, bytes, res.get_key()));
        map.print();
    }
    try std.testing.expect(map.len == 0);
}

test "hashmap insert/get strings" {
    std.testing.log_level = .debug;

    const alloc = std.testing.allocator;
    const c = 8;
    std.debug.assert((c & (c - 1)) == 0);

    var map = try HashMap.init(alloc, c);
    defer map.deinit();

    const s1 = [_][]const u8{ "hello", "world" };
    const s2 = [_][]const u8{ "zig", "awesome" };
    const s3 = [_][]const u8{ "rust", "cool" };

    try map.insert(s1[0], s1[1]);
    try map.insert(s2[0], s2[1]);
    try map.insert(s3[0], s3[1]);
    try std.testing.expect(map.len == 3);

    map.print();

    const res1 = map.get(s1[0]).?;
    try std.testing.expect(std.mem.eql(u8, res1.get_key(), s1[0]));
    try std.testing.expect(std.mem.eql(u8, res1.get_val(), s1[1]));

    const res2 = map.get(s2[0]).?;
    try std.testing.expect(std.mem.eql(u8, res2.get_key(), s2[0]));
    try std.testing.expect(std.mem.eql(u8, res2.get_val(), s2[1]));

    const res3 = map.get(s3[0]).?;
    try std.testing.expect(std.mem.eql(u8, res3.get_key(), s3[0]));
    try std.testing.expect(std.mem.eql(u8, res3.get_val(), s3[1]));
}

test "hashmap regrow" {
    std.testing.log_level = .debug;

    const alloc = std.testing.allocator;
    const c = 8;
    std.debug.assert((c & (c - 1)) == 0);

    var map = try HashMap.init(alloc, c);
    defer map.deinit();

    const n_keys = 10;
    const k = "key";
    const v = "value";

    for (0..n_keys) |i| {
        var key: [4:0]u8 = undefined;
        @memcpy(key[0..3], k);
        key[3] = @as(u8, @intCast(i)) + 48;

        debug("inserting key: {s}\n", .{key});

        try map.insert(&key, v);
    }
    map.print();
    std.debug.assert(map.len == n_keys);
    std.debug.assert(map.data.len == c * 2);
}
