const std = @import("std");
const lib = @import("lib.zig");

// rename [path] [newname]
// update [path] playcount [amount]
// update [path] playtime [time in seconds]
// add [path] - when a new song is downloaded or added to library / to make sure it is traacked / can be a folder

test "rename" {
    const io = std.testing.io;
    const alloc = std.testing.allocator;

    try lib.EDITING.clearHistoryFile(io);
    
    try lib.handleArgs(io, &.{ "dummy", "rename", "b.mp3", "a.mp3" });
    try lib.handleArgs(io, &.{ "dummy", "rename", "a.mp3", "b.mp3" });
    try lib.handleArgs(io, &.{ "dummy", "rename", "album1/b.mp3", "a.mp3" });
    try lib.handleArgs(io, &.{ "dummy", "rename", "album1/a.mp3", "b.mp3" });

    const file = try lib.EDITING.openHistoryFile(io);

    var rBuf: [1024]u8 = undefined;
    var reader = file.reader(io, &rBuf);
    var in = &reader.interface;
    const buf = try in.allocRemaining(alloc, .unlimited);
    defer alloc.free(buf);

    var it = std.mem.tokenizeScalar(u8, buf, '\n');

    try std.testing.expectEqualSlices(u8, "rename b.mp3 a.mp3", it.next().?);
    try std.testing.expectEqualSlices(u8, "rename a.mp3 b.mp3", it.next().?);
    try std.testing.expectEqualSlices(u8, "rename album1/b.mp3 a.mp3", it.next().?);
    try std.testing.expectEqualSlices(u8, "rename album1/a.mp3 b.mp3", it.next().?);

    file.close(io);
    try lib.EDITING.clearHistoryFile(io);
}
test "update" {}
test "add" {}
