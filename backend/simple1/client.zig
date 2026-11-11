const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const net = Io.net;

//TODO make music table take less space by shortening paths
//TODO use the default music dirs of respective os windows - /users/$USER/Music android - /Music?
//TODO commit the changes
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
    const MusicTable = struct {
        set: SetType,
        arena: std.heap.ArenaAllocator,
        io: Io,
        file: Io.File,

        const SetType = std.AutoHashMap([32]u8, MusicEntry);
        const MusicEntry = struct {
            path: []const u8,
            play_count: u32,
            play_time: u32,
        };
        fn init(io: Io) @This() {
            return .{
                .set = undefined,
                .arena = .init(std.heap.page_allocator),
                .io = io,
                .file = getFile(io),
            };
        }
        fn deinit(self: *@This()) void {
            self.set.deinit();
            self.arena.deinit();
        }
        fn start(self: *@This()) !void {
            self.set = .init(self.arena.allocator());

            var buf: [1024 * 64]u8 = undefined;
            var reader = self.file.reader(self.io, &buf);
            var r = &reader.interface;
            var hash_buf: [32]u8 = undefined;
            while (true) {
                r.readSliceAll(&hash_buf) catch break;
                const count = try r.takeInt(u32, .little);
                const time = try r.takeInt(u32, .little);
                const path_ = try r.takeDelimiter('\n');
                if (path_ == null) return error.BadFile;

                const result = try self.set.getOrPut(hash_buf);
                if (result.found_existing) continue;
                result.value_ptr.* = .{ .path = try self.arena.allocator().dupe(u8, path_.?), .play_count = count, .play_time = time };
            }
        }
        fn write(self: *@This()) !void {
            var buf: [1024 * 4]u8 = undefined;
            var writer = self.file.writer(self.io, &buf);
            const w = &writer.interface;
            var it = self.set.iterator();
            while (it.next()) |e| {
                try w.writeAll(e.key_ptr);
                try w.writeInt(u32, e.value_ptr.play_count, .little);
                try w.writeInt(u32, e.value_ptr.play_time, .little);
                try w.writeAll(e.value_ptr.path);
                try w.writeByte('\n');
            }
            try writer.end();
        }
        fn print(self: *@This()) void {
            var it = self.set.iterator();
            while (it.next()) |e| {
                std.debug.print("{x}: {s}\n", .{ e.key_ptr.*, Io.Dir.path.basename(e.value_ptr.path) });
            }
        }
        fn printStats(self: *@This()) void {
            var it = self.set.iterator();
            while (it.next()) |e| {
                std.debug.print("Count: {d: >4}, Time: {d: >4} | {s}\n", .{ e.value_ptr.play_count, e.value_ptr.play_time, Io.Dir.path.basename(e.value_ptr.path) });
            }
        }
        fn printStatsNow(io: Io) !void {
            var table = MusicTable.init(io);
            defer table.deinit();
            try table.start();
            table.printStats();
        }
        fn getFile(io: Io) Io.File {
            return getOrCreateFile(io, "music_table.txt") catch unreachable;
        }
        fn clearFile(io: Io) !void {
            const file = getFile(io);
            var w = file.writer(io, &.{});
            try w.end();
            file.close(io);
        }
    };
    const Changes = struct {
        set: SetType,
        arena: std.heap.ArenaAllocator,
        io: Io,
        file: Io.File,

        const SetType = std.AutoHashMap([32]u8, Change);
        const Change = enum(u8) {
            Delete,
            Remove,
            Rename,
        };
        fn init(io: Io) @This() {
            return .{
                .set = undefined,
                .arena = .init(std.heap.page_allocator),
                .io = io,
                .file = getFile(io),
            };
        }
        fn deinit(self: *@This()) void {
            self.set.deinit();
            self.arena.deinit();
        }
        fn start(self: *@This()) !void {
            self.set = .init(self.arena.allocator());

            var buf: [1024 * 64]u8 = undefined;
            var reader = self.file.reader(self.io, &buf);
            var r = &reader.interface;
            var hash_buf: [32]u8 = undefined;
            while (true) {
                const byte = r.takeInt(u8, .little) catch break;
                try r.readSliceAll(&hash_buf);

                const result = try self.set.getOrPut(hash_buf);
                if (result.found_existing) continue;
                result.value_ptr.* = @fromBackingInt(byte);
            }
        }
        fn write(self: *@This()) !void {
            var buf: [1024 * 4]u8 = undefined;
            var writer = self.file.writer(self.io, &buf);
            const w = &writer.interface;
            var it = self.set.iterator();
            while (it.next()) |e| {
                try w.writeInt(u8, @backingInt(e.value_ptr.*), .little);
                try w.writeAll(e.key_ptr);
            }
            try writer.end();
        }
        fn print(self: *@This()) void {
            var it = self.set.iterator();
            while (it.next()) |e| {
                std.debug.print("{any}: {x}\n", .{ @fromBackingInt(e.value_ptr.*), e.key_ptr });
            }
        }
        fn getFile(io: Io) Io.File {
            return getOrCreateFile(io, "changes.txt") catch unreachable;
        }
        fn clearFile(io: Io) !void {
            const file = getFile(io);
            var w = file.writer(io, &.{});
            try w.end();
            file.close(io);
        }
    };
    fn getAppDir(io: Io) !Io.Dir {
        const cwd = std.Io.Dir.cwd();
        return cwd.openDir(io, app_path, .{}) catch try cwd.createDirPathOpen(io, app_path, .{});
    }
    fn getOrCreateFile(io: Io, name: []const u8) !Io.File {
        var dir = try getAppDir(io);
        defer dir.close(io);
        return dir.openFile(io, name, .{ .mode = .read_write }) catch try dir.createFile(io, name, .{ .read = true });
    }
    const Add = struct {
        var group: std.Io.Group = .init;
        var lock: std.Io.Mutex = .init;

        fn add(io: std.Io, path: []const u8) !void {
            var table = MusicTable.init(io);
            defer table.deinit();
            try table.start();

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
                    try addRecurse(io, dir, &table);
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
                    try addFile(io, file, &table);
                },
            }

            try group.await(io);
            try table.write();
        }
        fn addAddPath(io: Io, path: []const u8) !void {
            try add(io, path);
            try Paths.add(io, path);
        }
        fn addRecurse(io: std.Io, dir: std.Io.Dir, table: *MusicTable) !void {
            var it = dir.iterate();
            while (it.next(io)) |e| {
                if (e == null) break;
                switch (e.?.kind) {
                    .file => {
                        if (!isSong(e.?.name)) continue;
                        const file = try dir.openFile(io, e.?.name, .{});
                        try addFile(io, file, table);
                    },
                    .directory => {
                        std.debug.print("scanning: {s}\n", .{e.?.name});
                        var dir1 = try dir.openDir(io, e.?.name, .{ .iterate = true });
                        defer dir1.close(io);
                        try addRecurse(io, dir1, table);
                    },
                    else => {},
                }
            } else |_| {}
        }
        fn addFile(io: std.Io, file: std.Io.File, table: *MusicTable) !void {
            try group.concurrent(io, addFileThreadWrapper, .{ io, file, table });
        }
        fn addFileThreadWrapper(io: std.Io, file: std.Io.File, table: *MusicTable) void {
            addFileThread(io, file, table) catch {
                std.debug.print("Error hashing file\n", .{});
                return;
            };
        }
        fn addFileThread(io: std.Io, file: std.Io.File, table: *MusicTable) !void {
            var buf: [256]u8 = undefined;
            const len = try file.realPath(io, &buf);
            const path = buf[0..len];

            const hash = try hashFile(io, file);
            file.close(io);

            try lock.lock(io);
            const result = try table.set.getOrPut(hash);
            if (result.found_existing) {
                std.debug.print("\x1B[31mAlready In Table: {s}\x1B[0m\n", .{std.Io.Dir.path.basename(path)});
            } else {
                std.debug.print("\x1B[32mAdded: {s}\x1B[0m\n", .{std.Io.Dir.path.basename(path)});
                result.value_ptr.play_count = 0;
                result.value_ptr.play_time = 0;
                result.value_ptr.path = try table.arena.allocator().dupe(u8, path);
            }
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
    const Delete_Remove = struct {
        // add delete to changes
        // when syncing if the hash is recieved from other client then say song is had to not request it
        // after sending all songs send the command to delete the hash
        fn delete(io: Io, path: []const u8) !void {
            try delete_remove(io, path, .Delete);
        }
        fn remove(io: Io, path: []const u8) !void {
            try delete_remove(io, path, .Remove);
        }
        fn delete_remove(io: Io, path: []const u8, change: Changes.Change) !void {
            // CHECKS
            {
                if (!Io.Dir.path.isAbsolute(path)) {
                    std.debug.print("Path is not absolute\n", .{});
                    return;
                }
                const stat = try Io.Dir.cwd().statFile(io, path, .{});
                if (stat.kind != .file) {
                    std.debug.print("Path is not a file\n", .{});
                    return;
                }
                if (change != .Delete and change != .Remove) return;
            }
            var changes = Changes.init(io);
            defer changes.deinit();
            try changes.start();
            var table = MusicTable.init(io);
            defer table.deinit();
            try table.start();

            const hash: [32]u8 = blk: {
                var file = try Io.Dir.openFileAbsolute(io, path, .{});
                defer file.close(io);
                break :blk try Add.hashFile(io, file);
            };
            const r1 = try changes.set.getOrPut(hash);
            if (r1.found_existing) {
                //FIXME
                std.debug.print("Only one action allowed per song right now\n", .{});
                return;
            } else {
                r1.value_ptr.* = change;
            }
            const r2 = table.set.remove(hash);
            if (!r2) {
                std.debug.print("Song not found in table\n", .{});
                return;
            }
            switch (change) {
                .Delete => {
                    try Io.Dir.deleteFileAbsolute(io, path);
                },
                .Remove => {
                    var dir = try getRemoveDir(io);
                    defer dir.close(io);
                    const basename = Io.Dir.path.basename(path);
                    const old_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(path).?, .{});

                    try Io.Dir.rename(old_dir, basename, dir, basename, io);
                },
                else => {
                    std.debug.print("Not implemented\n", .{});
                    return;
                },
            }

            try changes.write();
            try table.write();
        }
        fn getRemoveDir(io: Io) !Io.Dir {
            var dir = try getAppDir(io);
            defer dir.close(io);
            return dir.openDir(io, "removed", .{}) catch try dir.createDirPathOpen(io, "removed", .{});
        }
    };
    const Rename = struct {
        fn rename(io: Io, old: []const u8, new: []const u8) !void {
            // CHECKS
            {
                if (!Io.Dir.path.isAbsolute(old)) {
                    std.debug.print("Path is not absolute\n", .{});
                    return;
                }
                const stat = try Io.Dir.cwd().statFile(io, old, .{});
                if (stat.kind != .file) {
                    std.debug.print("Path is not a file\n", .{});
                    return;
                }
            }
            var changes = Changes.init(io);
            defer changes.deinit();
            try changes.start();
            var table = MusicTable.init(io);
            defer table.deinit();
            try table.start();

            const hash: [32]u8 = blk: {
                var file = try Io.Dir.openFileAbsolute(io, old, .{});
                defer file.close(io);
                break :blk try Add.hashFile(io, file);
            };
            const r1 = try changes.set.getOrPut(hash);
            if (r1.found_existing) {
                //FIXME
                std.debug.print("Only one action allowed per song right now\n", .{});
                return;
            } else {
                r1.value_ptr.* = .Rename;
            }
            const r2 = table.set.getPtr(hash);
            if (r2 == null) {
                std.debug.print("Song not found in table\n", .{});
                return;
            }
            const new_path = try Io.Dir.path.join(table.arena.allocator(), &.{ Io.Dir.path.dirname(old).?, new });
            r2.?.*.path = new_path;

            const old_name = Io.Dir.path.basename(old);
            const old_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(old).?, .{});

            try Io.Dir.rename(old_dir, old_name, old_dir, new, io);

            try changes.write();
            try table.write();
        }
    };
    const Stat = struct {
        const Which = enum(u1) {
            Time,
            Count,
        };
        fn update(io: Io, path: []const u8, which_: []const u8, amount_: []const u8) !void {
            try base(io, path, which_, amount_, false);
        }
        fn set(io: Io, path: []const u8, which_: []const u8, amount_: []const u8) !void {
            try base(io, path, which_, amount_, true);
        }
        fn base(io: Io, path: []const u8, which_: []const u8, amount_: []const u8, idk: bool) !void {
            // CHECKS
            {
                if (!Io.Dir.path.isAbsolute(path)) {
                    std.debug.print("Path is not absolute\n", .{});
                    return;
                }
                const stat = try Io.Dir.cwd().statFile(io, path, .{});
                if (stat.kind != .file) {
                    std.debug.print("Path is not a file\n", .{});
                    return;
                }
            }
            var table = MusicTable.init(io);
            defer table.deinit();
            try table.start();

            const hash: [32]u8 = blk: {
                var file = try Io.Dir.openFileAbsolute(io, path, .{});
                defer file.close(io);
                break :blk try Add.hashFile(io, file);
            };

            const r1 = table.set.getPtr(hash);
            if (r1 == null) {
                std.debug.print("Song not found\n", .{});
                return;
            }
            const which = if (eql(which_, "time")) Which.Time else if (eql(which_, "count")) Which.Count else {
                std.debug.print("Invalid command \'{s}\'\n", .{which_});
                return;
            };
            const amount = std.fmt.parseInt(u32, amount_, 10) catch {
                std.debug.print("Invalid value \'{s}\'\n", .{amount_});
                return;
            };
            if (idk) {
                //set
                switch (which) {
                    .Count => r1.?.*.play_count = amount,
                    .Time => r1.?.*.play_time = amount,
                }
            } else {
                //update
                switch (which) {
                    .Count => r1.?.*.play_count += amount,
                    .Time => r1.?.*.play_time += amount,
                }
            }
            try table.write();
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

            var music_dir = try getMusicDir(io);
            defer music_dir.close(io);
            var buf: [1024]u8 = undefined;
            const len = try music_dir.realPath(io, &buf);
            try Add.add(io, buf[0..len]);

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
            var table = FileManager.MusicTable.init(io);
            defer table.deinit();
            try table.start();

            var music_dir = try FileManager.getMusicDir(io);
            defer music_dir.close(io);
            const s = Io.Timestamp.now(io, .awake);
            var total: usize = 0;
            var group = std.Io.Group.init;

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
                try group.concurrent(io, FileManager.Add.addFileThreadWrapper, .{ io, file, &table });

                std.debug.print("\x1B[2F\x1B[2KRecieved: {d} bytes: {s}\n", .{ f_len, basename });
                const elapsed_ns: u64 = @intCast(s.untilNow(io, .awake).toNanoseconds());
                const secs = @as(f64, @floatFromInt(@max(elapsed_ns, 1))) / 1e9;
                const bps = @as(f64, @floatFromInt(total)) / secs;
                std.debug.print("\x1B[2KSpeed {d:.2}MB/S\n", .{bps / 1000000});
            }
            try group.await(io);
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
                try FileManager.MusicTable.clearFile(io);
            } else if (eql("sync_new_key", args[0])) {
                try FileManager.Key.saveKey(io, &FileManager.Key.generateNewKey(io));
            } else if (eql("resetpaths", args[0])) {
                try FileManager.Paths.clearPathsFile(io);
            } else if (eql("rescan", args[0])) {
                try FileManager.Rescan.rescan(io);
            } else if (eql("resetchanges", args[0])) {
                try FileManager.Changes.clearFile(io);
            } else if (eql("printstats", args[0])) {
                try FileManager.MusicTable.printStatsNow(io);
            }
        },
        2 => {
            if (eql("sync", args[0])) {
                try FileManager.Key.saveKey(io, args[1]);
                try Client.client(io, args[1]);
            } else if (eql("add", args[0])) {
                try FileManager.Add.addAddPath(io, args[1]);
            } else if (eql("delete", args[0])) {
                try FileManager.Delete_Remove.delete(io, args[1]);
            } else if (eql("remove", args[0])) {
                try FileManager.Delete_Remove.remove(io, args[1]);
            }
        },
        3 => {
            if (eql("rename", args[0])) {
                try FileManager.Rename.rename(io, args[1], args[2]);
            }
        },
        4 => {
            if (eql("stat", args[0])) {
                try FileManager.Stat.update(io, args[1], args[2], args[3]);
            }
        },
        5 => {
            if (eql("stat", args[0])) {
                if (!eql("set", args[2])) {
                    std.debug.print("Invalid args\n", .{});
                    return;
                }
                try FileManager.Stat.set(io, args[1], args[3], args[4]);
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
