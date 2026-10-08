const std = @import("std");
const net = std.Io.net;
const builtin = @import("builtin");
const ClientCode = @import("server.zig").Networks.ClientCode;

const Io = std.Io;

// Goal for now
// Connect two clients to allow talk between the two

// send initial message to server
// recieve reciever ip
// attempt to connect to reciever ip
// if fails fall back to relaying
var clientState: Networks.ClientState = undefined;
const TESTING_RELAY: bool = false;
const TESTING: bool = true;
const CHAT_MODE: bool = false;

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
                .key = FileManager.KeyStuff.getKey(io) catch unreachable,
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
                    try Syncing.sync(io);
                }
            }

            GlobalListeningThread.join();
        }
        fn listen(io: Io) !void {
            var buffer: [1024]u8 = undefined;

            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();
            var writer = Io.Writer.Allocating.init(gpa.allocator());
            defer writer.deinit();
            var action: FileManager.Changes.Action = undefined;


            while (true) {
                const message = try clientState.client_socket.receive(io, &buffer);
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
                            var l: [4]u8 = .{0,0,0,0};
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
                        if (eql(message.data[1..], "FILE")) action = .ADD
                        else if (eql(message.data[1..], "STOP")) switch (action) {
                            .ADD => {
                                try Syncing.recieveFile(io, &writer.writer);
                                _ = writer.writer.consumeAll();
                                action = undefined;
                            },
                            else => {
                                testPrint("Not implemented: {any}\n", .{action});
                            }
                        } else {
                            try writer.writer.writeAll(message.data[1..]);
                        }
                        
                    },
                    .NONE => {
                        std.debug.print("Code not handled: {b}: {s}\n", .{ message.data[0], message.data[1..] });
                    },
                    .TERMINATE => {
                        std.debug.print("Disconnected\n", .{});
                        clientState.should_disconnect = true;
                        break;
                    },
                    else => std.debug.print("Not implemented yet!!: {any}\n", .{code}),
                }
            }
        }
        const Syncing = struct {
            fn sync(io: Io) !void {
                var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer gpa.deinit();

                const list = try FileManager.Changes.getChanges(io, gpa.allocator());
                for (list.items) |e| {
                    switch (e.action) {
                        .ADD => {
                            testPrint("{any}: {s}\n", .{e.action, e.path});
                            try sendFile(io, e);
                            try io.sleep(.fromMicroseconds(500), .awake);
                        },
                        else => {
                            testPrint("Not implemented {any}\n", .{e.action});
                        }
                    }
                }
                testPrint("DONE SENDING STUFF\n", .{});
                // const exit = "EXIT";
                // try send(io, exit);
            }
            fn sendFile(io: Io, entry: FileManager.Changes.Entry) !void {
                const path = entry.path;
                const id = entry.id;
                var file = try Io.Dir.openFileAbsolute(io, path, .{});
                defer file.close(io);
                const basename = std.fs.path.basename(path);
                
                var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer gpa.deinit();

                var rbuf: [1024*4]u8 = undefined;
                var fr = file.reader(io, &rbuf);
                var reader = &fr.interface;
                const data = try reader.allocRemaining(gpa.allocator(), .unlimited);
                var buufferedr = Io.Reader.fixed(data);

                switch (clientState.cliendMode) {
                    .P2P => {
                        var senddata: [1024]u8 = undefined;
                        senddata[0] = ClientCode.getByte(.DATA)[0];

                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "FILE");
                        const header = try std.fmt.bufPrint(senddata[1..], "{d:0>8}{d:0>8}{s}{d:0>8}", .{id, basename.len, basename, data.len});
                        testPrint("file header: {s}\n", .{header});
                        try clientState.sendResolved(io, senddata[0..header.len+1]);

                        var sent: usize = 0;
                        while (true) {
                            const d = buufferedr.take(1023) catch buufferedr.buffered();
                            @memcpy(senddata[1..d.len+1], d);
                            try clientState.sendResolved(io, senddata[0..d.len+1]);
                            sent += 1;
                            if (sent % 16 == 0) try io.sleep(.fromMilliseconds(1), .awake);
                            if (d.len != 1023) break;
                        }
                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "STOP");
                    },
                    .Relay => {
                        var senddata: [1024]u8 = undefined;
                        const header = try std.fmt.bufPrint(senddata[0..], "{s}{s}{s}", .{ClientCode.getByte(.RELAY), clientState.key, ClientCode.getByte(.DATA)});

                        @memcpy(senddata[header.len..header.len+4], "FILE");
                        try clientState.sendResolved(io, senddata[0..header.len+4]);

                        const fheader = try std.fmt.bufPrint(senddata[header.len..], "{d:0>8}{d:0>8}{s}{d:0>8}", .{id, basename.len, basename, data.len});
                        testPrint("file header: {s}\n", .{fheader});
                        try clientState.sendResolved(io, senddata[0..header.len+fheader.len]);

                        var sent: usize = 0;
                        while (true) {
                            const d = buufferedr.take(1024-header.len) catch buufferedr.buffered();
                            @memcpy(senddata[header.len..header.len+d.len], d);
                            try clientState.sendResolved(io, senddata[0..header.len+d.len]);
                            sent += 1;
                            if (sent % 16 == 0) try io.sleep(.fromMilliseconds(1), .awake);
                            if (d.len != 1024-header.len) break;
                        }

                        @memcpy(senddata[header.len..header.len+4], "STOP");
                        try clientState.sendResolved(io, senddata[0..header.len+4]);
                    }
                }

            }
            fn recieveFile(io: Io, writer: *Io.Writer) !void {
                //TODO: use the id
                const id = stringToNum(writer.buffered()[0..8]);
                const name_len = stringToNum(writer.buffered()[8..16]);
                const name = writer.buffered()[16..16+name_len];
                const content_len = stringToNum(writer.buffered()[16+name_len..24+name_len]);
                const content = writer.buffered()[24+name_len..24+name_len+content_len];

                testPrint("adding file {s} with id: {d} len: {d}\n", .{name, id, content_len});

                var dir = try FileManager.getMusicDir(io);
                defer dir.close(io);

                var file = try dir.createFile(io, name, .{ .read = true });

                var wbuf: [1024*4]u8 = undefined;
                var fwriter = file.writer(io, &wbuf);
                var fw = &fwriter.interface;

                try fw.writeAll(content);
                try fw.flush();

                file.close(io);
                _ = try FileManager.MusicTable.addEntry(io, dir, name);
            }
        };
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

const app_directory: []const u8 = "app/";
const FileManager = struct {
    fn getAppDir(io: Io) !Io.Dir {
        const app_dir_name = if (TESTING) "testing/" ++ app_directory else app_directory;
        const cwd = std.Io.Dir.cwd();

        return cwd.openDir(io, app_dir_name, .{}) catch try cwd.createDirPathOpen(io, app_dir_name, .{});
    }
    fn getMusicDir(io: Io) !Io.Dir {
        const music_dir_name = "music";
        const cwd = std.Io.Dir.cwd();

        return cwd.openDir(io, music_dir_name, .{}) catch try cwd.createDirPathOpen(io, music_dir_name, .{});
    }
    fn getOrCreateFile(io: Io, name: []const u8) !Io.File {
        const app_dir = try getAppDir(io);
        defer app_dir.close(io);

        return app_dir.openFile(io, name, .{ .mode = .read_write }) catch 
        try app_dir.createFile(io, name, .{ .read = true });
    }
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
    fn fileToToken(io: Io, file: Io.File, alloc: std.mem.Allocator) !std.mem.TokenIterator(u8, .any) {
        var rbuf: [256]u8 = undefined;
        var reader = file.reader(io, &rbuf);
        var rf = &reader.interface;
        const data = try rf.allocRemaining(alloc, .unlimited);

        return std.mem.tokenizeAny(u8, data, "\r\n");
    }
    const MusicPath = struct {
        fn getMusicPathsFile(io: Io) !Io.File {
            return getOrCreateFile(io, "musicDirPaths.txt");
        }
        fn addPathToFile(io: Io, path: []const u8) !void {
            //testPrint("{s}\n", .{path});
            var file = try getMusicPathsFile(io);
            defer file.close(io);
            
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var it = try fileToToken(io, file, gpa.allocator());
            while (it.next()) |entry|{
                if (eql(path, entry)) {
                    return;
                }
            }

            var wbuf: [256]u8 = undefined;
            var writer = file.writer(io, &wbuf);
            var wf = &writer.interface;

            try writer.seekTo(try file.length(io));
            _ = try wf.writeAll(path);
            try wf.writeByte('\n');
            try wf.flush();
        }
        fn deletePath(io: Io, path: []const u8) !void {
            var file = try getMusicPathsFile(io);
            defer file.close(io);

            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var wbuf: [256]u8 = undefined;
            var writer = file.writer(io, &wbuf);
            try file.setLength(io, 0);
            var wf = &writer.interface;

            var it = fileToToken(io, file, gpa.allocator());
            while (it.next()) |entry|{
                if (!eql(path, entry)) {
                    try wf.writeAll(entry);
                    try wf.writeByte('\n');
                }
            }
            try wf.flush();
        }
        fn addPath(io: Io, cwd: Io.Dir, path: []const u8) !void {
            try addPathToFile(io, path);
            const basename = std.fs.path.basename(path);
            for (1..basename.len) |i| {
                if (basename[basename.len-i] == '.') {
                    const num = try MusicTable.addEntry(io, cwd, path);
                    try Changes.addSong(io, num);
                    return;
                }
            }
            try addFolder(io, cwd, path);
        }
        fn addFolder(io: Io, cwd: Io.Dir, path: []const u8) !void {
            const dir = try cwd.openDir(io, path, .{.iterate = true});
            defer dir.close(io);

            var it = dir.iterate();

            while (it.next(io)) |entry| {
                if (entry == null) break;
                switch (entry.?.kind) {
                    .file => {
                        const num = try MusicTable.addEntry(io, dir, entry.?.name);
                        try Changes.addSong(io, num);
                    },
                    .directory => {
                        try addFolder(io, dir, entry.?.name);
                    },
                    else => {}
                }
            } else |_| {}
        }
    };
    const MusicTable = struct {
        const Entry = struct {
            id: usize,
            hash: []const u8,
            path: []const u8,
        };
        fn getMusicTableFile(io: Io) !Io.File {
            return getOrCreateFile(io, "musicTable.txt");
        }
        fn addEntry(io: Io, dir: Io.Dir, path: []const u8) !usize {
            var file = try getMusicTableFile(io);
            defer file.close(io);
            const song = try dir.openFile(io, path, .{});
            defer song.close(io);

            var pathbuf: [256]u8 = undefined;
            const pathlen = try dir.realPathFile(io, path, &pathbuf);

            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            const list = try parseMusicTableFile(io, gpa.allocator());

            const hash = try hashFile(io, song);
            for (list.items) |e| {
                if (eql(&hash, e.hash)) {
                    testPrint("Song {s} already included\n", .{path});
                    return 0;
                }
            } else {
                var wbuf: [1024]u8 = undefined;
                var writer = file.writer(io, &wbuf);
                var fw = &writer.interface;
                try writer.seekTo(try file.length(io));
                try fw.print("{d} {s} {s}\n", .{list.items.len+1, hash, pathbuf[0..pathlen]});
                try fw.flush();
                testPrint("Added song: {s}\n", .{path});
                return list.items.len+1;
               // try Changes.addSong(io, list.items.len+1);
            }
        }
        fn hashFile(io: Io, file: Io.File) ![32]u8 {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var rbuf: [1024]u8 = undefined;
            var reader = file.reader(io, &rbuf);
            var fr = &reader.interface;
            const data = try fr.allocRemaining(gpa.allocator(), .unlimited);

            var h = std.crypto.hash.Blake3.init(.{});
            var result: [32]u8 = undefined;

            h.update(data);

            h.final(&result);
            return result;
        }
        fn parseMusicTableFile(io: Io, alloc: std.mem.Allocator) !std.ArrayList(Entry) {
            var file = try getMusicTableFile(io);
            defer file.close(io);

            var rbuf: [1024]u8 = undefined;
            var reader = file.reader(io, &rbuf);
            var fr = &reader.interface;
            const data = try fr.allocRemaining(alloc, .unlimited);

            var list = try std.ArrayList(Entry).initCapacity(alloc, 4);

            var i: usize = 0;
            var begin: usize = 0;
            var end: usize = 0;
            while (i < data.len) {
                begin = i;
                end = i;
                while (i < data.len) {
                    if (data[i] == ' ') {
                        end = i;
                        break;
                    }
                    i+=1;
                }
                const id = stringToNum(data[begin..end]);
                begin = end+1;
                end = begin+32;
                //testPrint("hash begin {d}: end {d}\n", .{begin, end});
                const hash = data[begin..end];
                begin = end+1;
                i = begin;
                while (i < data.len) {
                    if (data[i] == '\n') {
                        end = i;
                        i+=1;
                        break;
                    }
                    i+=1;
                }
                //testPrint("name begin {d}: end {d}\n", .{begin, end});
                const name = data[begin..end];
                //testPrint("id: {d}\nhash: {s}\nname: {s}\n", .{id, hash, name});
                try list.append(alloc, .{ .id = id, .hash = hash, .path = name });
            }
            return list;
        }
    };
    const Changes = struct {
        const Entry = struct {
            path: []const u8,
            id: usize,
            action: Action,
        };
        const Action = enum(u8) {
            ADD,
            RENAME,
            DELETE,
        };
        fn getChangesFile(io: Io) !Io.File {
            return getOrCreateFile(io, "changes.txt");
        }
        fn addSong(io: Io, id: usize) !void {
            var file = try getChangesFile(io);
            defer file.close(io);

            var wbuf: [1024]u8 = undefined;
            var writer = file.writer(io, &wbuf);
            var fw = &writer.interface;
            try writer.seekTo(try file.length(io));

            try fw.print("add id:{d}\n", .{id});
            try fw.flush();
        }
        fn getChanges(io: Io, alloc: std.mem.Allocator) !std.ArrayList(Entry) {
            var file = try getChangesFile(io);
            defer file.close(io);

            var list = try std.ArrayList(Entry).initCapacity(alloc, 4);
            const table = try MusicTable.parseMusicTableFile(io, alloc);
            // defer table.deinit(alloc);

            var it = try fileToToken(io, file, alloc);
            while (it.next()) |e| {
                const split = std.mem.cutScalar(u8, e, ' ');
                const split1 = std.mem.cutScalar(u8, e, ':');
                if (eql(split.?.@"0", "add")) {
                    const id = stringToNum(split1.?.@"1");
                    try list.append(alloc, .{ .action = .ADD, .path = table.items[id-1].path, .id = id });
                } else if (eql(split.?.@"0", "rename")) {
                    
                }
            }
            return list;
        }
    };
    
    const testing = struct {

    };
};

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

    switch (args.len) {
        0 => {
            try Networks.Client.start(io);
        },
        1 => {
            if (eql(args[0], "sync")) {
                try Networks.Client.start(io);
            } else if (eql(args[0], "sync_new_key")) {
                try FileManager.KeyStuff.writeKey(io, try FileManager.KeyStuff.generateNewKey(io));
            }
        },
        2 => {
            if (eql(args[0], "sync")) {
                if (args[1].len != 8) return error.KeyWrongLength;
                var key: [8]u8 = undefined;
                @memcpy(&key, args[1][0..8]);
                try FileManager.KeyStuff.writeKey(io, key);
                clientState.key = key;

                try Networks.Client.start(io);
            } else if (eql(args[0], "add")) {
                testPrint("add command not implemented\n", .{});
            } else if (eql(args[0], "rename")) {
                testPrint("rename command not implemented\n", .{});
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
test "FileManaging" {
    const io = std.testing.io;
    //const alloc = std.testing.allocator;
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    //try FileManager.testing.reset(io);

    try FileManager.MusicPath.addPath(io, Io.Dir.cwd(),"music/album");
    try FileManager.MusicPath.addPath(io, Io.Dir.cwd(), "music/c.mp3");
    const list = try FileManager.Changes.getChanges(io, gpa.allocator());
    for (list.items) |e| {
        testPrint("{any}: {s}\n", .{e.action, e.path});
    }

    //try FileManager.MusicPath.deletePath(io, "music/album");

    // try FileManager.testing.readMusicFoldersCache(io);
    // try FileManager.testing.readMusicIds(io);
}
