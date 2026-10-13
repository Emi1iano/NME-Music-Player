const std = @import("std");
const lib = @import("client.zig");

// add [path] - path needs to be relative to the music folder and be a path to a file
// rename [path]  - path needs to be relative to the music folder and be a path to a file
// sync [key] - key is optional and 8bytes between chars '0'-'9' / if key isnt provided load cache for key else generate new key then attempt to connect
// sync_new_key - generates new key without connecting

export fn clientAPI(string: [*:0]const u8) callconv(.c) i32 {
    const buf: []const u8 = std.mem.span(string);
    var it = std.mem.tokenizeScalar(u8, buf, ' ');

    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    var alloc = gpa.allocator();

    var list = std.ArrayList([:0]const u8).initCapacity(alloc, 4) catch return -1;
    while (it.next()) |arg| {
        const arg_z = alloc.dupeZ(u8, arg) catch return -1;
        list.append(alloc, arg_z) catch return -1;
    }

    var thread: std.Io.Threaded = .init(alloc, .{});
    defer thread.deinit();
    const io = thread.io();

    lib.start(io, list.items) catch return -1;
    return 0;
}