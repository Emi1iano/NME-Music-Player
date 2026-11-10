const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const net = Io.net;

//TODO make music table take less space by shortening paths
const CHAT_MODE = false;

const app_path = "testing2/app";
const song_extensions = [_][]const u8{ ".mp3", ".opus", ".flac", ".m4a" };

const Song = struct {
    hash: [32]u8,
    path: []const u8 = undefined,
    play_time: u32 = 0,
    play_count: u32 = 0,
};
const Songs = std.ArrayList(Song);
const Songs_R = std.ArrayList(*const Song);

const Client = struct {
    fn client(io: std.Io, key: []const u8) !void {
        const ip = try std.Io.net.IpAddress.parse("24.243.26.72", 5252);

        var stream = ip.connect(io, .{ .mode = .stream }) catch |err| switch (err) {
            error.ConnectionRefused => {
                std.debug.print("Server down\n", .{});
                return;
            },
            else => return err,
        };
        defer stream.close(io);

        var rbuf: [1024 * 64]u8 = undefined;
        var wbuf: [1024 * 64]u8 = undefined;
        var reader = stream.reader(io, &rbuf);
        var writer = stream.writer(io, &wbuf);
        const r = &reader.interface;
        const w = &writer.interface;

        try w.writeByte(@intCast(key.len));
        try w.writeAll(key);
        try w.flush();

        var clients: std.Io.Group = .init;
        defer clients.cancel(io);
        if (CHAT_MODE) {
            try clients.concurrent(io, ChatMode.recieving, .{ io, r });
            ChatMode.sending(io, w, stream);
        } else {
            const gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();
            var sync: Syncing = .{ .gpa = gpa };
            try clients.concurrent(io, Syncing.recieveWrap, .{ &sync, io, r });
            try sync.sending(io, w, stream);
            try clients.await(io);
        }
    }
    const ChatMode = struct {
        fn sending(io: Io, w: *Io.Writer, stream: net.Stream) void {
            var buf: [1024]u8 = undefined;
            while (true) {
                const in = cin(io, &buf);
                if (std.mem.eql(u8, "exit", in)) {
                    stream.shutdown(io, .both) catch break;
                    return;
                }
                _ = w.writeAll(in) catch continue;
                w.flush() catch {};
            }
        }
        fn recieving(io: Io, r: *Io.Reader) void {
            _ = io;
            var buf: [1024]u8 = undefined;
            var w = Io.Writer.fixed(&buf);

            while (true) {
                _ = r.stream(&w, .unlimited) catch break;
                std.debug.print("{s}\n", .{w.buffered()});
                _ = w.consumeAll();
            }
        }
    };
};
const FileManager = struct {
    const Add = struct {
        var group: std.Io.Group = .init;
        var lock: std.Io.Mutex = .init;
        fn add(io: std.Io, path: []const u8) !void {
            var table_f = try getTableFile(io);
            defer table_f.close(io);
            var buf: [1024 * 4]u8 = undefined;
            var writer = table_f.writer(io, &buf);
            try writer.seekTo(try table_f.length(io));
            const w = &writer.interface;
            switch (std.mem.eql(u8, "", std.Io.Dir.path.extension(path))) {
                true => {
                    const dir = std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch |err| switch (err) {
                        error.FileNotFound => {
                            std.debug.print("Directory from path not found\n", .{});
                            return;
                        },
                        else => return err,
                    };
                    defer dir.close(io);
                    try addRecurse(io, dir, w);
                },
                false => {
                    if (!isSong(path)) return;
                    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch |err| switch (err) {
                        error.FileNotFound => {
                            std.debug.print("File from path not found\n", .{});
                            return;
                        },
                        else => return err,
                    };
                    try addFile(io, file, w);
                },
            }
            try group.await(io);
            try w.flush();
            try Paths.add(io, path);
        }
        fn addRecurse(io: std.Io, dir: std.Io.Dir, table_w: *std.Io.Writer) !void {
            var it = dir.iterate();
            while (it.next(io)) |e| {
                if (e == null) break;
                switch (e.?.kind) {
                    .file => {
                        if (!isSong(e.?.name)) continue;
                        const file = try dir.openFile(io, e.?.name, .{});
                        try addFile(io, file, table_w);
                    },
                    .directory => {
                        std.debug.print("scanning: {s}\n", .{e.?.name});
                        var dir1 = try dir.openDir(io, e.?.name, .{ .iterate = true });
                        defer dir1.close(io);
                        try addRecurse(io, dir1, table_w);
                    },
                    else => {},
                }
            } else |_| {}
        }
        fn addFile(io: std.Io, file: std.Io.File, table_w: *std.Io.Writer) !void {
            try group.concurrent(io, addFileThreadWrapper, .{ io, file, table_w });
        }
        fn addFileThreadWrapper(io: std.Io, file: std.Io.File, table_w: *std.Io.Writer) void {
            addFileThread(io, file, table_w) catch {
                std.debug.print("Error hashing file\n", .{});
                return;
            };
        }
        fn addFileThread(io: std.Io, file: std.Io.File, table_w: *std.Io.Writer) !void {
            var buf: [256]u8 = undefined;
            const len = try file.realPath(io, &buf);

            const hash = try hashFile(io, file);
            file.close(io);

            const count: u32 = 0;
            const time: u32 = 0;
            try lock.lock(io);
            try table_w.print("{s}", .{hash});
            try table_w.writeInt(u32, count, .native);
            try table_w.writeInt(u32, time, .native);
            try table_w.print("{s}\n", .{buf[0..len]});
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
        fn clearTable(io: Io) !void {
            const table_f = try getTableFile(io);
            var w = table_f.writer(io, &.{});
            try w.end();
            table_f.close(io);
        }
    };
    const Key = struct {
        fn saveKey(io: Io, buf: []const u8) !void {
            var file = try getKeyFile(io);
            defer file.close(io);
            var wbuf: [256]u8 = undefined;
            var writer = file.writer(io, &wbuf);
            var w = &writer.interface;

            _ = try w.writeAll(buf);
            try writer.end();
        }
        fn getKey(io: Io, buf: []u8) ![]u8 {
            var file = try getKeyFile(io);
            defer file.close(io);
            var rbuf: [256]u8 = undefined;
            var reader = file.reader(io, &rbuf);
            var r = &reader.interface;
            const len = try r.readSliceShort(buf);
            if (len == 0) {
                std.debug.print("Couldnt find key\nGenerated new key\n", .{});
                const key = generateNewKey(io);
                try saveKey(io, &key);
                @memcpy(buf[0..key.len], &key);
                return buf[0..key.len];
            }
            return buf[0..len];
        }
        fn generateNewKey(io: Io) [8]u8 {
            const seed: u64 = @bitCast(std.Io.Timestamp.now(io, .awake).toMicroseconds());
            var rand = std.Random.DefaultPrng.init(seed);

            var key: [8]u8 = undefined;
            for (&key) |*c| {
                const offset: u8 = @intCast(rand.next() % 10);
                c.* = '0' + offset;
            }
            return key;
        }
        fn getKeyFile(io: Io) !Io.File {
            const cwd = std.Io.Dir.cwd();

            const dir = cwd.openDir(io, app_path, .{}) catch try cwd.createDirPathOpen(io, app_path, .{});
            defer dir.close(io);
            return dir.openFile(io, "key.txt", .{ .mode = .read_write }) catch try dir.createFile(io, "key.txt", .{ .read = true });
        }
    };
    const Paths = struct {
        fn idK(io: Io, gpa: std.mem.Allocator, list: *std.ArrayList([]const u8)) !void {
            var file = try getPathsFile(io);
            defer file.close(io);

            var buf: [1024]u8 = undefined;
            var reader = file.reader(io, &buf);
            var r = &reader.interface;
            const content = try r.allocRemaining(gpa, .unlimited);
            var it = std.mem.tokenizeScalar(u8, content, '\n');
            while (it.next()) |line| {
                try list.append(gpa, line);
            }
        }
        fn add(io: Io, path: []const u8) !void {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();
            var file = try getPathsFile(io);
            defer file.close(io);

            var list = try std.ArrayList([]const u8).initCapacity(gpa.allocator(), 4);
            try idK(io, gpa.allocator(), &list);
            // if both null return
            // if one or the other null add the path
            // if both not null compare names if the same continue else add the path
            for (list.items) |line| {
                var x = Io.Dir.path.componentIterator(path);
                var y = Io.Dir.path.componentIterator(line);
                while (true) {
                    const x1 = x.next();
                    const y1 = y.next();
                    if (x1 == null and y1 == null) return else if ((x1 == null) ^ (y1 == null)) break;
                    if (eql(x1.?.name, y1.?.name)) continue else break;
                }
            }

            var buf: [1024]u8 = undefined;
            var writer = file.writer(io, &buf);
            var w = &writer.interface;
            try writer.seekTo(try file.length(io));
            try w.print("{s}\n", .{path});
            try w.flush();
        }
        fn clearPathsFile(io: Io) !void {
            const file = try getPathsFile(io);
            var w = file.writer(io, &.{});
            try w.end();
            file.close(io);
        }
    };
    const Rescan = struct {
        fn rescan(io: Io) !void {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();
            var list = try std.ArrayList([]const u8).initCapacity(gpa.allocator(), 4);
            try Paths.idK(io, gpa.allocator(), &list);

            for (list.items) |line| {
                try Add.add(io, line);
            }
        }
    };
    fn loadSongs(io: std.Io, songs: *Songs, alloc: std.mem.Allocator) !void {
        var file = try Add.getTableFile(io);
        defer file.close(io);

        var rBuf: [1024]u8 = undefined;
        var reader = file.reader(io, &rBuf);
        var r = &reader.interface;
        while (true) {
            const hash = r.take(32) catch break;
            songs.append(alloc, .{ .hash = hash[0..32].* }) catch unreachable;
            const song = songs.lastPtr() orelse unreachable;
            song.*.play_count = try r.takeInt(u32, .native);
            song.*.play_time = try r.takeInt(u32, .native);
            const pre = try r.takeDelimiter('\n');
            if (pre == null) {
                std.debug.print("NULL IN LOADSONGS\n", .{});
                continue;
            }
            song.*.path = try alloc.dupe(u8, pre.?);
        }
    }
    fn getMusicDir(io: std.Io) !std.Io.Dir {
        const cwd = std.Io.Dir.cwd();

        const dir = cwd.openDir(io, app_path ++ "/music", .{}) catch try cwd.createDirPathOpen(io, app_path ++ "/music", .{});
        return dir;
    }
    fn getPathsFile(io: std.Io) !std.Io.File {
        const cwd = std.Io.Dir.cwd();

        const dir = cwd.openDir(io, app_path, .{}) catch try cwd.createDirPathOpen(io, app_path, .{});
        defer dir.close(io);
        return dir.openFile(io, "paths.txt", .{ .mode = .read_write }) catch try dir.createFile(io, "paths.txt", .{ .read = true });
    }
};
const Syncing = struct {
    o_hashes: myEvent(Hashes) = .init(),
    start_sending: std.Io.Event = .unset,
    gpa: std.heap.ArenaAllocator,

    fn sending(self: *@This(), io: Io, w: *Io.Writer, stream: net.Stream) !void {
        var songs = try Songs.initCapacity(self.gpa.allocator(), 8);

        try FileManager.loadSongs(io, &songs, self.gpa.allocator());
        std.debug.print("Loaded {d} songs\n", .{songs.items.len});

        // SEND HASHES
        {
            if (!self.start_sending.isSet()) std.debug.print("\n", .{});
            var count: usize = 0;
            var buf: [3]u8 = @splat(' ');
            var i: usize = 0;
            while (!self.start_sending.isSet()) {
                std.debug.print("\x1B[1FWaiting for other client{s}\n", .{buf});
                try io.sleep(.fromMilliseconds(10), .awake);
                if (count % 30 == 0) {
                    if (i % 4 == 0) {
                        buf = @splat(' ');
                    } else {
                        buf[i % 4 - 1] = '.';
                    }
                    i += 1;
                }
                count += 1;
            }
            std.debug.print("Sending Hashes\n", .{});

            try w.writeInt(u32, @intCast(songs.items.len), .little);
            for (songs.items) |*song| {
                try w.writeAll(&song.*.hash);
            }
            try w.flush();
        }

        var d_songs: Songs_R = try .initCapacity(self.gpa.allocator(), 8);
        // FIND DIFFERING HASHES
        {
            try self.o_hashes.wait(io);
            std.debug.print("Hashes Recieved: {d}\n", .{self.o_hashes.data.len()});
            for (songs.items) |*song| {
                for (0..self.o_hashes.data.len()) |i| {
                    if (std.mem.eql(u8, &song.*.hash, self.o_hashes.data.get(i).?)) break;
                } else {
                    try d_songs.append(self.gpa.allocator(), song);
                }
            }
        }

        // SEND DIFFERING SONGS
        {
            for (d_songs.items) |song| {
                var file = std.Io.Dir.openFileAbsolute(io, song.*.path, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        std.debug.print("File {s} not found\n", .{song.*.path});
                        continue;
                    },
                    else => return err,
                };
                defer file.close(io);

                const basename = Io.Dir.path.basename(song.*.path);
                try w.writeInt(u64, basename.len, .little);
                try w.writeAll(basename);
                try w.writeInt(u64, try file.length(io), .little);

                var buf: [1024 * 64]u8 = undefined;
                var reader = file.reader(io, &buf);
                var r = &reader.interface;
                _ = r.streamRemaining(w) catch break;
            }
            try w.flush();
        }

        try stream.shutdown(io, .send);
    }
    fn recieveWrap(self: *@This(), io: Io, r: *Io.Reader) void {
        self.recieving(io, r) catch |err| {
            std.debug.print("Error recieving: {any}\n", .{err});
        };
    }
    fn recieving(self: *@This(), io: Io, r: *Io.Reader) !void {
        // WAIT FOR INITIAL MESSAGE
        {
            _ = try r.takeByte();
            var buf: [1024]u8 = undefined;
            var w = Io.Writer.fixed(&buf);
            while (true) {
                _ = r.stream(&w, .unlimited) catch break;
                if (eql("STARTSENDING", w.buffered())) {
                    self.start_sending.set(io);
                    _ = w.consumeAll();
                    break;
                }
            }
        }

        // GET OTHER CLIENTS HASHES
        {
            const n = try r.takeInt(u32, .little);
            const buf = try r.readAlloc(self.gpa.allocator(), n * 32);
            self.o_hashes.data.buf = buf;
            self.o_hashes.set(io);
        }

        // RECIEVE SONGS
        {
            var music_dir = try FileManager.getMusicDir(io);
            defer music_dir.close(io);
            const s = Io.Timestamp.now(io, .awake);
            var total: usize = 0;
            var group = std.Io.Group.init;
            var table_f = try FileManager.Add.getTableFile(io);
            defer table_f.close(io);
            var buf1: [1024 * 4]u8 = undefined;
            var writer1 = table_f.writer(io, &buf1);
            try writer1.seekTo(try table_f.length(io));
            const w1 = &writer1.interface;
            std.debug.print("\n\n\n", .{});
            while (true) {
                const b_len = r.takeInt(u64, .little) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };
                var basename_buf: [255]u8 = undefined;
                const basename = basename_buf[0..b_len];
                try r.readSliceAll(basename);

                const f_len = try r.takeInt(u64, .little);

                var file = try music_dir.createFile(io, basename, .{ .read = true });
                var buf: [1024 * 64]u8 = undefined;
                var writer = file.writer(io, &buf);
                const w = &writer.interface;

                _ = try r.streamExact64(w, f_len);
                total += f_len;
                try writer.end();
                try group.concurrent(io, FileManager.Add.addFileThreadWrapper, .{ io, file, w1 });

                std.debug.print("\x1B[2F\x1B[2KRecieved: {d} bytes: {s}\n", .{ f_len, basename });
                const elapsed_ns: u64 = @intCast(s.untilNow(io, .awake).toNanoseconds());
                const secs = @as(f64, @floatFromInt(@max(elapsed_ns, 1))) / 1e9;
                const bps = @as(f64, @floatFromInt(total)) / secs;
                std.debug.print("\x1B[2KSpeed {d:.2}MB/S\n", .{bps / 1000000});
            }
            try group.await(io);
            try w1.flush();
            std.debug.print("Time took: {d:.1} seconds\n", .{@as(f64, @floatFromInt(s.untilNow(io, .awake).toMilliseconds())) / 1000});
        }
    }
    const Hashes = struct {
        buf: []const u8,
        fn init(buf: []const u8) @This() {
            return .{
                .buf = buf,
            };
        }
        /// null is returned if idx is out of bounds
        fn get(self: *@This(), idx: usize) ?[]const u8 {
            const i: usize = idx * 32;
            if (self.buf.len < i) return null;
            return self.buf[i .. i + 32];
        }
        fn len(self: *@This()) usize {
            return self.buf.len / 32;
        }
    };
    fn myEvent(comptime T: type) type {
        return struct {
            data: T,
            event: std.Io.Event,
            fn init() @This() {
                return .{
                    .data = undefined,
                    .event = .unset,
                };
            }
            fn wait(self: *@This(), io: Io) !void {
                return self.event.wait(io);
            }
            fn set(self: *@This(), io: Io) void {
                self.event.set(io);
            }
        };
    }
};

pub fn main(init: std.process.Init) !void {
    if (builtin.target.os.tag == .windows) {
        var thread = try std.process.spawn(init.io, .{ .argv = &.{ "chcp", "65001" }, .stdout = .ignore });
        _ = try thread.wait(init.io);
    }
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    try start(init.io, args[1..]);
}
pub fn start(io: std.Io, args: []const []const u8) !void {
    var buf: [256]u8 = undefined;
    switch (args.len) {
        0 => {
            try Client.client(io, try FileManager.Key.getKey(io, &buf));
        },
        1 => {
            if (eql("sync", args[0])) {
                try Client.client(io, try FileManager.Key.getKey(io, &buf));
            } else if (eql("resettable", args[0])) {
                try FileManager.Add.clearTable(io);
            } else if (eql("sync_new_key", args[0])) {
                try FileManager.Key.saveKey(io, &FileManager.Key.generateNewKey(io));
            } else if (eql("resetpaths", args[0])) {
                try FileManager.Paths.clearPathsFile(io);
            } else if (eql("rescan", args[0])) {
                try FileManager.Add.clearTable(io);
                try FileManager.Rescan.rescan(io);
            }
        },
        2 => {
            if (eql("sync", args[0])) {
                try FileManager.Key.saveKey(io, args[1]);
                try Client.client(io, args[1]);
            } else if (eql("add", args[0])) {
                try FileManager.Add.add(io, args[1]);
            }
        },
        else => {},
    }
}
fn cin(io: Io, buffer: []u8) []u8 {
    var rbuffer: [256]u8 = undefined;
    var stdin = Io.File.stdin().reader(io, &rbuffer);
    var input = &stdin.interface;

    var writer = std.Io.Writer.fixed(buffer);

    const len = input.streamDelimiter(&writer, '\n') catch 1;

    if (builtin.os.tag == .windows) {
        return buffer[0 .. len - 1];
    } else return buffer[0..len];
}
fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
