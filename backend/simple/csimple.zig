const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Shared = @import("shared.zig");
const MTU_BUF = [Shared.MTU_SIZE]u8;
const Code = Shared.Code;
const Songs = std.ArrayList(Song);
const Songs_R = std.ArrayList(*const Song);
const Hashes = std.ArrayList([32]u8);

pub const Local_Testing: bool = false;
const app_path = "testing2/app";
const song_extensions = [_][]const u8{ ".mp3", ".opus", ".flac", ".m4a" };

//TODO optimize music table to shorten paths
//TODO file formats like mp3 store metadata and if that changes hash is different

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    try start(init.io, args[1..]);
}
pub fn start(io: std.Io, args: []const []const u8) !void {
    try Client.start(io);
    _ = args;
    // if (args.len > 1) {
    //     if (std.mem.eql(u8, "add", args[0])) {
    //         try Add.add(io, args[1]);
    //         return;
    //     }
    // }
    // // Load songs
    // var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer gpa.deinit();
    // var songs = try Songs.initCapacity(gpa.allocator(), 8);
    // try loadSongs(io, &songs, gpa.allocator());
    // std.debug.print("Songs Loaded: {d}\n", .{songs.items.len});
    // // Send hashes
    // try sendHashes(&songs);
    // // Recieve hashes
    // var hashes = try Hashes.initCapacity(gpa.allocator(), 8);
    // try recieveHashes(&hashes, gpa.allocator());
    // std.debug.print("Hashes Recieved: {x}\n", .{hashes.items.len});
    // // Find differing hashes
    // var d_songs = try Songs_R.initCapacity(gpa.allocator(), 8);
    // try findDifferingSongs(&d_songs, &songs, &hashes, gpa.allocator());
    // std.debug.print("Sending {d} songs\n", .{d_songs.items.len});
    // // Send differing songs
    // try sendSongs(&d_songs);
    // // Recieve differing songs
    // try recieveSongs();

}

const Client = struct {
    fn start(io: Io) !void {
        var socket = try getClientSocket(io);
        defer socket.close(io);

        try sendInitialMessage(io, socket);
        var buf: MTU_BUF = undefined;
        const message = try socket.receive(io, &buf);
        const d = message.data[1..];
        std.debug.print("Other client public ip: {d}.{d}.{d}.{d}:{d}", .{d[0], d[1], d[2], d[3], std.mem.readInt(u16, d[4..6], .little)});
    }
    // TEST ------------------------------
    // TEST Use proper send like mysend.send
    /// 1 byte code, 6 byte local ip, 8 byte key
    fn sendInitialMessage(io: Io, socket: net.Socket) !void {
        var buf: MTU_BUF = undefined;
        const message = try std.fmt.bufPrint(buf[0..], "{s}{s}{s}", .{ Code.getByte(.INITIAL), try getLocalIpAndPort(io), getKey() });
        const ip = try getServerIp();
        try socket.send(io, &ip, message);
    }
    //FIXME
    fn getKey() [8]u8 {
        return @splat('a');
    }
    //FIXME
    fn getLocalIpAndPort(io: Io) ![6]u8 {
        _ = io;
        return @splat(0);
    }
    fn getClientSocket(io: Io) !net.Socket {
        const client_port: u16 = 32145;
        var client = try Io.net.IpAddress.parse("0.0.0.0", client_port);
        var client_socket: std.Io.net.Socket = undefined;
        while (true) {
            if (client.bind(io, .{ .mode = .dgram })) |socket| {
                client_socket = socket;
                break;
            } else |err| switch (err) {
                error.AddressInUse => {
                    client.setPort(client.ip4.port + 1);
                },
                else => {
                    return err;
                },
            }
        }
        return client_socket;
    }
    fn getServerIp() !net.IpAddress {
        if (Local_Testing) return try std.Io.net.IpAddress.parse("172.28.41.169", 5252);
        return try std.Io.net.IpAddress.parse("24.243.26.72", 5252);
    }
};
const Song = struct {
    hash: [32]u8,
    path: []const u8,
    play_time: u32,
    play_count: u32,
};
const Add = struct {
    var group: std.Io.Group = .init;
    // ! maybe use file.lock instead of this lock
    var lock: std.Io.Mutex = .init;
    fn add(io: std.Io, path: []const u8) !void {
        var table_f = try getTableFile(io);
        defer table_f.close(io);
        switch (std.mem.eql(u8, "", std.Io.Dir.path.extension(path))) {
            true => {
                const dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
                defer dir.close(io);
                try addRecurse(io, dir, table_f);
            },
            false => {
                if (!isSong(path)) return;
                const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
                try addFile(io, file, table_f);
            },
        }
        try group.await(io);
    }
    fn addRecurse(io: std.Io, dir: std.Io.Dir, table_f: std.Io.File) !void {
        var it = dir.iterate();
        while (it.next(io)) |e| {
            if (e == null) break;
            switch (e.?.kind) {
                .file => {
                    if (!isSong(e.?.name)) continue;
                    const file = try dir.openFile(io, e.?.name, .{});
                    try addFile(io, file, table_f);
                },
                .directory => {
                    std.debug.print("scanning: {s}\n", .{e.?.name});
                    var dir1 = try dir.openDir(io, e.?.name, .{ .iterate = true });
                    defer dir1.close(io);
                    try addRecurse(io, dir1, table_f);
                },
                else => {},
            }
        } else |_| {}
    }
    fn addFile(io: std.Io, file: std.Io.File, table_f: std.Io.File) !void {
        try group.concurrent(io, addFileThreadWrapper, .{ io, file, table_f });
    }
    fn addFileThreadWrapper(io: std.Io, file: std.Io.File, table_f: std.Io.File) void {
        addFileThread(io, file, table_f) catch {
            std.debug.print("Error hashing file\n", .{});
            return;
        };
    }
    fn addFileThread(io: std.Io, file: std.Io.File, table_f: std.Io.File) !void {
        var buf: [256]u8 = undefined;
        const len = try file.realPath(io, &buf);

        const hash = try hashFile(io, file);
        file.close(io);

        var wBuf: [1024]u8 = undefined;
        var writer = table_f.writer(io, &wBuf);
        var w = &writer.interface;
        const count: u32 = 0;
        const time: u32 = 0;
        try lock.lock(io);
        try writer.seekTo(try table_f.length(io));
        try w.print("{s}", .{hash});
        try w.writeInt(u32, count, .native);
        try w.writeInt(u32, time, .native);
        try w.print("{s}\n", .{buf[0..len]});
        try writer.end();
        std.debug.print("added: {s}\n", .{std.Io.Dir.path.basename(buf[0..len])});
        lock.unlock(io);
    }
    fn hashFile(io: std.Io, file: std.Io.File) ![32]u8 {
        var result: [32]u8 = undefined;
        var b = std.crypto.hash.Blake3.init(.{});

        var buf: [1024 * 256]u8 = undefined;
        var reader = file.reader(io, &buf);
        var r = &reader.interface;

        //var data: [1024 * 64]u8 = undefined;
        while (true) {
            const chunk = r.peekGreedy(1) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
            b.update(chunk);
            r.toss(chunk.len);
            //const len = try r.readSliceShort(&data);
            // b.update(data[0..len]);
            // if (len != data.len) break;
        }

        b.final(&result);
        return result;
    }
    fn getTableFile(io: std.Io) !std.Io.File {
        const cwd = std.Io.Dir.cwd();

        const dir = cwd.openDir(io, app_path, .{}) catch try cwd.createDirPathOpen(io, app_path, .{});
        defer dir.close(io);
        return dir.openFile(io, "music_table.txt", .{ .mode = .read_write }) catch try dir.createFile(io, "music_table.txt", .{ .read = true });
    }
    fn isSong(path: []const u8) bool {
        const extension = std.Io.Dir.path.extension(path);
        for (song_extensions) |e| {
            if (std.mem.eql(u8, e, extension)) return true;
        }
        return false;
    }
};
fn loadSongs(io: std.Io, songs: *Songs, alloc: std.mem.Allocator) !void {
    var file: std.Io.File = blk: {
        const cwd = std.Io.Dir.cwd();

        const dir = cwd.openDir(io, app_path, .{}) catch try cwd.createDirPathOpen(io, app_path, .{});
        break :blk dir.openFile(io, "music_table.txt", .{}) catch try dir.createFile(io, "music_table.txt", .{});
    };
    defer file.close(io);
    var rBuf: [1024]u8 = undefined;
    var reader = file.reader(io, &rBuf);
    var r = &reader.interface;
    while (true) {
        const hash = r.take(32) catch break;
        const play_count = try r.takeInt(u32, .native);
        const play_time = try r.takeInt(u32, .native);
        const pre = try r.takeDelimiter('\n');
        const path = try alloc.dupe(u8, pre.?);
        try songs.append(alloc, .{ .hash = hash[0..32].*, .path = path, .play_count = play_count, .play_time = play_time });
    }
}
fn sendHashes(songs: *Songs) !void {
    for (songs.items) |song| {
        //std.debug.print("Sending Hash: {x}\n", .{&song.hash});
        _ = song;
    }
}
fn recieveHashes(hashes: *Hashes, alloc: std.mem.Allocator) !void {
    try hashes.append(alloc, @splat(101));
    // try hashes.append(alloc, @splat(100));
}
fn findDifferingSongs(d_songs: *Songs_R, songs: *Songs, o_hashes: *Hashes, alloc: std.mem.Allocator) !void {
    for (songs.items) |*song| {
        for (o_hashes.items) |hash| {
            if (std.mem.eql(u8, &song.*.hash, &hash)) break;
        } else {
            // std.debug.print("Missing Hash: {x}\n", .{&song.hash});
            try d_songs.append(alloc, song);
        }
    }
}
fn sendSongs(songs: *Songs_R) !void {
    _ = songs;
    // for (songs.items) |song| {
    //     std.debug.print("Sending song: {s}\n", .{song.*.path});
    // }
}
fn recieveSongs() !void {}
const MySend = struct {
    buffer: []u8,
    end: usize = 0,
    io: std.Io,
    fn init(io: std.Io, buf: []u8) @This() {
        return .{
            .buffer = buf,
            .io = io,
        };
    }
    fn writeAll(self: *@This(), bytes: []const u8) !void {
        var index: usize = 0;
        while (index < bytes.len) index += try self.write(bytes[index..]);
    }
    pub fn write(self: *@This(), bytes: []const u8) !usize {
        if (self.end + bytes.len <= self.buffer.len) {
            @branchHint(.likely);
            @memcpy(self.buffer[self.end..][0..bytes.len], bytes);
            self.end += bytes.len;
            return bytes.len;
        }
        return try self.drain(bytes);
    }
    fn drain(self: *@This(), bytes: []const u8) !usize {
        const space = self.buffer.len - self.end;
        const n = @min(space, bytes.len);
        @memcpy(self.buffer[self.end..][0..n], bytes[0..n]);
        self.end += n;

        std.debug.print("{s}\n", .{self.buffer[0..self.end]});
        self.end = 0;
        return n;
    }
    fn flush(self: *@This()) !void {
        if (self.end == 0) return;
        _ = try self.drain("");
    }
    fn buffered(self: *@This()) []u8 {
        return self.buffer[0..self.end];
    }
};

test "idk" {
    const io = std.testing.io;
    var thread = try std.process.spawn(io, .{ .argv = &.{ "chcp", "65001" } });
    _ = try thread.wait(io);
    // TEST ---------------------------------------
    {
        const table_f = try Add.getTableFile(io);
        var w = table_f.writer(io, &.{});
        try w.end();
        table_f.close(io);
    }

    const timestamp = std.Io.Timestamp.now(io, .awake);
    try start(io, &.{ "add", "C:/Users/Emi1iano/Music/Test/idk/" });
    // try main(io, &.{"add", "C:/Users/Emi1iano/Music/Music/"});
    try start(io, &.{});
    const d = timestamp.durationTo(std.Io.Timestamp.now(io, .awake)).toMilliseconds();

    std.debug.print("Seconds {d}\n", .{d});
}
