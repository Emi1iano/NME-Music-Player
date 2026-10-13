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

//TODO: add something like this
//  sendResolved(.{"FILE", file.content, "STOP"});
//  sendResolved(.{"DELETE", id, "STOP"});
//
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
                        if (eql(message.data[1..], "FILE")) action = .ADD else if (eql(message.data[1..], "RENAME")) action = .RENAME else if (eql(message.data[1..], "DELETE")) action = .DELETE else if (eql(message.data[1..], "STOP")) switch (action) {
                            .ADD => {
                                try Syncing.recieveFile(io, &writer.writer);
                                _ = writer.writer.consumeAll();
                                action = undefined;
                            },
                            .RENAME => {
                                try Syncing.recieveRename(io, writer.writer.buffered());
                                _ = writer.writer.consumeAll();
                                action = undefined;
                            },
                            .DELETE => {
                                testPrint("id to be deleted {s}\n", .{writer.written()});
                                _ = try FileManager.MusicTable.deleteEntryWithId(io, stringToNum(writer.written()));
                                //entry points into random memory
                                try FileManager.deleteSongAbsolute(io, globalStorage.path);
                                _ = writer.writer.consumeAll();
                                action = undefined;
                            },
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
            // fn send(io: Io, action: FileManager.Changes.Action, buf: []const u8) !void {
            //     switch (action) {
            //         .ADD =>{},
            //         .RENAME => {},
            //         .DELETE => {},
            //     }
            // }
            // recieve(.type, buf) {
            //      switch (type) {
            //          .add =>{}
            //          .delete => {}
            //          .rename ={}
            // }
            // }
            fn sync(io: Io) !void {
                var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer gpa.deinit();

                const list = try FileManager.Changes.getChanges(io, gpa.allocator());
                for (list.items) |e| {
                    switch (e.action) {
                        .ADD => {
                            testPrint("{any}: {s}\n", .{ e.action, std.fs.path.basename(e.path) });
                            try sendFile(io, e);
                            try io.sleep(.fromMicroseconds(500), .awake);
                        },
                        .RENAME => {
                            try sendRename(io, e);
                        },
                        .DELETE => {
                            //TODO: Fix this to show the correct path after deletion
                            testPrint("{any}: {s}\n", .{ e.action, std.fs.path.basename(e.path) });
                            try sendDeleteFile(io, e);
                        },
                    }
                }
                testPrint("DONE SENDING STUFF\n", .{});
                try FileManager.Changes.clearChanges(io);
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

                var rbuf: [1024 * 4]u8 = undefined;
                var fr = file.reader(io, &rbuf);
                var reader = &fr.interface;
                const data = try reader.allocRemaining(gpa.allocator(), .unlimited);
                var buufferedr = Io.Reader.fixed(data);

                switch (clientState.cliendMode) {
                    .P2P => {
                        var senddata: [1024]u8 = undefined;
                        senddata[0] = ClientCode.getByte(.DATA)[0];

                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "FILE");
                        const header = try std.fmt.bufPrint(senddata[1..], "{d:0>8}{d:0>8}{s}{d:0>8}", .{ id, basename.len, basename, data.len });
                        testPrint("file header: {s}\n", .{header});
                        try clientState.sendResolved(io, senddata[0 .. header.len + 1]);

                        var sent: usize = 0;
                        while (true) {
                            const d = buufferedr.take(1023) catch buufferedr.buffered();
                            @memcpy(senddata[1 .. d.len + 1], d);
                            try clientState.sendResolved(io, senddata[0 .. d.len + 1]);
                            sent += 1;
                            if (sent % 16 == 0) try io.sleep(.fromMilliseconds(1), .awake);
                            if (d.len != 1023) break;
                        }
                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "STOP");
                    },
                    .Relay => {
                        var senddata: [1024]u8 = undefined;
                        const header = try std.fmt.bufPrint(senddata[0..], "{s}{s}{s}", .{ ClientCode.getByte(.RELAY), clientState.key, ClientCode.getByte(.DATA) });

                        @memcpy(senddata[header.len .. header.len + 4], "FILE");
                        try clientState.sendResolved(io, senddata[0 .. header.len + 4]);

                        const fheader = try std.fmt.bufPrint(senddata[header.len..], "{d:0>8}{d:0>8}{s}{d:0>8}", .{ id, basename.len, basename, data.len });
                        testPrint("file header: {s}\n", .{fheader});
                        try clientState.sendResolved(io, senddata[0 .. header.len + fheader.len]);

                        var sent: usize = 0;
                        while (true) {
                            const d = buufferedr.take(1024 - header.len) catch buufferedr.buffered();
                            @memcpy(senddata[header.len .. header.len + d.len], d);
                            try clientState.sendResolved(io, senddata[0 .. header.len + d.len]);
                            sent += 1;
                            if (sent % 16 == 0) try io.sleep(.fromMilliseconds(1), .awake);
                            if (d.len != 1024 - header.len) break;
                        }

                        @memcpy(senddata[header.len .. header.len + 4], "STOP");
                        try clientState.sendResolved(io, senddata[0 .. header.len + 4]);
                    },
                }
            }
            fn recieveFile(io: Io, writer: *Io.Writer) !void {
                //TODO: implement something like this
                // const r = Io.Reader.fixed(writer.buffered());
                // r.take(8)
                const id = stringToNum(writer.buffered()[0..8]);
                const name_len = stringToNum(writer.buffered()[8..16]);
                const name = writer.buffered()[16 .. 16 + name_len];
                const content_len = stringToNum(writer.buffered()[16 + name_len .. 24 + name_len]);
                if (content_len != writer.buffered().len-24+name_len) {
                    testPrint("Mismatched Lengths: {d}, {d}", .{content_len, writer.buffered().len-24+name_len});
                } 
                const content = writer.buffered()[24 + name_len .. 24 + name_len + content_len];

                testPrint("adding file {s} with id: {d} len: {d}\n", .{ name, id, content_len });

                var dir = try FileManager.getMusicDir(io);
                defer dir.close(io);

                var file = try dir.createFile(io, name, .{ .read = true });

                var wbuf: [1024 * 4]u8 = undefined;
                var fwriter = file.writer(io, &wbuf);
                var fw = &fwriter.interface;

                try fw.writeAll(content);
                try fw.flush();

                file.close(io);
                _ = try FileManager.MusicTable.addEntryWithId(io, dir, name, id);
            }
            fn sendDeleteFile(io: Io, entry: FileManager.Changes.Entry) !void {
                switch (clientState.cliendMode) {
                    .P2P => {
                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "DELETE");
                        var data: [33]u8 = undefined;
                        const senddata = try std.fmt.bufPrint(data[0..], "{s}{d}", .{ ClientCode.getByte(.DATA), entry.id });
                        try clientState.sendResolved(io, senddata);
                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "STOP");
                    },
                    .Relay => {
                        var senddata: [42]u8 = undefined;
                        const header = try std.fmt.bufPrint(senddata[0..], "{s}{s}{s}", .{ ClientCode.getByte(.RELAY), clientState.key, ClientCode.getByte(.DATA) });
                        const header1 = try std.fmt.bufPrint(senddata[header.len..], "DELETE", .{});
                        try clientState.sendResolved(io, senddata[0 .. header.len + header1.len]);
                        const data = try std.fmt.bufPrint(senddata[header.len..], "{d}", .{entry.id});
                        try clientState.sendResolved(io, senddata[0 .. header.len + data.len]);
                        const footer = try std.fmt.bufPrint(senddata[header.len..], "STOP", .{});
                        try clientState.sendResolved(io, senddata[0 .. header.len + footer.len]);
                    },
                }
            }
            fn sendRename(io: Io, entry: FileManager.Changes.Entry) !void {
                switch (clientState.cliendMode) {
                    .P2P => {
                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "RENAME");
                        var data: [256]u8 = undefined;
                        const senddata = try std.fmt.bufPrint(data[0..], "{s}{d} {s}", .{ ClientCode.getByte(.DATA), entry.id, std.fs.path.basename(entry.path) });
                        try clientState.sendResolved(io, senddata);
                        try clientState.sendResolved(io, ClientCode.getByte(.DATA) ++ "STOP");
                    },
                    .Relay => {
                        var senddata: [42]u8 = undefined;
                        const header = try std.fmt.bufPrint(senddata[0..], "{s}{s}{s}", .{ ClientCode.getByte(.RELAY), clientState.key, ClientCode.getByte(.DATA) });
                        const header1 = try std.fmt.bufPrint(senddata[header.len..], "RENAME", .{});
                        try clientState.sendResolved(io, senddata[0 .. header.len + header1.len]);
                        const data = try std.fmt.bufPrint(senddata[header.len..], "{d} {s}", .{ entry.id, std.fs.path.basename(entry.path) });
                        try clientState.sendResolved(io, senddata[0 .. header.len + data.len]);
                        const footer = try std.fmt.bufPrint(senddata[header.len..], "STOP", .{});
                        try clientState.sendResolved(io, senddata[0 .. header.len + footer.len]);
                    },
                }
            }
            fn recieveRename(io: Io, buf: []const u8) !void {
                var r = Io.Reader.fixed(buf);
                const temp = try r.takeDelimiter(' ');
                const id = stringToNum(temp.?);
                const new = r.buffered();
                testPrint("renaming: id:{d} to {s}", .{ id, new });

                var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer gpa.deinit();
                const list = try FileManager.MusicTable.parseMusicTableFile(io, gpa.allocator());
                const old = list.items[id - 1].path;

                try FileManager.renameFile(io, old, new);
                _ = try FileManager.MusicTable.updateRename(io, old, new);
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

const GlobalStorage = struct {
    alloc: std.mem.Allocator,
    path: []const u8 = undefined,

    fn init(alloc: std.mem.Allocator) GlobalStorage {
        return .{ .alloc = alloc };
    }
};
var globalStorage: GlobalStorage = undefined;
const FileManager = struct {
    fn getAppDir(io: Io) !Io.Dir {
        const app_dir_name = if (TESTING) "testing/" ++ app_directory else app_directory;
        const cwd = std.Io.Dir.cwd();

        return cwd.openDir(io, app_dir_name, .{}) catch try cwd.createDirPathOpen(io, app_dir_name, .{});
    }
    fn getMusicDir(io: Io) !Io.Dir {
        const music_dir_name = "music";
        const app_dir = try getAppDir(io);
        defer app_dir.close(io);

        return app_dir.openDir(io, music_dir_name, .{}) catch try app_dir.createDirPathOpen(io, music_dir_name, .{});
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
    //relative to app/music dir
    fn deleteSongAbsolute(io: Io, path: []const u8) !void {
        testPrint("PATH TO BE DELETED: {s}\n", .{path});
        try Io.Dir.deleteFileAbsolute(io, path);
    }
    fn deleteSongRelative(io: Io, path: []const u8) !void {
        testPrint("PATH TO BE DELETED: {s}\n", .{path});
        var music_dir = try getMusicDir(io);
        defer music_dir.close(io);
        try music_dir.deleteFile(io, path);
    }
    fn isFile(path: []const u8) bool {
        const basename = std.fs.path.basename(path);
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
    //old can be relative to app/music or absolute
    //needs the file extension to be included
    fn renameFile(io: Io, old: []const u8, new: []const u8) !void {
        const dir = if (std.fs.path.isAbsolute(old)) blk: {
            const dir_path = std.fs.path.dirname(old);
            break :blk try Io.Dir.openDirAbsolute(io, dir_path.?, .{});
        } else blk: {
            break :blk try getMusicDir(io);
        };
        dir.renamePreserve(std.fs.path.basename(old), dir, new, io) catch |err| switch (err) {
            error.FileNotFound => {
                testPrint("File {s} not found.\n", .{std.fs.path.basename(old)});
            },
            error.PathAlreadyExists => {
                testPrint("Existing {s} already found.\n", .{new});
                return err;
            },
            else => return err,
        };
    }
    const Commands = struct {
        const Data = struct {
            path: []const u8,
            object: Object,

            fn init(io: Io, path: []const u8) !Data {
                const absolute = std.fs.path.isAbsolute(path);
                const file: Object = if (isFile(path)) blk: {
                    if (absolute) {
                        break :blk Object{ .file = try Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_only }) };
                    } else {
                        const music_dir = try getMusicDir(io);
                        defer music_dir.close(io);

                        break :blk Object{ .file = try music_dir.openFile(io, path, .{ .mode = .read_only }) };
                    }
                } else blk: {
                    if (absolute) {
                        break :blk Object{ .dir = try Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) };
                    } else {
                        const music_dir = try getMusicDir(io);
                        defer music_dir.close(io);
                        break :blk Object{ .dir = try music_dir.openDir(io, path, .{ .iterate = true }) };
                    }
                };
                return .{
                    .path = path,
                    .object = file,
                };
            }
            fn deinit(self: *Data, io: Io) void {
                switch (self.*.object) {
                    .file => {
                        self.object.file.close(io);
                    },
                    .dir => {
                        self.object.dir.close(io);
                    },
                }
            }
            const Object = union(enum) {
                file: Io.File,
                dir: Io.Dir,
            };
        };

        //path can be absolute or relative to app/music
        fn addPathTableChange(io: Io, path: []const u8) !void {
            if (path.len == 0) return error.InvalidPath;
            var data: Data = try .init(io, path);
            defer data.deinit(io);
            //TODO: make it so if one fails the others dont commit
            try MusicPath.addPathToFile(io, path);
            try MusicTable.temp.scanPathAndAddChange(io, data);
        }
        //old can be relative to app/music or absolute
        //needs the file extension to be included
        fn rename(io: Io, old: []const u8, new: []const u8) !void {
            if (!isFile(old)) return error.NotAFile;
            if (!isSong(old)) return error.NotASong;
            if (!eql(std.fs.path.extension(old), std.fs.path.extension(new))) return error.MismatchExtensions;

            // May exist in music paths
            try MusicPath.updateRename(io, old, new);
            // If not in music table return err
            const id = MusicTable.updateRename(io, old, new) catch |err| switch (err) {
                error.FileNotFound => {
                    testPrint("File {s} not found\n", .{old});
                    return;
                },
                error.FileNotFoundInTable => {
                    testPrint("File {s} not found in music table\n", .{old});
                    return;
                },
                else => return err,
            };
            try Changes.addRename(io, id);
            renameFile(io, old, new) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    return;
                },
                else => return err,
            };
        }
        fn renameTesting(io: Io, old: []const u8, new: []const u8) !void {
            if (!isFile(old)) return error.NotAFile;
            if (!isSong(old)) return error.NotASong;
            if (!eql(std.fs.path.extension(old), std.fs.path.extension(new))) return error.MismatchExtensions;

            // May exist in music paths
            try MusicPath.updateRename(io, old, new);
            // If not in music table return err
            const id = try MusicTable.updateRename(io, old, new);
            try Changes.addRename(io, id);
            try renameFile(io, old, new);
        }
    };
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
            while (it.next()) |entry| {
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
            while (it.next()) |entry| {
                if (!eql(path, entry)) {
                    try wf.writeAll(entry);
                    try wf.writeByte('\n');
                }
            }
            try wf.flush();
        }
        fn addPathAndScan(io: Io, cwd: Io.Dir, path: []const u8) !void {
            try addPathToFile(io, path);
            const basename = std.fs.path.basename(path);
            for (1..basename.len) |i| {
                if (basename[basename.len - i] == '.') {
                    const num = try MusicTable.addEntry(io, cwd, path);
                    if (num == 0) return;
                    try Changes.addSong(io, num);
                    return;
                }
            }
            try scanFolder(io, cwd, path);
        }
        fn scanFolder(io: Io, cwd: Io.Dir, path: []const u8) !void {
            const dir = try cwd.openDir(io, path, .{ .iterate = true });
            defer dir.close(io);

            var it = dir.iterate();

            while (it.next(io)) |entry| {
                if (entry == null) break;
                switch (entry.?.kind) {
                    .file => {
                        const num = try MusicTable.addEntry(io, dir, entry.?.name);
                        if (num == 0) continue;
                        try Changes.addSong(io, num);
                    },
                    .directory => {
                        try scanFolder(io, dir, entry.?.name);
                    },
                    else => {},
                }
            } else |_| {}
        }
        fn rescanFolders(io: Io) !void {
            var file = try getMusicPathsFile(io);
            defer file.close(io);

            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var it = try fileToToken(io, file, gpa.allocator());
            testPrint("Rescanning: {s}\n", .{"app/music"});
            try scanFolder(io, try FileManager.getMusicDir(io), "");
            while (it.next()) |e| {
                testPrint("Rescanning: {s}\n", .{e});
                try addPathAndScan(io, Io.Dir.cwd(), e);
            }
        }
        fn getPaths(io: Io, alloc: std.mem.Allocator) !std.mem.TokenIterator(u8, .any) {
            var file = try getMusicPathsFile(io);
            defer file.close(io);

            return try fileToToken(io, file, alloc);
            // var rbuf: [1024]u8 = undefined;
            // var reader = file.reader(io, &rbuf);
            // var r = &reader.interface;

            // const data = try r.allocRemaining(alloc, .unlimited);

        }
        fn parsePathsFile(io: Io, alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
            var file = try getMusicPathsFile(io);
            defer file.close(io);

            var rbuf: [1024]u8 = undefined;
            var reader = file.reader(io, &rbuf);
            var fr = &reader.interface;
            const data = try fr.allocRemaining(alloc, .unlimited);
            var r = Io.Reader.fixed(data);

            var list = try std.ArrayList([]const u8).initCapacity(alloc, 4);
            while (r.takeDelimiter('\n')) |line| {
                if (line == null) break;
                try list.append(alloc, line.?);
            } else |_| {}
            return list;
        }
        fn updateRename(io: Io, old: []const u8, new: []const u8) !void {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var list = try parsePathsFile(io, gpa.allocator());
            if (std.fs.path.isAbsolute(old)) {
                for (list.items, 0..) |*path, i| {
                    if (eql(path.*, old)) {
                        var new_path: [256]u8 = undefined;
                        const old_path = std.fs.path.dirname(old);
                        @memcpy(new_path[0..old_path.?.len], old_path.?);
                        @memcpy(new_path[old_path.?.len .. old_path.?.len + new.len], new);
                        list.items[i] = new_path[0 .. old_path.?.len + new.len];
                        break;
                    }
                }
            } else {
                for (list.items, 0..) |*path, i| {
                    if (eql(path.*, old)) {
                        //TODO make work with album/c.mp3
                        list.items[i] = new;
                        break;
                    }
                }
            }

            var file = try getMusicPathsFile(io);
            var buf: [256]u8 = undefined;
            var writer = file.writer(io, &buf);
            var w = &writer.interface;
            for (list.items) |line| {
                try w.print("{s}\n", .{line});
            }
            try writer.end();
        }
        fn clearMusicPaths(io: Io) !void {
            var file = try getMusicPathsFile(io);
            defer file.close(io);

            var writer = file.writer(io, &.{});
            try writer.end();
        }
    };
    const MusicTable = struct {
        const Entry = struct {
            id: usize,
            hash: []const u8,
            path: []const u8,
        };
        const temp = struct {
            //TODO: maybe add strcut that wraps a list and alloc together
            fn addFileEntryAndCommit(io: Io, file: Io.File, table: *std.ArrayList(Entry), alloc: std.mem.Allocator) !void {
                const id = table.items.len + 1;
                const hash = try hashFile(io, file);
                var path: [256]u8 = undefined;
                const path_len = try file.realPath(io, &path);
                if (!isSong(path[0..path_len])) return error.NotASong;
                for (table.items) |e| {
                    if (eql(e.hash, &hash)) {
                        //TODO: make it print relative path
                        testPrint("\x1b[34mSong {s} already included\x1b[0m\n", .{std.fs.path.basename(path[0..path_len])});
                        return;
                    }
                }
                try table.append(alloc, .{ .id = id, .hash = try alloc.dupe(u8, &hash), .path = try alloc.dupe(u8, &path) });
                { // Add to Music Table
                    //TODO: open table file once and pass the writer
                    var tableFile = try getMusicTableFile(io);
                    defer tableFile.close(io);

                    var wBuf: [1024]u8 = undefined;
                    var writer = tableFile.writer(io, &wBuf);
                    var w = &writer.interface;

                    try writer.seekTo(try tableFile.length(io));
                    try w.print("{d} {s} {s}\n", .{ id, hash, path[0..path_len] });
                    try w.flush();
                }
                { // Add to Changes
                    try Changes.addSong(io, id);
                }
                testPrint("\x1b[32mAdded song: {s}\x1b[0m\n", .{std.fs.path.basename(path[0..path_len])});
            }
            fn dirRecurseAddFileEntry(io: Io, dir: Io.Dir, table: *std.ArrayList(Entry), alloc: std.mem.Allocator) !void {
                var it = dir.iterate();

                while (it.next(io)) |e| {
                    if (e == null) break;
                    switch (e.?.kind) {
                        .file => {
                            const file = try dir.openFile(io, e.?.name, .{ .mode = .read_only });
                            addFileEntryAndCommit(io, file, table, alloc) catch |err| switch (err) {
                                error.NotASong => {
                                    testPrint("\x1b[31mNot a song: {s}\x1b[0m\n", .{e.?.name});
                                },
                                else => return err,
                            };
                        },
                        .directory => {
                            const dir1 = try dir.openDir(io, e.?.name, .{ .iterate = true });
                            try dirRecurseAddFileEntry(io, dir1, table, alloc);
                        },
                        else => {},
                    }
                } else |_| {}
            }
            fn scanPathAndAddChange(io: Io, data: Commands.Data) !void {
                var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer gpa.deinit();
                const alloc = gpa.allocator();
                var table = try parseMusicTableFile(io, alloc); //open & close table once

                switch (data.object) {
                    .file => |file| {
                        temp.addFileEntryAndCommit(io, file, &table, alloc) catch |err| switch (err) {
                            error.NotASong => {
                                testPrint("\x1b[31mNot a song: {s}\x1b[0m\n", .{std.fs.path.basename(data.path)});
                            },
                            else => return err,
                        }; //open & close table once / open & close file
                    },
                    .dir => |dir| {
                        try temp.dirRecurseAddFileEntry(io, dir, &table, alloc);
                    },
                }
            }
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
                    testPrint("\x1b[34mSong {s} already included\x1b[0m\n", .{path});
                    return 0;
                }
            } else {
                var wbuf: [1024]u8 = undefined;
                var writer = file.writer(io, &wbuf);
                var fw = &writer.interface;
                try writer.seekTo(try file.length(io));
                try fw.print("{d} {s} {s}\n", .{ list.items.len + 1, hash, pathbuf[0..pathlen] });
                try fw.flush();
                testPrint("\x1b[32mAdded song: {s}\x1b[0m\n", .{path});
                return list.items.len + 1;
            }
        }
        fn addEntryWithId(io: Io, dir: Io.Dir, path: []const u8, id: usize) !void {
            //TODO: make sure id doesnt conflict with existing one
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
                    return;
                }
            } else {
                var wbuf: [1024]u8 = undefined;
                var writer = file.writer(io, &wbuf);
                var fw = &writer.interface;
                try writer.seekTo(try file.length(io));
                try fw.print("{d} {s} {s}\n", .{ id, hash, pathbuf[0..pathlen] });
                try fw.flush();
                testPrint("Added song: {s}\n", .{path});
                return;
            }
        }
        //relative to app/music dir
        fn deleteEntry(io: Io, path: []const u8) !Entry {
            var music_dir = try getMusicDir(io);
            defer music_dir.close(io);
            var song = try std.Io.Dir.openFile(music_dir, io, path, .{ .mode = .read_write });
            defer song.close(io);
            const hash = try hashFile(io, song);

            return deleteEntryWithHash(io, hash);
        }
        fn deleteEntryWithId(io: Io, id: usize) !Entry {
            var file = try getMusicTableFile(io);
            defer file.close(io);

            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            const list = try parseMusicTableFile(io, gpa.allocator());
            return deleteEntryWithHash(io, list.items[id - 1].hash[0..32].*);
        }
        fn deleteEntryWithHash(io: Io, hash: [32]u8) !Entry {
            var file = try getMusicTableFile(io);
            defer file.close(io);

            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var list = try parseMusicTableFile(io, gpa.allocator());
            var id: Entry = undefined;
            for (0..list.items.len) |i| {
                if (eql(&hash, list.items[i].hash)) {
                    testPrint("FOUND {s}\n", .{std.fs.path.basename(list.items[i].path)});
                    globalStorage.path = try globalStorage.alloc.dupe(u8, list.items[i].path);
                    const e = list.orderedRemove(i);
                    id = e;
                    break;
                }
            }
            {
                var wbuf: [1024]u8 = undefined;
                var writer = file.writer(io, &wbuf);
                var w = &writer.interface;

                for (list.items, 0..) |e, i| {
                    try w.print("{d} {s} {s}\n", .{ i + 1, e.hash, e.path });
                    try w.flush();
                }
                try writer.end();
            }
            return id;
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
            var r = Io.Reader.fixed(data);

            var list = try std.ArrayList(Entry).initCapacity(alloc, 4);
            while (true) {
                const id1 = try r.takeDelimiter(' ');
                if (id1 == null) break;
                const id = stringToNum(id1.?);
                const hash = try r.take(32);
                r.toss(1);
                const path = try r.takeDelimiter('\n');
                //testPrint("id: {d} hash: {x}\nname: {s}\n", .{ id, hash, path.? });
                try list.append(alloc, .{ .id = id, .hash = hash, .path = path.? });
            }
            return list;
        }
        fn updateRename(io: Io, old: []const u8, new: []const u8) !usize {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            var list = try parseMusicTableFile(io, gpa.allocator());
            var path_buf: [256]u8 = undefined;
            const absolute_path = if (std.fs.path.isAbsolute(old)) old else blk: {
                var music_dir = try getMusicDir(io);
                defer music_dir.close(io);

                const dir_path_len = try music_dir.realPathFile(io, old, &path_buf);
                break :blk path_buf[0..dir_path_len];
            };
            var result: usize = 0;
            for (list.items, 0..) |*e, i| {
                if (eql(e.*.path, absolute_path)) {
                    // var new_path_buf: [256]u8 = undefined;
                    const old_path = std.fs.path.dirname(absolute_path);
                    //const new_path = try std.fmt.bufPrint(&new_path_buf, "{s}\\{s}", .{ old_path.?, new });
                    const new_path = try std.fs.path.join(gpa.allocator(), &.{ old_path.?, new });
                    list.items[i].path = new_path;
                    result = list.items[i].id;
                    break;
                }
            } else {
                return error.FileNotFoundInTable;
            }
            var file = try getMusicTableFile(io);
            var buf: [256]u8 = undefined;
            var writer = file.writer(io, &buf);
            var w = &writer.interface;
            for (list.items) |e| {
                try w.print("{d} {s} {s}\n", .{ e.id, e.hash, e.path });
            }
            try writer.end();

            return result;
        }
        fn clearMusicTable(io: Io) !void {
            var file = try getMusicTableFile(io);
            defer file.close(io);

            var writer = file.writer(io, &.{});
            try writer.end();
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
        fn deleteSong(io: Io, id: usize) !void {
            var file = try getChangesFile(io);
            defer file.close(io);

            var wbuf: [1024]u8 = undefined;
            var writer = file.writer(io, &wbuf);
            var fw = &writer.interface;
            try writer.seekTo(try file.length(io));

            try fw.print("delete id:{d}\n", .{id});
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
                    try list.append(alloc, .{ .action = .ADD, .path = table.items[id - 1].path, .id = id });
                } else if (eql(split.?.@"0", "delete")) {
                    const id = stringToNum(split1.?.@"1");
                    try list.append(alloc, .{ .action = .DELETE, .path = table.items[id - 1].path, .id = id });
                } else if (eql(split.?.@"0", "rename")) {
                    const id = stringToNum(split1.?.@"1");
                    try list.append(alloc, .{ .action = .RENAME, .path = table.items[id - 1].path, .id = id });
                } else {
                    testPrint("change not implemented: \"{s}\"", .{split.?.@"0"});
                }
            }
            return list;
        }
        fn addRename(io: Io, id: usize) !void {
            var file = try getChangesFile(io);
            defer file.close(io);

            var wbuf: [1024]u8 = undefined;
            var writer = file.writer(io, &wbuf);
            var fw = &writer.interface;
            try writer.seekTo(try file.length(io));

            try fw.print("rename id:{d}\n", .{id});
            try fw.flush();
        }
        fn clearChanges(io: Io) !void {
            var file = try getChangesFile(io);
            defer file.close(io);

            var writer = file.writer(io, &.{});
            try writer.end();
        }
    };

    const testing = struct {
        fn resetCache(io: Io) !void {
            try Changes.clearChanges(io);
            try MusicTable.clearMusicTable(io);
            try MusicPath.clearMusicPaths(io);
        }
    };
    const idkMusicTable = struct {
        const Entry = struct {
            id: usize,
            hash: []const u8,
            path: []const u8,
        };
        fn somrthing(io: Io) !void {
            var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer gpa.deinit();

            const file = try getOrCreateFile(io, "musicTable.txt");

            var musicTable = try MyFile(Entry, "{d} {s}{s}", .{ @as(u8, ' '), 32, @as(u8, '\n') }).init(gpa.allocator(), file);
            try musicTable.parse(io);
            defer musicTable.deinit();
        }
    };
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
        fn deinit(self: *@This()) void {
            self.list.deinit();
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
    _ = io;
    var buf: [1024]u8 = undefined;
    const header = switch (clientState.cliendMode) {
        .P2P => try std.fmt.bufPrint(buf[0..], "{s}", .{ClientCode.getByte(code)}),
        .Relay => try std.fmt.bufPrint(buf[0..], "{s}{s}{s}", .{ ClientCode.getByte(.RELAY), clientState.key, ClientCode.getByte(code) }),
    };
    const typeinfo = @typeInfo(@TypeOf(args));
    const fields = typeinfo.@"struct".fields;

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
        while (r.seek < r.end) {
            const d = r.take(1024 - header.len) catch r.buffered();
            @memcpy(buf[header.len .. header.len + d.len], d);
            // try clientState.sendResolved(io, &buf);
            testPrint("{s}\n", .{buf[0 .. header.len + d.len]});
            if (d.len != 1024 - header.len) break;
        }
    }
}
pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    try start(init.io, args[1..]);
    _ = try FileManager.MusicTable.parseMusicTableFile(init.io, alloc);
    var file = try Io.Dir.cwd().openFile(init.io, "testing/app/musicTable.txt", .{ .mode = .read_write });
    defer file.close(init.io);

    //     var myfile = try MyFile(FileManager.MusicTable.Entry, "{d} {s}{s}\n", .{@as(u8, ' '), 32, @as(u8, '\n')}).init(alloc, file);
    //     defer myfile.deinit();
    //
    //     try myfile.parse(init.io);
    //     try myfile.printAll();
    //     try myfile.writeAll(init.io);
    // try MySend(init.io, ClientCode.DATA, .{ "hello world", "this is joe", "lets have a good time", "!!!" });
}
pub fn start(io: Io, args: []const [:0]const u8) !void {
    Networks.Client.acknowledged = false;
    clientState = .init(io);
    defer clientState.deinit(io);

    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    globalStorage = .init(gpa.allocator());

    switch (args.len) {
        0 => {
            try Networks.Client.start(io);
        },
        1 => {
            if (eql(args[0], "sync")) {
                try Networks.Client.start(io);
            } else if (eql(args[0], "sync_new_key")) {
                try FileManager.KeyStuff.writeKey(io, try FileManager.KeyStuff.generateNewKey(io));
            } else if (eql(args[0], "scan")) {
                try FileManager.MusicPath.rescanFolders(io);
            } else if (eql(args[0], "testreset")) {
                try FileManager.testing.resetCache(io);
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
                //FileManager.MusicPath.addPathAndScan(io, try FileManager.getMusicDir(io), args[1]);
                try FileManager.Commands.addPathTableChange(io, args[1]);
            } else if (eql(args[0], "delete")) {
                testPrint("DELETEING: {s}\n", .{args[1]});
                const entry = try FileManager.MusicTable.deleteEntry(io, args[1]);
                try FileManager.Changes.deleteSong(io, entry.id);
                //std.fs.path.isAbsolute(path: []const u8)
                try FileManager.deleteSongRelative(io, args[1]);
            }
        },
        3 => {
            if (eql(args[0], "rename")) {
                try FileManager.Commands.rename(io, args[1], args[2]);
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
// test "FileManaging" {
//     const io = std.testing.io;
//     var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     defer gpa.deinit();

//     try FileManager.MusicPath.addPathAndScan(io, Io.Dir.cwd(),"music/album");
//     try FileManager.MusicPath.addPathAndScan(io, Io.Dir.cwd(), "music/c.mp3");
//     const list = try FileManager.Changes.getChanges(io, gpa.allocator());
//     for (list.items) |e| {
//         testPrint("{any}: {s}\n", .{e.action, e.path});
//     }
// }
test "Add Command" {
    const io = std.testing.io;
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();

    try FileManager.testing.resetCache(io);
    var it = try FileManager.MusicPath.getPaths(io, gpa.allocator());
    try std.testing.expectEqual(null, it.next());

    try std.testing.expectError(error.InvalidPath, FileManager.Commands.addPathTableChange(io, ""));
    try FileManager.Commands.addPathTableChange(io, "c.mp3");
    it = try FileManager.MusicPath.getPaths(io, gpa.allocator());
    try std.testing.expectEqualStrings("c.mp3", it.next().?);
    try std.testing.expectEqual(null, it.next());

    try FileManager.Commands.addPathTableChange(io, "c.mp3");
    it = try FileManager.MusicPath.getPaths(io, gpa.allocator());
    try std.testing.expectEqualStrings("c.mp3", it.next().?);
    try std.testing.expectEqual(null, it.next());

    try FileManager.Commands.addPathTableChange(io, "F:/Code/Zig/NME-Music-Player/backend/NetworksButBetter/backend/src/music");
    it = try FileManager.MusicPath.getPaths(io, gpa.allocator());
    try std.testing.expectEqualStrings("c.mp3", it.next().?);
    try std.testing.expectEqualStrings("F:/Code/Zig/NME-Music-Player/backend/NetworksButBetter/backend/src/music", it.next().?);
    try std.testing.expectEqual(null, it.next());
}
test "Rename Command" {
    const io = std.testing.io;
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();

    try FileManager.testing.resetCache(io);

    try std.testing.expectError(error.NotAFile, FileManager.Commands.renameTesting(io, "music", "song.mp3"));
    try std.testing.expectError(error.MismatchExtensions, FileManager.Commands.renameTesting(io, "album/nice.mp3", "song.opus"));
    try FileManager.Commands.addPathTableChange(io, "c.mp3");
    try std.testing.expectError(error.FileNotFound, FileManager.Commands.renameTesting(io, "a.mp3", "test.mp3"));
    try std.testing.expectError(error.FileNotFoundInTable, FileManager.Commands.renameTesting(io, "b.mp3", "a.mp3"));
    try std.testing.expectError(error.PathAlreadyExists, FileManager.Commands.renameTesting(io, "c.mp3", "b.mp3"));
    try FileManager.Commands.addPathTableChange(io, "b.mp3");
}
test "Delete Command" {}
test "Update Command" {}
