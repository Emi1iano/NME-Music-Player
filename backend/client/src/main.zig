const std = @import("std");
const builtin = @import("builtin");
const api = @import("api.zig");
const lib = @import("lib.zig");
const Io = std.Io;

// COMMANDS FOR WINDOWS
// sync [key] - if key isnt provided read from cache if cache empty generate new key / key should be 8 bytes
// sync_new_key - generate new key
// rename [path] [newname]
// update [path] playcount [amount]
// update [path] playtime [time in seconds]
// add [path] - when a new song is downloaded or added to library / to make sure it is traacked / can be a folder
// 

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    // const string: [*:0]const u8 = "sync 12345679";
    // const i = api.clientAPI(string);
    // std.debug.print("exit code {d}\n", .{i});

    try lib.handleArgs(init.io,args);
}

