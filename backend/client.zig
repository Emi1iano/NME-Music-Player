const std = @import("std");
const net = std.Io.net;
const builtin = @import("builtin");
const ClientCode = @import("server.zig").Networks.ClientCode;
const Io = std.Io;

const TESTING_RELAY: bool = false;
const TESTING: bool = true;
const CHAT_MODE: bool = false;

var clientState: Networks.ClientState = undefined;
const song_extensions = [_][]const u8{ ".mp3", ".opus", ".flac" };
const app_directory: []const u8 = "app/";

const Networks = struct {
    const ClientState = struct {
        client_socket: net.Socket = undefined,
        server_ip: net.IpAddress = undefined,
        resolved_ip: net.IpAddress = undefined,
        reciever_public_ip: ?net.IpAddress = null,
        reciever_local_ip: ?net.IpAddress = null,
        key: [8]u8 = undefined,
        lock: std.Io.Mutex = .init,
        cliendMode: ClientMode = ClientMode.P2P,
        recieved_inital_info: bool = false,
        should_disconnect: bool = false,

        const ClientMode = enum(u8) {
            P2P,
            Relay,
        };

        fn init(io: Io) ClientState {
            return .{
                .client_socket = getClientSocket(io) catch unreachable,
                .server_ip = getServerIp() catch unreachable,
                .key = NewFileManager.KeyStuff.getKey(io) catch unreachable,
            };
        }
        fn deinit(self: *ClientState, io: Io) void {
            self.client_socket.close(io);
        }
        fn sendResolvedWithCode(self: *ClientState, io: Io, cliendCode: ClientCode, comptime message: []const u8) !void {
            try self.client_socket.socket.send(io, &clientState.resolved_ip, ClientCode.getByte(cliendCode) ++ message);
        }
        fn sendResolved(self: *ClientState, io: Io, data: []const u8) !void {
            try self.client_socket.send(io, &clientState.resolved_ip, data);
            //testPrint("using {any}\n", .{clientState.resolved_ip});
        }
        fn sendServer(self: *ClientState, io: Io, data: []u8) !void {
            try self.client_socket.send(io, &self.server_ip, data);
        }
        fn parseInitialResponse(self: *ClientState, buffer: [12]u8) !void {
            self.reciever_public_ip = parseRecieverIp(buffer[0..6]);
            self.reciever_local_ip = parseRecieverIp(buffer[6..12]);
            self.recieved_inital_info = true;
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
            return try std.Io.net.IpAddress.parse("24.243.26.72", 5252);
        }
        fn parseRecieverIp(bytes: []const u8) ?net.IpAddress {
            var port: u16 = 0;
            port |= bytes[4];
            port <<= 8;
            port |= bytes[5];
            const v: u32 = @bitCast(bytes[0..4].*);
            if (v == 0) {
                std.debug.print("Local IP of other client not found\n", .{});
                return null;
            }
            return .{ .ip4 = .{ .bytes = bytes[0..4].*, .port = port } };
        }
    };
    const Client = struct {
        var acknowledged: bool = false;

        fn sendInitialServerMessage(io: Io) !void {
            var message: [15]u8 = undefined;
            // client code
            message[0] = @intFromEnum(ClientCode.INITIAL);
            // local ip
            @memcpy(message[1..7], &LocalIp.ipToBuf(try LocalIp.getLocalIp(io), clientState.client_socket.address.getPort()));
            // key
            @memcpy(message[7..15], &clientState.key);

            try clientState.sendServer(io, &message);
        }
        fn punching(io: Io) !void {
            while (!clientState.recieved_inital_info and !clientState.should_disconnect) try io.sleep(.fromMilliseconds(100), .awake);
            var socket = clientState.client_socket;
            for (0..30) |_| {
                if (acknowledged) break;
                if (clientState.should_disconnect) return;
                if (TESTING_RELAY) {
                    try io.sleep(.fromMilliseconds(100), .awake);
                    continue;
                }
                if (clientState.reciever_local_ip) |ip| {
                    try socket.send(io, &ip, ClientCode.getByte(.P2P) ++ "LOCAL IP");
                }
                try socket.send(io, &clientState.reciever_public_ip.?, ClientCode.getByte(.P2P) ++ "PUBLIC IP");
                try io.sleep(.fromMilliseconds(100), .awake);
            }
            if (acknowledged) {
                std.debug.print("Done Punching\n", .{});
                return;
            }
            std.debug.print("Failed to P2P\nSwitching to relay\n", .{});
            clientState.cliendMode = .Relay;
            clientState.resolved_ip = clientState.server_ip;
            var initial: [7]u8 = undefined;
            @memcpy(initial[0..], "RESOLVE");
            try send(io, initial[0..]);
            //TODO: do a proper handshake
            try io.sleep(.fromMilliseconds(100), .awake);
        }
        fn clientStart(io: Io) !void {
            if (clientState.should_disconnect) return;
            var buffer: [256]u8 = undefined;
            while (true) {
                const in = cin(io, &buffer);
                try send(io, in);
                if (std.mem.eql(u8, in, "EXIT")) return;
            }
        }
        fn send(io: Io, buf: []const u8) !void {
            if (clientState.cliendMode == .P2P) {
                if (std.mem.eql(u8, buf, "EXIT")) {
                    try clientState.sendResolved(io, &ClientCode.getByte(.TERMINATE));
                    return;
                }
                var buffer: [256]u8 = undefined;
                var w = std.Io.Writer.fixed(&buffer);
                try w.writeAll(&ClientCode.getByte(.TEXT));
                try w.writeAll(buf);
                try clientState.sendResolved(io, w.buffered());
            } else {
                if (std.mem.eql(u8, buf, "EXIT")) {
                    var buffer: [256]u8 = undefined;
                    var w = std.Io.Writer.fixed(&buffer);
                    try w.writeAll(&ClientCode.getByte(.RELAY));
                    try w.writeAll(&clientState.key);
                    try w.writeAll(&ClientCode.getByte(.TERMINATE));
                    try clientState.sendResolved(io, w.buffered());
                    return;
                }
                var buffer: [256]u8 = undefined;
                var w = std.Io.Writer.fixed(&buffer);
                try w.writeAll(&ClientCode.getByte(.RELAY));
                try w.writeAll(&clientState.key);
                try w.writeAll(&ClientCode.getByte(.TEXT));
                try w.writeAll(buf);
                try clientState.sendResolved(io, w.buffered());
            }
        }
        fn start(io: Io) !void {
            var GlobalListeningThread = try std.Thread.spawn(.{}, listen, .{io});

            try sendInitialServerMessage(io);
            try punching(io);
            if (!clientState.should_disconnect) {
                if (CHAT_MODE) {
                    try clientStart(io);
                } else {
                    try Syncing.send(io);
                }
            }

            GlobalListeningThread.join();
        }
        fn listen(io: Io) !void {
            var buffer: [1024]u8 = undefined;

            var gpa = std.heap.DebugAllocator(.{}).init;
            defer _ = gpa.deinit();

            var writer = try Io.Writer.Allocating.initCapacity(gpa.allocator(), 60_000_000);
            defer writer.deinit();
            var action: NewFileManager.Action = undefined;

            var group: std.Io.Group = .init;
            defer group.cancel(io);

            while (true) {
                const message = try clientState.client_socket.receive(io, &buffer);
                const data = message.data[1..];
                const code = ClientCode.getCode(message.data[0]);

                switch (code) {
                    .INITIAL => {
                        if (clientState.recieved_inital_info) {
                            std.debug.print("Already initalized\n", .{});
                            continue;
                        }
                        if (message.data.len == 13) {
                            try clientState.parseInitialResponse(message.data[1..13].*);
                            const p = clientState.reciever_public_ip.?.ip4.bytes;
                            var l: [4]u8 = .{ 0, 0, 0, 0 };
                            var lp: u16 = 0;
                            if (clientState.reciever_local_ip) |ip| {
                                l = ip.ip4.bytes;
                                lp = ip.getPort();
                            }
                            std.debug.print("Initial message: Other Client Public IP: {d}.{d}.{d}.{d}:{d} Local IP: {d}.{d}.{d}.{d}:{d}\n", .{ p[0], p[1], p[2], p[3], clientState.reciever_public_ip.?.getPort(), l[0], l[1], l[2], l[3], lp });
                        }
                    },
                    .TEXT => std.debug.print("recieved: {s}\n", .{message.data[1..]}),
                    .P2P => {
                        testPrint("P2P: {s}\n", .{message.data[1..]});
                        //clientState.reciever_local_ip.? = message.from;
                        clientState.resolved_ip = message.from;
                        if (clientState.reciever_local_ip) |ip| {
                            try clientState.client_socket.send(io, &ip, ClientCode.getByte(.ACK) ++ "LOCAL IP");
                        } else {
                            if (eql(message.data[1..9], "LOCAL IP")) {
                                clientState.reciever_local_ip = message.from;
                            }
                        }
                        try clientState.client_socket.send(io, &clientState.reciever_public_ip.?, ClientCode.getByte(.ACK) ++ "PUBLIC IP");
                    },
                    .ACK => {
                        testPrint("ACK: {s}\n", .{message.data[1..]});
                        if (acknowledged) continue;
                        if (std.mem.eql(u8, message.data[1..9], "LOCAL IP")) {
                            std.debug.print("USE LOCAL IP\n", .{});
                            clientState.resolved_ip = clientState.reciever_local_ip.?;
                        } else if (std.mem.eql(u8, message.data[1..10], "PUBLIC IP")) {
                            std.debug.print("USE PUBLIC IP\n", .{});
                            clientState.resolved_ip = clientState.reciever_public_ip.?;
                        }
                        acknowledged = true;
                    },
                    .DATA => {
                        // if (message.data.len < 100) {
                        //     testPrint("DATA: {s}\n", .{message.data[1..]});
                        // }
                        if (eql(data, "ADD")) action = .Add else if (eql(data, "DELETE")) action = .Delete else if (eql(data, "RENAME")) action = .Rename else if (eql(data, "STOP")) {
                            const owned = try writer.toOwnedSlice();
                            errdefer gpa.allocator().free(owned);
                            try group.concurrent(io, Syncing.threadWrapper, .{ io, gpa.allocator(), owned, action });
                            action = undefined;
                        } else {
                            try writer.writer.writeAll(data);
                        }
                    },
                    .NONE => {
                        std.debug.print("Code not handled: {b}: {s}\n", .{ message.data[0], message.data[1..] });
                    },
                    .TERMINATE => {
                        std.debug.print("Disconnected\n", .{});
                        clientState.should_disconnect = true;
                        try group.await(io);
                        break;
                    },
                    else => std.debug.print("Not implemented yet!!: {any}\n", .{code}),
                }
            }
        }
        const LocalIp = struct {
            fn getLocalIp(io: Io) ![4]u8 {
                switch (builtin.os.tag) {
                    .windows => {
                        return try getLocalIpWindows(io);
                    },
                    // .linux => {
                    //     return try getLocalIpAndroid(io);
                    // },
                    else => {
                        return .{
                            0,
                            0,
                            0,
                            0,
                        };
                    },
                }
            }
            fn getLocalIpWindows(io: std.Io) ![4]u8 {
                var result: [4]u8 = undefined;
                var child = try std.process.spawn(io, .{ .argv = &.{"ipconfig"}, .stdout = .pipe });

                var buffer: [1024]u8 = undefined;
                var wbuffer: [1024 * 2]u8 = undefined;
                var reader = child.stdout.?.reader(io, &buffer);
                var input = &reader.interface;
                var writer = std.Io.Writer.fixed(&wbuffer);

                _ = try input.streamRemaining(&writer);
                const result1 = std.mem.cut(u8, writer.buffered(), "IPv4");
                const result2 = std.mem.cut(u8, result1.?.@"1", ": ");
                const result3 = std.mem.cut(u8, result2.?.@"1", "\n");

                var byte: u8 = 0;
                var x: usize = 0;
                for (result3.?.@"0") |c| {
                    switch (c) {
                        '0'...'9' => {
                            byte = byte * 10 + (c - '0');
                        },
                        else => {
                            result[x] = byte;
                            byte = 0;
                            x += 1;
                        },
                    }
                }

                _ = try child.wait(io);
                return result;
            }
            fn getLocalIpAndroid(io: Io) ![4]u8 {
                var result: [4]u8 = .{ 192, 168, 0, 0 };
                var child = try std.process.spawn(io, .{ .argv = &.{"ifconfig"}, .stdout = .pipe });

                var buffer: [1024]u8 = undefined;
                var wbuffer: [1024]u8 = undefined;
                var reader = child.stdout.?.reader(io, &buffer);
                var input = &reader.interface;
                var writer = std.Io.Writer.fixed(&wbuffer);

                _ = try input.streamRemaining(&writer);
                const result1 = std.mem.cut(u8, writer.buffered(), "192.168.");
                //TODO: maybe fix this
                if (result1 == null) return result;
                const result2 = std.mem.cut(u8, result1.?.@"1", " ");

                var byte: u8 = 0;
                var x: usize = 0;
                for (result2.?.@"0") |c| {
                    switch (c) {
                        '0'...'9' => {
                            byte = byte * 10 + (c - '0');
                        },
                        else => {
                            result[2 + x] = byte;
                            x += 1;
                        },
                    }
                }
                result[2 + x] = byte;

                _ = try child.wait(io);
                std.debug.print("local ip: {d}.{d}.{d}.{d}\n", .{ result[0], result[1], result[2], result[3] });
                return result;
            }
            fn ipToBuf(ip: [4]u8, port: u16) [6]u8 {
                var result: [6]u8 = [_]u8{0} ** 6;
                @memcpy(result[0..4], &ip);

                result[4] |= @truncate(port >> 8);
                result[5] |= @truncate(port);

                return result;
            }
        };
    };
};
const Syncing = struct {
    fn send(io: Io) !void {
        var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer gpa.deinit();

        var changes = try NewFileManager.Changes.init(io, gpa.allocator());
        try changes.file.parse(io);
        defer changes.deinit(io);
        var music_table = try NewFileManager.MusicTable.init(io, gpa.allocator());
        try music_table.file.parse(io);
        defer music_table.deinit(io);
        for (changes.file.list.items()) |e| {
            const action: NewFileManager.Action = if (eql(e.action, "add")) .Add else if (eql(e.action, "delete")) .Delete else if (eql(e.action, "rename")) .Rename else unreachable;
            var id_buf: [8]u8 = undefined;
            const string_id = try std.fmt.bufPrint(&id_buf, "{d:0>8}", .{e.id});
            switch (action) {
                .Add => {
                    const path = music_table.file.list.items()[e.id - 1].path;
                    const hash = music_table.file.list.items()[e.id - 1].hash;
                    const file = try Io.Dir.openFileAbsolute(io, path, .{});
                    defer file.close(io);
                    var buf: [1024 * 4]u8 = undefined;
                    var reader = file.reader(io, &buf);
                    var r = &reader.interface;
                    const data = try r.allocRemaining(gpa.allocator(), .unlimited);
                    defer gpa.allocator().free(data);

                    var header_buf: [256]u8 = undefined;
                    const base_path = Io.Dir.path.basename(path);
                    const header = try std.fmt.bufPrint(&header_buf, "{d:0>8}{s}{d:0>8}{s}{d:0>8}", .{ e.id, hash, base_path.len, base_path, data.len });
                    testPrint("Sending file {s}\n", .{base_path});
                    try MySend(io, .DATA, .{ "ADD", header, data, "STOP" });
                    testPrint("Done sending\n", .{});
                },
                .Delete => {
                    testPrint("Sending ID: {d} to delete\n", .{e.id});
                    try MySend(io, .DATA, .{ "DELETE", string_id, "STOP" });
                },
                .Rename => {
                    testPrint("Sending ID: {d} to rename\n", .{e.id});
                    try MySend(io, .DATA, .{ "RENAME", string_id, "STOP" });
                },
            }
        }
        try MySend(io, .TERMINATE, .{});
        // try changes.file.clearFile(io);
    }
    fn recieve(io: Io, alloc: std.mem.Allocator, data: []const u8, action: NewFileManager.Action) !void {
        defer alloc.free(data);
        var r = Io.Reader.fixed(data);
        switch (action) {
            .Add => {
                _ = stringToNum(try r.take(8));
                const hash = try r.take(32);
                const name_len = stringToNum(try r.take(8));
                const name = try r.take(name_len);
                const content_len = stringToNum(try r.take(8));
                if (content_len != r.buffered().len) {
                    testPrint("Recieved bytes doesnt match required length.\nShould be: {d} Got: {d}\n", .{ content_len, r.buffered().len });
                }
                const content = r.buffered(); //r.take(content_len);
                const music_dir = try NewFileManager.getMusicDir(io);
                defer music_dir.close(io);
                const file = try music_dir.createFile(io, name, .{ .read = true });
                defer file.close(io);

                var buf: [1024 * 4]u8 = undefined;
                var writer = file.writer(io, &buf);
                var w = &writer.interface;

                try w.writeAll(content);
                try writer.end();
                const new_hash = try NewFileManager.Commands.Aux.hashFile(io, file);
                if (!eql(hash, &new_hash)) {
                    testPrint("Hashes dont match\n{x}\n{x}\nRecieved {d:.2}% of bytes.\n", .{ hash, new_hash, @as(f32, @floatFromInt(content.len)) / @as(f32, @floatFromInt(content_len)) * 100});
                } else {
                    testPrint("Successfully recieved song {s}\n", .{name});
                }

                // try NewFileManager.Commands.Aux.addFile(io, file, , changes: *Changes)
            },
            .Delete => {
                testPrint("Implement\n", .{});
            },
            .Rename => {
                testPrint("Implement\n", .{});
            },
        }
    }
    fn threadWrapper(io: Io, alloc: std.mem.Allocator, data: []const u8, action: NewFileManager.Action) void {
        recieve(io, alloc, data, action) catch |err| {
            testPrint("Error recieving {any}", .{err});
        };
    }
};
const NewFileManager = struct {
    const Action = enum(u2) {
        Add,
        Rename,
        Delete,
    };
    const Commands = struct {
        const Aux = struct {
            fn recurseDir(io: Io, dir: Io.Dir, table: *MusicTable, changes: *Changes) !void {
                var it = dir.iterate();

                while (it.next(io)) |e| {
                    if (e == null) break;
                    testPrint("scanning: {s}\n", .{e.?.name});
                    switch (e.?.kind) {
                        .file => {
                            var file = try dir.openFile(io, e.?.name, .{});
                            defer file.close(io);
                            try addFile(io, file, table, changes);
                        },
                        .directory => {
                            var dir1 = try dir.openDir(io, e.?.name, .{ .iterate = true });
                            defer dir1.close(io);
                            try recurseDir(io, dir1, table, changes);
                        },
                        else => {},
                    }
                } else |_| {}
            }
            fn addFile(io: Io, file: Io.File, table: *MusicTable, changes: *Changes) !void {
                var buf: [256]u8 = undefined;
                const len = try file.realPath(io, &buf);
                const hash = try hashFile(io, file);
                const result: struct { bool, usize } = blk: for (table.file.list.items()) |e| {
                    if (eql(&hash, e.hash)) {
                        testPrint("\x1b[34mSong {s} already included\x1b[0m\n", .{std.fs.path.basename(buf[0..len])});
                        break .{ false, 0 };
                    }
                } else {
                    var list = &table.file.list;
                    var alloc = &table.file.alloc;
                    const id = list.items().len + 1;
                    try list.append(.{ .id = id, .hash = try alloc.dupe(u8, &hash), .path = try alloc.dupe(u8, buf[0..len]) });
                    testPrint("\x1b[32mAdded song: {s}\x1b[0m\n", .{std.fs.path.basename(buf[0..len])});
                    break :blk .{ true, id };
                };
                if (result.@"0") {
                    try changes.file.list.append(.{ .action = try changes.file.alloc.dupe(u8, "add"), .id = result.@"1" });
                }
            }
            fn hashFile(io: Io, file: Io.File) ![32]u8 {
                var result: [32]u8 = undefined;
                var b = std.crypto.hash.Blake3.init(.{});

                var buf: [1024 * 4]u8 = undefined;
                var reader = file.reader(io, &buf);
                var r = &reader.interface;

                var data: [1024 * 4]u8 = undefined;
                while (true) {
                    const len = try r.readSliceShort(&data);
                    b.update(data[0..len]);
                    if (len != data.len) break;
                }

                b.final(&result);
                return result;
            }
            fn removeDelete(io: Io, path: []const u8, action: []const u8) !void {
                var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer gpa.deinit();

                var music_table = try MusicTable.init(io, gpa.allocator());
                defer music_table.deinit(io);
                try music_table.file.parse(io);
                var music_paths = try MusicPaths.init(io, gpa.allocator());
                defer music_paths.deinit(io);
                try music_paths.file.parse(io);
                var changes = try Changes.init(io, gpa.allocator());
                defer changes.deinit(io);
                try changes.file.parse(io);
                const music_dir = try getMusicDir(io);
                defer music_dir.close(io);

                if (!isFile(path)) return error.PathNotAFile;
                var file = switch (std.fs.path.isAbsolute(path)) {
                    true => try Io.Dir.openFileAbsolute(io, path, .{}),
                    false => music_dir.openFile(io, path, .{}) catch |err| switch (err) {
                        error.FileNotFound => {
                            testPrint("File: {s} not found\n", .{path});
                            return;
                        },
                        else => return err,
                    },
                };
                defer file.close(io);
                const hash = try Aux.hashFile(io, file);

                const entry: MusicTable.Entry = for (music_table.file.list.items()) |e| {
                    if (eql(&hash, e.hash)) {
                        const entry = music_table.file.list.list.orderedRemove(e.id - 1);
                        try music_table.writeAllOrdered(io);
                        break entry;
                    }
                } else {
                    testPrint("Attempt to {s} song {s} not found in music table\n", .{ action, path });
                    return;
                };

                var path_buf: [256]u8 = undefined;
                const absolute_path: []const u8 = if (std.fs.path.isAbsolute(path)) path else blk: {
                    const len = try file.realPath(io, &path_buf);
                    break :blk path_buf[0..len];
                };

                testPrint("{s} {s} with id: {d}\n", .{ action, entry.path, entry.id });
                if (eql(action, "delete")) {
                    // FIXME
                    // try Io.Dir.deleteFileAbsolute(io, entry.path);
                    // TODO if add 1 and delete 1 then cancel them out
                    // add id:1
                    // add id:2
                    // delete id:1
                } else if (eql(action, "remove")) {
                    var remove_file = try getRemoveDir(io);
                    defer remove_file.close(io);
                    var buf: [256]u8 = undefined;
                    const new_path_len = try remove_file.realPath(io, &buf);
                    const basename = std.fs.path.basename(path);
                    const new_path = try std.fs.path.join(gpa.allocator(), &.{ buf[0..new_path_len], basename });
                    defer gpa.allocator().free(new_path);

                    try Io.Dir.renameAbsolute(absolute_path, new_path, io);
                    // TODO if add 1 and remove 1 then cancel them out
                    // add id:1
                    // add id:2
                    // remove id:1
                }
                try changes.file.list.append(.{ .action = action, .id = entry.id });
                try changes.file.writeAll(io);

                for (music_paths.file.list.items(), 0..) |e, i| {
                    const path_absolute_path: []const u8 = if (std.fs.path.isAbsolute(e.path)) e.path else blk: {
                        const len = try file.realPath(io, &path_buf);
                        break :blk path_buf[0..len];
                    };
                    if (eql(absolute_path, path_absolute_path)) {
                        _ = music_paths.file.list.list.swapRemove(i);
                        try music_paths.file.writeAll(io);
                        break;
                    }
                }
            }
            fn allocRealPath(io: Io, alloc: std.mem.Allocator, file: Io.File) ![]u8 {
                var buf = try alloc.alloc(u8, 256);
                const len = try file.realPath(io, buf);
                return buf[0..len];
            }
        };
        // path relative to app/music or absolute
        fn add(io: Io, path: []const u8) !void {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var music_table = try MusicTable.init(io, gpa.allocator());
            defer music_table.deinit(io);
            try music_table.file.parse(io);
            var music_paths = try MusicPaths.init(io, gpa.allocator());
            defer music_paths.deinit(io);
            try music_paths.file.parse(io);
            var changes = try Changes.init(io, gpa.allocator());
            defer changes.deinit(io);
            try changes.file.parse(io);
            const music_dir = try getMusicDir(io);
            defer music_dir.close(io);

            const is_absolute = std.fs.path.isAbsolute(path);
            if (isFile(path)) {
                if (!isSong(path)) return error.NotASong;
                const file = switch (is_absolute) {
                    true => try Io.Dir.openFileAbsolute(io, path, .{}),
                    false => try music_dir.openFile(io, path, .{}),
                };
                defer file.close(io);
                for (music_paths.file.list.items()) |line| {
                    if (eql(path, line.path)) break;
                } else {
                    try music_paths.file.list.append(.{ .path = try music_paths.file.alloc.dupe(u8, path) });
                    try music_paths.file.writeAll(io);
                }
                try Aux.addFile(io, file, &music_table, &changes);
            } else {
                const dir = switch (is_absolute) {
                    true => try Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }),
                    false => try music_dir.openDir(io, path, .{ .iterate = true }),
                };
                defer dir.close(io);
                for (music_paths.file.list.items()) |line| {
                    if (eql(path, line.path)) break;
                } else {
                    try music_paths.file.list.append(.{ .path = try music_paths.file.alloc.dupe(u8, path) });
                    try music_paths.file.writeAll(io);
                }
                try Aux.recurseDir(io, dir, &music_table, &changes);
            }
            try music_table.file.writeAll(io);
            try changes.file.writeAll(io);
        }
        fn rename(io: Io, old: []const u8, new: []const u8) !void {
            if (!isFile(old)) return;
            if (!isSong(old)) return;
            if (!eql(std.fs.path.extension(old), std.fs.path.extension(new))) {
                testPrint("Extensions dont match in rename\n", .{});
                return;
            }
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var music_table = try MusicTable.init(io, gpa.allocator());
            defer music_table.deinit(io);
            try music_table.file.parse(io);
            var music_paths = try MusicPaths.init(io, gpa.allocator());
            defer music_paths.deinit(io);
            try music_paths.file.parse(io);
            var changes = try Changes.init(io, gpa.allocator());
            defer changes.deinit(io);
            try changes.file.parse(io);
            const music_dir = try getMusicDir(io);
            defer music_dir.close(io);

            const file = switch (Io.Dir.path.isAbsolute(old)) {
                true => try Io.Dir.openFileAbsolute(io, old, .{}),
                false => try music_dir.openFile(io, new, .{}),
            };
            defer file.close(io);
            var old_absolute_path_buf: [256]u8 = undefined;
            const old_absolute_path = old_absolute_path_buf[0..try file.realPath(io, &old_absolute_path_buf)];
            const base_dir = try Io.Dir.openDirAbsolute(io, Io.Dir.path.dirname(old_absolute_path).?, .{});
            defer base_dir.close(io);

            const hash = try Aux.hashFile(io, file);
            const entry: *MusicTable.Entry = for (music_table.file.list.items()) |*e| {
                if (eql(&hash, e.hash)) break e;
            } else {
                testPrint("Song {s} not found in music table\n", .{old});
                return;
            };
            testPrint("Renaming {s} to {s}\n", .{ std.fs.path.basename(old), new });
            try base_dir.renamePreserve(old, base_dir, new, io);
            var new_absolute_path_buf: [256]u8 = undefined;
            const new_absolute_path = new_absolute_path_buf[0..try file.realPath(io, &new_absolute_path_buf)];

            entry.*.path = try music_table.file.alloc.dupe(u8, new_absolute_path);
            try music_table.file.writeAll(io);
            try changes.file.list.append(.{ .action = "rename", .id = entry.id });
            try changes.file.writeAll(io);

            for (music_paths.file.list.items()) |*e| {
                const entry_absolute_path: []const u8 = blk: switch (Io.Dir.path.isAbsolute(e.*.path)) {
                    true => e.*.path,
                    false => {
                        const entry_file = try music_dir.openFile(io, e.*.path, .{});
                        defer entry_file.close(io);
                        break :blk try Aux.allocRealPath(io, gpa.allocator(), file);
                    },
                };
                if (eql(old_absolute_path, entry_absolute_path)) {
                    const new_path: []const u8 = blk: switch (Io.Dir.path.isAbsolute(e.*.path)) {
                        true => new_absolute_path,
                        false => {
                            if (Io.Dir.path.dirname(e.*.path)) |base| {
                                break :blk try Io.Dir.path.join(gpa.allocator(), &.{ base, new });
                            } else {
                                break :blk new;
                            }
                        },
                    };
                    e.*.path = new_path;
                    try music_paths.file.writeAll(io);
                    break;
                }
            }
        }
        fn scan(io: Io) !void {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var music_table = try MusicTable.init(io, gpa.allocator());
            defer music_table.deinit(io);
            try music_table.file.parse(io);
            var music_paths = try MusicPaths.init(io, gpa.allocator());
            defer music_paths.deinit(io);
            try music_paths.file.parse(io);
            var changes = try Changes.init(io, gpa.allocator());
            defer changes.deinit(io);
            try changes.file.parse(io);
            const music_dir = try getMusicDir(io);
            defer music_dir.close(io);

            try Aux.recurseDir(io, music_dir, &music_table, &changes);
            for (music_paths.file.list.items()) |e| {
                const path = e.path;
                switch (isSong(path)) {
                    true => {
                        const file = switch (std.fs.path.isAbsolute(path)) {
                            true => try Io.Dir.openFileAbsolute(io, path, .{}),
                            false => try music_dir.openFile(io, path, .{}),
                        };
                        defer file.close(io);
                        try Aux.addFile(io, file, &music_table, &changes);
                    },
                    false => {
                        const dir = switch (std.fs.path.isAbsolute(path)) {
                            true => try Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }),
                            false => try music_dir.openDir(io, path, .{ .iterate = true }),
                        };
                        defer dir.close(io);
                        try Aux.recurseDir(io, dir, &music_table, &changes);
                    },
                }
            }
            try music_table.file.writeAll(io);
            try changes.file.writeAll(io);
        }
        fn delete(io: Io, path: []const u8) !void {
            try Aux.removeDelete(io, path, "delete");
        }
        fn remove(io: Io, path: []const u8) !void {
            try Aux.removeDelete(io, path, "remove");
        }
    };
    const MusicTable = struct {
        file: table,

        const music_table_name_file = "musicTable.txt";
        const table = MyFile(Entry, "{d} {s}{s}\n", .{ @as(u8, ' '), 32, @as(u8, '\n') });

        const Entry = struct {
            id: usize,
            hash: []const u8,
            path: []const u8,
        };
        fn init(io: Io, alloc: std.mem.Allocator) !@This() {
            const file = try getOrCreateFile(io, music_table_name_file);
            return .{
                .file = try table.init(alloc, file),
            };
        }
        fn deinit(self: *@This(), io: Io) void {
            self.file.deinit(io);
        }
        fn writeAllOrdered(self: *@This(), io: Io) !void {
            var buf: [1024]u8 = undefined;
            var fw = self.file.file.writer(io, &buf);
            var w = &fw.interface;

            for (self.file.list.items(), 1..) |item, i| {
                try w.print(MusicTable.table.returnfmt(), .{ i, item.hash, item.path });
            }
            try fw.end();
        }
    };
    const MusicPaths = struct {
        file: table,

        const music_dir_paths_name_file = "musicDirPaths.txt";
        const table = MyFile(Entry, "{s}\n", .{@as(u8, '\n')});

        const Entry = struct {
            path: []const u8,
        };
        fn init(io: Io, alloc: std.mem.Allocator) !@This() {
            const file = try getOrCreateFile(io, music_dir_paths_name_file);
            return .{
                .file = try table.init(alloc, file),
            };
        }
        fn deinit(self: *@This(), io: Io) void {
            self.file.deinit(io);
        }
    };
    const Changes = struct {
        file: table,

        const changes_file_name = "changes.txt";
        // FIXME id:{d} still works with stringtonum(id:{d}) maybe make better
        const table = MyFile(Entry, "{s} id:{d}\n", .{ @as(u8, ' '), @as(u8, '\n') });

        const Entry = struct {
            action: []const u8,
            id: usize,
        };
        fn init(io: Io, alloc: std.mem.Allocator) !@This() {
            const file = try getOrCreateFile(io, changes_file_name);
            return .{
                .file = try table.init(alloc, file),
            };
        }
        fn deinit(self: *@This(), io: Io) void {
            self.file.deinit(io);
        }
    };
    const KeyStuff = struct {
        fn getKeyFile(io: Io) !Io.File {
            return getOrCreateFile(io, "key.txt");
        }
        fn getKey(io: Io) ![8]u8 {
            const file = try getKeyFile(io);
            defer file.close(io);

            var rbuf: [256]u8 = undefined;
            var wbuf: [256]u8 = undefined;
            var reader = file.reader(io, &rbuf);
            var input = &reader.interface;
            var writer = std.Io.Writer.fixed(&wbuf);

            const len = try input.streamRemaining(&writer);
            if (len == 0) {
                std.debug.print("No Key Found, Generating New Key\n", .{});
                const key = try generateNewKey(io);
                std.debug.print("New Key Generated: {s}\n", .{key});
                try writeKey(io, key);
                std.debug.print("New Key Set\n", .{});
                return key;
            }
            if (len != 8) {
                std.debug.print("len of key: {d}\n", .{len});
                return error.ErrorReadingKeyFromFile;
            }
            // if (TESTING) {
            //     const result: [8]u8 = [_]u8{'5'} ** 8;
            //     std.debug.print("Using Testing key\n", .{});
            //     return result;
            // }
            std.debug.print("Key Read: {s}\n", .{wbuf[0..8]});
            return wbuf[0..8].*;
        }
        fn generateNewKey(io: Io) ![8]u8 {
            const seed: u64 = @bitCast(std.Io.Timestamp.now(io, .awake).toMicroseconds());
            var rand = std.Random.DefaultPrng.init(seed);

            var key: [8]u8 = undefined;
            for (&key) |*c| {
                const offset: u8 = @intCast(rand.next() % 10);
                c.* = '0' + offset;
            }
            return key;
        }
        fn writeKey(io: Io, key: [8]u8) !void {
            var file = try getKeyFile(io);
            defer file.close(io);

            var wBuffer: [128]u8 = undefined;
            var writer = file.writer(io, &wBuffer);
            var output = &writer.interface;

            _ = try output.write(&key);
            try output.flush();
            try writer.end();
        }
    };
    const testing = struct {
        fn reset(io: Io) !void {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();
            var music_table = try MusicTable.init(io, gpa.allocator());
            defer music_table.deinit(io);
            var music_paths = try MusicPaths.init(io, gpa.allocator());
            defer music_paths.deinit(io);
            var changes = try Changes.init(io, gpa.allocator());
            defer changes.deinit(io);
            try music_table.file.clearFile(io);
            try music_paths.file.clearFile(io);
            try changes.file.clearFile(io);
        }
    };
    fn getAppDir(io: Io) !Io.Dir {
        const app_dir_name = if (TESTING) "testing/" ++ app_directory else app_directory;
        const cwd = std.Io.Dir.cwd();

        return cwd.openDir(io, app_dir_name, .{}) catch try cwd.createDirPathOpen(io, app_dir_name, .{});
    }
    fn getMusicDir(io: Io) !Io.Dir {
        const music_dir_name = "music";
        const app_dir = try getAppDir(io);
        defer app_dir.close(io);

        return app_dir.openDir(io, music_dir_name, .{ .iterate = true }) catch try app_dir.createDirPathOpen(io, music_dir_name, .{});
    }
    fn getRemoveDir(io: Io) !Io.Dir {
        const remove_dir_name = "removedSongs";
        const app_dir = try getAppDir(io);
        defer app_dir.close(io);

        return app_dir.openDir(io, remove_dir_name, .{ .iterate = true }) catch try app_dir.createDirPathOpen(io, remove_dir_name, .{});
    }
    fn getOrCreateFile(io: Io, name: []const u8) !Io.File {
        const app_dir = try getAppDir(io);
        defer app_dir.close(io);

        return app_dir.openFile(io, name, .{ .mode = .read_write }) catch
            try app_dir.createFile(io, name, .{ .read = true });
    }
    fn isFile(path: []const u8) bool {
        const basename = std.fs.path.basename(path);
        if (eql(".", basename) or eql("..", basename)) return false;
        if (path.len == 0) return false;
        for (1..basename.len) |i| {
            if (basename[basename.len - i] == '.') {
                return true;
            }
        }
        return false;
    }
    fn isSong(path: []const u8) bool {
        const extension = std.fs.path.extension(path);
        for (song_extensions) |e| {
            if (eql(e, extension)) return true;
        }
        return false;
    }
};
fn MyFile(comptime T: type, comptime format: []const u8, parse_rules: anytype) type {
    return struct {
        list: MyList(T),
        file: Io.File,
        alloc: std.mem.Allocator,

        fn init(alloc: std.mem.Allocator, file: Io.File) !@This() {
            return .{
                .list = try MyList(T).init(alloc),
                .file = file,
                .alloc = alloc,
            };
        }
        fn deinit(self: *@This(), io: Io) void {
            self.list.deinit();
            self.file.close(io);
        }
        fn parse(self: *@This(), io: Io) !void {
            var buf: [1024]u8 = undefined;
            var fr = self.file.reader(io, &buf);
            const data = try fr.interface.allocRemaining(self.alloc, .unlimited);
            var r = Io.Reader.fixed(data);

            const fields = @typeInfo(T).@"struct".fields;
            const parse_fields = @typeInfo(@TypeOf(parse_rules)).@"struct".fields;
            comptime std.debug.assert(fields.len == parse_fields.len);

            while (r.seek < r.end) {
                var item: T = undefined;
                inline for (parse_fields, fields) |pf, f| {
                    const rule = @field(parse_rules, pf.name);

                    const chunk: []const u8 = switch (pf.type) {
                        u8 => (try r.takeDelimiter(rule)) orelse return error.EndOfStream,
                        comptime_int => try r.take(rule),
                        else => @compileError("type not supported: " ++ @typeName(pf.type)),
                    };

                    @field(item, f.name) = switch (f.type) {
                        usize => stringToNum(chunk),
                        []const u8 => chunk,
                        else => @compileError("field not supported: " ++ @typeName(f.type)),
                    };
                }
                try self.list.append(item);
            }
        }
        fn printAll(self: *@This()) !void {
            for (self.list.items()) |item| {
                testPrint(format, item);
            }
        }
        fn writeAll(self: *@This(), io: Io) !void {
            var buf: [1024]u8 = undefined;
            var fw = self.file.writer(io, &buf);
            var w = &fw.interface;

            for (self.list.items()) |item| {
                try w.print(format, item);
            }
            try fw.end();
        }
        fn clearFile(self: *@This(), io: Io) !void {
            var fw = self.file.writer(io, &.{});
            try fw.end();
        }
        fn returnfmt() []const u8 {
            return format;
        }
    };
}
fn MyList(comptime T: type) type {
    return struct {
        list: std.ArrayList(T),
        alloc: std.mem.Allocator,

        fn init(alloc: std.mem.Allocator) !@This() {
            return .{
                .list = try std.ArrayList(T).initCapacity(alloc, 4),
                .alloc = alloc,
            };
        }
        fn deinit(self: *@This()) void {
            self.list.deinit(self.alloc);
        }
        fn append(self: *@This(), value: T) !void {
            try self.list.append(self.alloc, value);
        }
        fn items(self: *@This()) []T {
            return self.list.items;
        }
        // TODO Figure out this
        fn printList(self: *@This()) void {
            for (self.items()) |x| {
                _ = x;
            }
        }
    };
}
fn MySend(io: Io, comptime code: ClientCode, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    const header = switch (clientState.cliendMode) {
        .P2P => try std.fmt.bufPrint(buf[0..], "{s}", .{ClientCode.getByte(code)}),
        .Relay => try std.fmt.bufPrint(buf[0..], "{s}{s}{s}", .{ ClientCode.getByte(.RELAY), clientState.key, ClientCode.getByte(code) }),
    };
    const typeinfo = @typeInfo(@TypeOf(args));
    const fields = typeinfo.@"struct".fields;

    if (fields.len == 0) {
        try clientState.sendResolved(io, buf[0..header.len]);
    }
    inline for (fields) |f| {
        const data: []const u8 = switch (@typeInfo(f.type)) {
            .pointer => |p| blk: switch (p.size) {
                .many => if (p.sentinel() != null) break :blk std.mem.span(@field(args, f.name)),
                .slice => break :blk @field(args, f.name),
                .one => switch (@typeInfo(p.child)) {
                    .array => |a| if (a.child == u8) break :blk @field(args, f.name),
                    else => {},
                },
                else => @compileError("arg not supported: " ++ @typeName(f.type)),
            },
            else => @compileError("arg not supported: " ++ @typeName(f.type)),
        };
        var r = Io.Reader.fixed(data);
        var amount: usize = 0;
        while (r.seek < r.end) {
            const d = r.take(1024 - header.len) catch r.buffered();
            @memcpy(buf[header.len .. header.len + d.len], d);
            try clientState.sendResolved(io, buf[0 .. header.len + d.len]);
            amount += 1;
            if (amount % 64 == 0) try io.sleep(.fromMilliseconds(1), .awake);
            if (d.len != 1024 - header.len) break;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    try start(init.io, args[1..]);
}
pub fn start(io: Io, args: []const [:0]const u8) !void {
    Networks.Client.acknowledged = false;
    clientState = .init(io);
    defer clientState.deinit(io);

    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();

    //FIXME me later, this is temp
    // if (args.len >= 2) {
    //     var buf: [256]u8 = undefined;
    //     var i: usize = 0;
    //     for (args[1..], 1..) |arg, a| {
    //         @memcpy(buf[i .. i + arg.len], arg);
    //         i += arg.len;
    //         if (a == args.len - 1) break;
    //         buf[i] = ' ';
    //         i += 1;
    //     }
    //     if (eql(args[0], "add")) {
    //         try FileManager.Commands.addPathTableChange(io, buf[0..i]);
    //         return;
    //     } else if (eql(args[0], "delete")) {
    //         testPrint("DELETEING: {s}\n", .{buf[0..i]});
    //         const entry = try FileManager.MusicTable.deleteEntry(io, buf[0..i]);
    //         try FileManager.Changes.deleteSong(io, entry.id);
    //         //std.fs.path.isAbsolute(path: []const u8)
    //         try FileManager.deleteSongRelative(io, buf[0..i]);
    //         return;
    //     }
    // }

    switch (args.len) {
        0 => {
            try Networks.Client.start(io);
        },
        1 => {
            if (eql(args[0], "sync")) {
                try Networks.Client.start(io);
            } else if (eql(args[0], "sync_new_key")) {
                try NewFileManager.KeyStuff.writeKey(io, try NewFileManager.KeyStuff.generateNewKey(io));
            } else if (eql(args[0], "scan")) {
                try NewFileManager.Commands.scan(io);
            } else if (eql(args[0], "testreset")) {
                try NewFileManager.testing.reset(io);
            }
        },
        2 => {
            if (eql(args[0], "sync")) {
                if (args[1].len != 8) return error.KeyWrongLength;
                var key: [8]u8 = undefined;
                @memcpy(&key, args[1][0..8]);
                try NewFileManager.KeyStuff.writeKey(io, key);
                clientState.key = key;

                try Networks.Client.start(io);
            } else if (eql(args[0], "add")) {
                try NewFileManager.Commands.add(io, args[1]);
            } else if (eql(args[0], "delete")) {
                try NewFileManager.Commands.delete(io, args[1]);
            } else if (eql(args[0], "remove")) {
                try NewFileManager.Commands.remove(io, args[1]);
            }
        },
        3 => {
            if (eql(args[0], "rename")) {
                try NewFileManager.Commands.rename(io, args[1], args[2]);
            }
        },
        else => {
            testPrint("Invalid args\n", .{});
        },
    }
}

var lock = std.Io.Mutex.init;
fn print(io: Io, comptime fmt: []const u8, args: anytype) void {
    lock.lock(io) catch unreachable;
    std.debug.print("\x1b[1A" ++ fmt ++ "\x1b[1E", args);
    lock.unlock(io);
}
fn testPrint(comptime fmt: []const u8, args: anytype) void {
    if (!TESTING) return;
    std.debug.print(fmt, args);
}
fn cin(io: std.Io, buffer: []u8) []u8 {
    var rBuffer: [256]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &rBuffer);
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
pub fn stringToNum(bytes: []const u8) usize {
    var result: usize = 0;
    for (bytes) |c| switch (c) {
        '0'...'9' => {
            result = result * 10 + (c - '0');
        },
        else => {},
    };
    return result;
}
test "Add Command" {
    // const io = std.testing.io;
    // var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer gpa.deinit();
}
test "Rename Command" {
    // const io = std.testing.io;
    // var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer gpa.deinit();
}
test "Delete Command" {}
test "Update Command" {}
