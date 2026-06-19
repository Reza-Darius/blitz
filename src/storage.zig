const std = @import("std");
const map = @import("hashmap.zig");

pub const Storage = struct {
    store: map.HashMap,

    pub fn init(allocator: std.mem.Allocator) !Storage {
        return .{ .store = try map.HashMap.init(allocator, 1024) };
    }
};
