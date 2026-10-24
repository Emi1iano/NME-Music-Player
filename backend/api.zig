const std = @import("std");
const lib = @import("client.zig");

// add [path] - path needs to be relative to the music folder and be a path to a file
// rename [path]  - path needs to be relative to the music folder and be a path to a file
// sync [key] - key is optional and 8bytes between chars '0'-'9' / if key isnt provided load cache for key else generate new key then attempt to connect
// sync_new_key - generates new key without connecting

export fn clientAPI(string: [*:0]const u8) callconv(.c) i32 {
    const buf: []const u8 = std.mem.span(string);

    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();

    var list = std.ArrayList([:0]const u8).initCapacity(gpa.allocator(), 4) catch return -1;
    parse(gpa.allocator(), buf, &list) catch return -1;

    var thread: std.Io.Threaded = .init(gpa.allocator(), .{});
    defer thread.deinit();
    const io = thread.io();

    lib.start(io, list.items) catch return -1;
    return 0;
}
fn parse(alloc: std.mem.Allocator, buf: []const u8, list: *std.ArrayList([:0]const u8)) !void {
    var cur: std.ArrayList(u8) = .empty;
    var in_quotes = false;
    var has_token = false; // so "" still yields an empty arg
    var i: usize = 0;

    while (i < buf.len) : (i += 1) {
        const c = buf[i];

        if (c == '\\' and i + 1 < buf.len and buf[i + 1] == '"') {
            i += 1;
            try cur.append(alloc, '"');
            has_token = true;
        } else if (c == '"') {
            in_quotes = !in_quotes;
            has_token = true;
        } else if (c == ' ' and !in_quotes) {
            if (has_token) {
                try list.append(alloc, try alloc.dupeZ(u8, cur.items));
                cur.clearRetainingCapacity();
                has_token = false;
            }
        } else {
            try cur.append(alloc, c);
            has_token = true;
        }
    }

    if (in_quotes) return error.UnterminatedQuote;
    if (has_token) try list.append(alloc, try alloc.dupeZ(u8, cur.items));
}
test "parse" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    var list = try std.ArrayList([:0]const u8).initCapacity(gpa.allocator(), 4);

    try parse(gpa.allocator(), "add", &list);
    const expected1 = [_][:0]const u8{"add"};
    for (expected1, list.items) |e, g| {
        try std.testing.expectEqualSlices(u8, e, g);
    }
    list.clearRetainingCapacity();
    try parse(gpa.allocator(), "add something", &list);
    const expected2 = [_][:0]const u8{ "add", "something" };
    for (expected2, list.items) |e, g| {
        try std.testing.expectEqualSlices(u8, e, g);
    }
    list.clearRetainingCapacity();
    try parse(gpa.allocator(), "\"add something\"", &list);
    const expected3 = [_][:0]const u8{"add something"};
    for (expected3, list.items) |e, g| {
        try std.testing.expectEqualSlices(u8, e, g);
    }
    list.clearRetainingCapacity();
    try parse(gpa.allocator(), "\"add \\\"something\"", &list);
    const expected4 = [_][:0]const u8{"add \"something"};
    for (expected4, list.items) |e, g| {
        try std.testing.expectEqualSlices(u8, e, g);
    }
    list.clearRetainingCapacity();
}
