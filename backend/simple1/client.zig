const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const net = Io.net;

//TODO make music table take less space by shortening paths
//TODO use the default music dirs of respective os windows - /users/$USER/Music android - /Music?
//TODO commit stats
//TODO unremove songs
//TODO remove all uses of realPath
//TODO if file from path from musictable doesnt exist remove it from musictable - move stats to other temperary place
const CHAT_MODE = false;

const app_path = "testing2/app";
const song_extensions = [_][]const u8{ ".mp3", ".opus", ".flac", ".m4a" };

const Songs_R = std.ArrayList(*const FileManager.MusicTable.MusicEntry);

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
            var sync: Syncing = .{ .gpa = gpa, .songs = FileManager.MusicTable.init(io) };
            try sync.songs.start();
            defer sync.songs.deinit();
            try clients.concurrent(io, Syncing.recieveWrap, .{ &sync, io, r });
            try sync.sending(io, w, stream);
            try clients.await(io);
            try sync.songs.write();
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
        // index -> client id
        header: [16]?u32 = @splat(null),

        const SetType = std.AutoHashMap([32]u8, MusicEntry);
        const MusicEntry = struct {
            path: []const u8,
            this_play_count: u32,
            this_play_time: u32,
            play_count: [16]?u32,
            play_time: [16]?u32,
            // 0b1 represents its in removed folder
            flags: u8,
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
            // reading header
            var idx: usize = 0;
            {
                while (true) {
                    const byte = r.peekByte() catch break;
                    if (byte == '\n') {
                        r.toss(1);
                        break;
                    }
                    self.header[idx] = try r.takeInt(u32, .little);
                    idx += 1;
                }
            }
            while (true) {
                r.readSliceAll(&hash_buf) catch break;
                const flags = try r.takeByte();
                const this_count = try r.takeInt(u32, .little);
                const this_time = try r.takeInt(u32, .little);
                var count: [16]?u32 = @splat(null);
                var time: [16]?u32 = @splat(null);
                for (0..idx) |x| {
                    count[x] = try r.takeInt(u32, .little);
                    time[x] = try r.takeInt(u32, .little);
                }
                const path_ = try r.takeDelimiter('\n');
                if (path_ == null) return error.BadFile;

                const result = try self.set.getOrPut(hash_buf);
                if (result.found_existing) continue;
                result.value_ptr.* = .{ .path = try self.arena.allocator().dupe(u8, path_.?), .play_count = count, .play_time = time, .flags = flags, .this_play_count = this_count, .this_play_time = this_time };
            }
        }
        /// allocates path to table
        fn addEntry(self: *@This(), key: [32]u8, path: []const u8) !void {
            const e = try self.set.getOrPut(key);
            if (e.found_existing) {
                std.debug.print("\x1B[31mAlready In Table: {s}\x1B[0m\n", .{std.Io.Dir.path.basename(path)});
            } else {
                std.debug.print("\x1B[32mAdded: {s}\x1B[0m\n", .{std.Io.Dir.path.basename(path)});
                e.value_ptr.* = .{ .flags = 0, .play_count = @splat(null), .play_time = @splat(null), .this_play_count = 0, .this_play_time = 0, .path = try self.arena.allocator().dupe(u8, path) };
            }
        }
        fn write(self: *@This()) !void {
            var buf: [1024 * 4]u8 = undefined;
            var writer = self.file.writer(self.io, &buf);
            const w = &writer.interface;
            {
                for (self.header) |x| {
                    if (x == null) break;
                    try w.writeInt(u32, x.?, .little);
                }
                try w.writeByte('\n');
            }
            var it = self.set.iterator();
            while (it.next()) |e| {
                try w.writeAll(e.key_ptr);
                try w.writeByte(e.value_ptr.flags);
                try w.writeInt(u32, e.value_ptr.this_play_count, .little);
                try w.writeInt(u32, e.value_ptr.this_play_time, .little);
                for (self.header, e.value_ptr.play_count, e.value_ptr.play_time) |i, x, y| {
                    if (i == null) break;
                    if (x == null or y == null) {
                        try w.writeInt(u32, 0, .little);
                        try w.writeInt(u32, 0, .little);
                    } else {
                        try w.writeInt(u32, x.?, .little);
                        try w.writeInt(u32, y.?, .little);
                    }
                }
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
                const m = e.value_ptr;
                const flags = if (m.flags & 0b1 == 1) "Removed" else "";
                std.debug.print("Count: {d: >4}, Time: {d: >4} ", .{ m.this_play_count, m.this_play_time });
                for (m.play_count, m.play_time, 0..) |x, y, i| {
                    if (x == null or y == null) break;
                    std.debug.print("Client: {d}- Count: {d: >4}, Time: {d: >4} ", .{ self.header[i].?, x.?, y.? });
                }
                std.debug.print("| {s} {s}\n", .{ Io.Dir.path.basename(m.path), flags });
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
    const ClientId = struct {
        fn getId(io: Io) u32 {
            var file = getFile(io);
            defer file.close(io);

            var buf: [4]u8 = undefined;
            var reader = file.reader(io, &buf);
            var r = &reader.interface;

            return r.takeInt(u32, .little) catch 0;
        }
        fn writeId(io: Io, id: u32) !void {
            var file = getFile(io);
            defer file.close(io);

            var buf: [4]u8 = undefined;
            var writer = file.writer(io, &buf);
            var w = &writer.interface;

            try w.writeInt(u32, id, .little);
            try w.flush();
        }
        fn getFile(io: Io) Io.File {
            return getOrCreateFile(io, "client_id.txt") catch unreachable;
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
        fn printChangesNow(io: Io) !void {
            var changes = Changes.init(io);
            defer changes.deinit();
            try changes.start();
            var it = changes.set.iterator();
            while (it.next()) |e| {
                std.debug.print("{any}: {x}\n", .{ e.value_ptr, e.key_ptr });
            }
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
            const stat = Io.Dir.statFile(Io.Dir.cwd(), io, path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.print("File from path not found\n", .{});
                    return;
                },
                else => return err,
            };

            switch (stat.kind) {
                .directory => {
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
                .file => {
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
                else => {},
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
            try table.addEntry(hash, path);
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
                const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        std.debug.print("File from path not found", .{});
                        return;
                    },
                    else => return err,
                };
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
            const r2 = table.set.getPtr(hash);
            if (r2 == null) {
                std.debug.print("Song not found in table\n", .{});
                return;
            }
            switch (change) {
                .Delete => {
                    try Io.Dir.deleteFileAbsolute(io, path);
                    _ = table.set.remove(hash);
                },
                .Remove => {
                    var dir = try getRemoveDir(io);
                    defer dir.close(io);
                    const basename = Io.Dir.path.basename(path);
                    const old_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(path).?, .{});
                    defer old_dir.close(io);

                    try Io.Dir.rename(old_dir, basename, dir, basename, io);
                    r2.?.flags |= 0b1;
                    r2.?.path = try dir.realPathFileAlloc(io, basename, table.arena.allocator());
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
                const stat = Io.Dir.cwd().statFile(io, old, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        std.debug.print("File from path not found", .{});
                        return;
                    },
                    else => return err,
                };
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
                const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        std.debug.print("File from path not found", .{});
                        return;
                    },
                    else => return err,
                };
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
                std.debug.print("Song not found in table\n", .{});
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
                    .Count => r1.?.*.this_play_count = amount,
                    .Time => r1.?.*.this_play_time = amount,
                }
            } else {
                //update
                switch (which) {
                    .Count => r1.?.*.this_play_count += amount,
                    .Time => r1.?.*.this_play_time += amount,
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
    o_data: o_Data = .{},
    o_changes: o_Changes = .{},
    songs: FileManager.MusicTable, 
    done_sending: Io.Event = .unset,
    start_sending: std.Io.Event = .unset,
    gpa: std.heap.ArenaAllocator,
    id: u32 = 0,

    fn sending(self: *@This(), io: Io, w: *Io.Writer, stream: net.Stream) !void {
        std.debug.print("Loaded {d} songs\n", .{self.songs.set.count()});

        var changes = FileManager.Changes.init(io);
        defer changes.deinit();
        try changes.start();

        // SEND INITAL MESSAGE (client id)
        {
            const id = FileManager.ClientId.getId(io);
            self.id = id;
            try w.writeInt(u32, id, .little);
            try w.flush();
        }

        // WAIT FOR OTHER CLIENT
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
        }

        // SEND CHANGES
        {
            try w.writeInt(u32, @intCast(changes.set.count()), .little);
            var it = changes.set.iterator();
            var count: usize = 0;
            var len: usize = 0;
            while (it.next()) |h| {
                try w.writeByte(@backingInt(h.value_ptr.*));
                try w.writeAll(h.key_ptr);
                if (h.value_ptr.* == .Rename) {
                    const song = self.songs.set.get(h.key_ptr.*);
                    if (song == null) {
                        std.debug.print("HOW???\n", .{});
                        unreachable;
                    }
                    const name = Io.Dir.path.basename(song.?.path);
                    len += name.len;
                    count += 1;
                }
            }
            try w.writeInt(u32, @intCast(len + count * 4), .little);
            it = changes.set.iterator();
            while (it.next()) |h| {
                if (h.value_ptr.* == .Rename) {
                    const song = self.songs.set.get(h.key_ptr.*);
                    if (song == null) continue;
                    const name = Io.Dir.path.basename(song.?.path);
                    try w.writeInt(u32, @intCast(name.len), .little);
                    try w.writeAll(name);
                }
            }
            try w.flush();
        }

        // RESOLVE CHANGES
        {
            try self.o_changes.initialized.wait(io);
            for (0..self.o_changes.len()) |i| {
                const e = self.o_changes.get(i).?;
                std.debug.print("Got change: {any} {x}\n", .{ e.change, e.hash });
            }
            var rename_count: usize = 0;
            for (0..self.o_changes.len()) |i| {
                const o_e = self.o_changes.get(i).?;
                const e = changes.set.get(o_e.hash[0..32].*);
                const new = if (o_e.change == .Rename) blk: {
                    rename_count += 1;
                    break :blk self.o_changes.getAux(rename_count - 1).?;
                } else undefined;
                switch (o_e.change) {
                    .Delete => if (e) |n| switch (n) {
                        .Delete => {},
                        .Remove, .Rename => {
                            const song = self.songs.set.fetchRemove(o_e.hash[0..32].*);
                            if (song == null) continue;
                            try Io.Dir.deleteFileAbsolute(io, song.?.value.path);
                        },
                    } else {
                        const song = self.songs.set.fetchRemove(o_e.hash[0..32].*);
                        if (song == null) {
                            std.debug.print("Song not found to delete\n", .{});
                            continue;
                        }
                        try Io.Dir.deleteFileAbsolute(io, song.?.value.path);
                    },
                    .Remove => if (e) |n| switch (n) {
                        .Delete, .Remove => {},
                        .Rename => {
                            const song = self.songs.set.getPtr(o_e.hash[0..32].*);
                            if (song == null) continue;
                            var dir = try FileManager.Delete_Remove.getRemoveDir(io);
                            defer dir.close(io);
                            const basename = Io.Dir.path.basename(song.?.path);
                            const old_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(song.?.path).?, .{});
                            defer old_dir.close(io);

                            try Io.Dir.rename(old_dir, basename, dir, basename, io);
                            song.?.flags |= 0b1;
                            song.?.path = try dir.realPathFileAlloc(io, basename, self.songs.arena.allocator());
                        },
                    } else {
                        const song = self.songs.set.getPtr(o_e.hash[0..32].*);
                        if (song == null) continue;
                        var dir = try FileManager.Delete_Remove.getRemoveDir(io);
                        defer dir.close(io);
                        const basename = Io.Dir.path.basename(song.?.path);
                        const old_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(song.?.path).?, .{});
                        defer old_dir.close(io);

                        try Io.Dir.rename(old_dir, basename, dir, basename, io);
                        song.?.flags |= 0b1;
                        song.?.path = try dir.realPathFileAlloc(io, basename, self.songs.arena.allocator());
                    },
                    .Rename => if (e) |n| switch (n) {
                        .Delete => {},
                        .Remove => {
                            const song = self.songs.set.getPtr(o_e.hash[0..32].*);
                            if (song == null) continue;
                            const old = song.?.path;
                            const new_path = try Io.Dir.path.join(self.songs.arena.allocator(), &.{ Io.Dir.path.dirname(old).?, new });
                            song.?.path = new_path;

                            const old_name = Io.Dir.path.basename(old);
                            const old_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(old).?, .{});
                            defer old_dir.close(io);

                            try Io.Dir.rename(old_dir, old_name, old_dir, new, io);
                        },
                        .Rename => {
                            std.debug.print("RESOLVE WHICH RENAME WINS\n", .{});
                        },
                    } else {
                        const song = self.songs.set.getPtr(o_e.hash[0..32].*);
                        if (song == null) continue;
                        const old = song.?.path;
                        const new_path = try Io.Dir.path.join(self.songs.arena.allocator(), &.{ Io.Dir.path.dirname(old).?, new });
                        song.?.path = new_path;

                        const old_name = Io.Dir.path.basename(old);
                        const old_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(old).?, .{});
                        defer old_dir.close(io);

                        try Io.Dir.rename(old_dir, old_name, old_dir, new, io);
                    },
                }
            }
        }

        // SEND HASHES
        {
            std.debug.print("Sending Hashes\n", .{});

            try w.writeInt(u32, self.id, .little);
            try w.writeInt(u32, @intCast(self.songs.set.count()), .little);
            var it = self.songs.set.iterator();
            while (it.next()) |song| {
                try w.writeAll(song.key_ptr);
                try w.writeInt(u32, song.value_ptr.this_play_count, .little);
                try w.writeInt(u32, song.value_ptr.this_play_time, .little);
            }
            try w.flush();
        }

        var d_songs: Songs_R = try .initCapacity(self.gpa.allocator(), 8);
        // FIND DIFFERING HASHES
        {
            try self.o_data.initialized.wait(io);
            std.debug.print("Hashes Recieved: {d}\n", .{self.o_data.len()});
            var it = self.songs.set.iterator();
            while (it.next()) |*song| {
                for (0..self.o_data.len()) |i| {
                    if (std.mem.eql(u8, song.key_ptr, self.o_data.get(i).?.hash)) break;
                } else {
                    try d_songs.append(self.gpa.allocator(), song.value_ptr);
                }
            }
        }

        // SEND DIFFERING SONGS
        {
            for (d_songs.items) |song| {
                if ((song.flags & 0b1) == 1) continue;
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
        self.done_sending.set(io);
        try FileManager.Changes.clearFile(io);
    }
    fn recieveWrap(self: *@This(), io: Io, r: *Io.Reader) void {
        self.recieving(io, r) catch |err| {
            std.debug.print("Error recieving: {any}\n", .{err});
        };
    }
    fn recieving(self: *@This(), io: Io, r: *Io.Reader) !void {
        //CLIENT ID
        {
            const id = try r.takeInt(u32, .little);
            if (id != 0) {
                try FileManager.ClientId.writeId(io, id);
                self.id = id;
            }
        }

        // WAIT FOR OTHER CLIENT
        {
            _ = try r.takeByte();
            self.start_sending.set(io);
        }

        // GET CHANGES
        {
            const n = try r.takeInt(u32, .little);
            const buf = try r.readAlloc(self.gpa.allocator(), n * 33);

            const len = try r.takeInt(u32, .little);
            const aux_buf = try r.readAlloc(self.gpa.allocator(), len);
            self.o_changes.buf = buf;
            self.o_changes.aux_buf = aux_buf;
            // for (0..self.o_changes.len()) |i| {
            //     const e = self.o_changes.get(i).?;
            //     std.debug.print("{any}: {x}\n", .{ e.change, e.hash });
            // }
            // for (0..100) |i| {
            //     const e = self.o_changes.getAux(i);
            //     if (e == null) break;
            //     std.debug.print("aux: {s}\n", .{e.?});
            // }
            self.o_changes.initialized.set(io);
        }

        // GET OTHER CLIENTS HASHES
        {
            const o_id = try r.takeInt(u32, .little);
            const n = try r.takeInt(u32, .little);
            const buf = try r.readAlloc(self.gpa.allocator(), n * 40);
            self.o_data.buf = buf;
            self.o_data.o_id = o_id;
            // for (0..self.o_hashes.data.len()) |i| {
            //     const e = self.o_hashes.data.get(i).?;
            //     std.debug.print("hashes: {x}\n", .{ e });
            // }
            
            self.o_data.initialized.set(io);
        }

        // RECIEVE SONGS
        {
            var music_dir = try FileManager.getMusicDir(io);
            defer music_dir.close(io);
            var path_buf: [1024]u8 = undefined;
            const music_dir_path = try music_dir.realPath(io, &path_buf);
            path_buf[music_dir_path] = Io.Dir.path.sep;

            const s = Io.Timestamp.now(io, .awake);
            var total: usize = 0;

            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();
            var alloc = gpa.allocator();
            const Entry = struct {
                hash: [32]u8,
                basename: []const u8,
            };
            var list: std.ArrayList(Entry) = .empty;
            defer list.deinit(alloc);

            std.debug.print("\n\n\n", .{});
            while (true) {
                const b_len = r.takeInt(u64, .little) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };
                const basename = path_buf[music_dir_path + 1 ..][0..@intCast(b_len)];
                try r.readSliceAll(basename);

                const f_len = try r.takeInt(u64, .little);

                var file = try music_dir.createFile(io, basename, .{ .read = true });
                defer file.close(io);
                var writer = file.writer(io, &.{});
                const w = &writer.interface;
                {
                    var hash: [32]u8 = undefined;
                    var b = std.crypto.hash.Blake3.init(.{});
                    var remaining: usize = f_len;

                    while (remaining > 0) {
                        const n: usize = @intCast(@min(r.buffer.len, remaining));
                        const chunk = try r.take(n);
                        b.update(chunk);
                        try w.writeAll(chunk);
                        remaining -= n;
                    }
                    b.final(&hash);
                    try list.append(alloc, .{.hash = hash, .basename = try alloc.dupe(u8, basename)});
                    total += f_len;
                    try writer.end();
                }

                std.debug.print("\x1B[2F\x1B[2KRecieved: {d} bytes: {s}\n", .{ f_len, basename });
                const elapsed_ns: u64 = @intCast(s.untilNow(io, .awake).toNanoseconds());
                const secs = @as(f64, @floatFromInt(@max(elapsed_ns, 1))) / 1e9;
                const bps = @as(f64, @floatFromInt(total)) / secs;
                std.debug.print("\x1B[2KSpeed {d:.2}MB/S\n", .{bps / 1000000});
            }
            try self.done_sending.wait(io);
            for (list.items) |i| {
                @memcpy(path_buf[music_dir_path+1..music_dir_path+1+i.basename.len], i.basename);
                try self.songs.addEntry(i.hash, path_buf[0..music_dir_path+i.basename.len+1]);
            }
            std.debug.print("Time took: {d:.1} seconds\n", .{@as(f64, @floatFromInt(s.untilNow(io, .awake).toMilliseconds())) / 1000});
        }
        
        // IMPORT STATS FROM OTHER CLIENT
        {
            const idx = for (self.songs.header, 0..) |x, i| {
                if (x == null) {
                    self.songs.header[i] = self.o_data.o_id;
                    break i;
                }
                if (self.o_data.o_id == x.?) break i;
            } else return;
            for (0..self.o_data.len()) |i| {
                const d = self.o_data.get(i);
                if (d == null) break;
                const re = self.songs.set.getPtr(d.?.hash[0..32].*);
                if (re == null) continue;
                re.?.*.play_count[idx] = d.?.count;
                re.?.*.play_time[idx] = d.?.time;
            }
        }
    }
    const o_Changes = struct {
        buf: []const u8 = undefined,
        aux_buf: []const u8 = undefined,
        initialized: Io.Event = .unset,
        const Entry = struct {
            hash: []const u8,
            change: FileManager.Changes.Change,
        };
        fn init(buf: []const u8) @This() {
            return .{
                .buf = buf,
            };
        }
        /// null is returned if idx is out of bounds
        fn get(self: *@This(), idx: usize) ?Entry {
            const i: usize = idx * 33;
            if (self.buf.len < i + 33) return null;
            return .{
                .change = @fromBackingInt(self.buf[i]),
                .hash = self.buf[i + 1 .. i + 33],
            };
        }
        fn len(self: *@This()) usize {
            return self.buf.len / 33;
        }
        /// null is returned if idx not found
        fn getAux(self: *@This(), idx: usize) ?[]const u8 {
            var r = Io.Reader.fixed(self.aux_buf);
            for (0..idx) |_| {
                const a_len = r.takeInt(u32, .little) catch return null;
                _ = r.take(a_len) catch return null;
            }
            const a_len = r.takeInt(u32, .little) catch return null;
            return r.peek(a_len) catch return null;
        }
    };
    const o_Data = struct {
        buf: []const u8 = undefined,
        initialized: Io.Event = .unset,
        o_id: u32 = undefined,
        const Entry = struct {
            hash: []const u8,
            count: u32,
            time: u32,
        };
        /// null is returned if idx is out of bounds
        fn get(self: *@This(), idx: usize) ?Entry {
            const i: usize = idx * 40;
            if (self.buf.len < i + 40) return null;
            return .{
                .hash = self.buf[i .. i + 32],
                .count = std.mem.readInt(u32, self.buf[i + 32 .. i + 36][0..4], .little),
                .time = std.mem.readInt(u32, self.buf[i + 36 .. i + 40][0..4], .little),
            };
        }
        fn len(self: *@This()) usize {
            return self.buf.len / 40;
        }
    };
};

pub fn main(init: std.process.Init) !void {
    if (builtin.target.os.tag == .windows) {
        var thread = try std.process.spawn(init.io, .{ .argv = &.{ "chcp", "65001" }, .stdout = .ignore });
        _ = try thread.wait(init.io);
    }
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    printio = init.io;
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
            } else if (eql("printchanges", args[0])) {
                try FileManager.Changes.printChangesNow(io);
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
            } else if (eql("update", args[0])) {
                if (eql("backend", args[1])) {
                    try FileManager.MusicTable.clearFile(io);
                    try FileManager.Rescan.rescan(io);
                }
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
var printlock: Io.Mutex = .init;
var printio: Io = undefined;
fn print(comptime fmt: []const u8, args: anytype) void {
    printlock.lockUncancelable(printio);
    std.debug.print(fmt, args);
    printlock.unlock(printio);
}