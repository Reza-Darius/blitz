const std = @import("std");
const utils = @import("utils.zig");

const info = std.log.info;
const debug = std.log.debug;
const l_err = std.log.err;
const warn = std.log.warn;

const MAP_SIZE = map_size(1024);

fn map_size(n: comptime_int) comptime_int {
    comptime std.debug.assert((n & (n - 1)) == 0);
    return n;
}

pub const HashMap = struct {
    len: u32,
    data: []Bucket,
    al: std.mem.Allocator,

    const Hash = u64;
    const Entry = []u8;
    const KEY = "secret key";

    const Bucket = struct {
        psl: u8,
        hash: Hash,
        entry: ?Entry,
    };

    pub fn init(allocator: std.mem.Allocator) !HashMap {
        return .{
            .len = 0,
            .data = try allocator.alloc(Bucket, MAP_SIZE),
            .al = allocator,
        };
    }

    pub fn deinit(self: *HashMap) void {
        // loop over entire map for deallocation?
        self.al.free(self.data);
        return ;
    }

    pub fn insert(self: *HashMap, key: []u8, elem: Entry) void {
        var b: Bucket = .{
            .psl = 0,
            .hash = hash(key),
            .entry = elem,
        };

        var idx = index(b.hash);

        while (self.data[idx].entry != null) {
            if (b.psl > self.data[idx].psl) {
                std.mem.swap(Bucket, &self.data[idx], &b);
            }
            idx = index(idx + 1);
            b.psl += 1;
        }

        self.data[idx] = b;
        self.len += 1;
        return;
    }

    pub fn get(self: HashMap, key: []u8) ?Entry {
        var psl = 0;
        const h = hash(key);
        var idx = index(h);

        while (self.data[idx].entry != null) {
            if (self.data[idx].hash == h) {
                return self.data[idx].entry;
            }
            if (psl > self.data[idx].psl) {
                return null;
            }
            idx = index(idx + 1);
            psl += 1;
        }
        return null;
    }

    pub fn remove(self: *HashMap, key: []u8) ?Entry {
        const i = index(hash(key));

        if (self.data[i].entry == null) return null;

        const r = self.data[i].entry;
        self.data[i].entry = null;

        var j = i + 1;
        while (self.data[j].entry != null) : (j += 1) {
            if (self.data[j].psl > 0) {
                self.data[j].psl -= 1;
                std.mem.swap(Bucket, &self.data[j], &self.data[j - 1]);
            } else {
                break;
            }
        }
        return r;
    }

    fn grow() void {}

    fn hash(elem: Entry) Hash {
        const hasher: std.hash.SipHash64(2, 4) = .init(KEY);
        hasher.update(elem);
        
        return hasher.finalInt();
    }

    fn load(self: HashMap) f32 {
        return self.len / self.data.len;
    }

    inline fn index(h: Hash) u32 {
        return h & (MAP_SIZE - 1);
    }
};
