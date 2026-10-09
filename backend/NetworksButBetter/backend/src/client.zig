const std = @import("std");
const net = std.Io.net;
const builtin = @import("builtin");
const ClientCode = @import("server.zig").Networks.ClientCode;
const sync = @import("sync.zig");

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

        fn init(io: Io) !ClientState {
            const server_ip = try getServerIp(io);
            return .{
                .client_socket = try getClientSocket(io),
                .server_ip = server_ip,
                .resolved_ip = server_ip,
                .key = try FileManager.KeyStuff.getKey(io),
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
        /// "server.txt" in the working directory ("a.b.c.d:port") overrides the default.
        fn getServerIp(io: Io) !net.IpAddress {
            var buf: [64]u8 = undefined;
            if (Config.read(io, "server.txt", &buf)) |text| {
                if (std.mem.lastIndexOfScalar(u8, text, ':')) |i| {
                    const port = std.fmt.parseInt(u16, text[i + 1 ..], 10) catch return error.BadServerAddress;
                    return try std.Io.net.IpAddress.parse(text[0..i], port);
                }
                return error.BadServerAddress;
            }
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
            defer {
                stopListener(io);
                GlobalListeningThread.join();
            }

            try waitForOtherClient(io);
            try punching(io);
            if (clientState.should_disconnect) return error.Disconnected;
            if (CHAT_MODE) {
                try clientStart(io);
            } else {
                try LibrarySync.run(io);
            }
        }
        /// Sends the key to the server every 2s (which also keeps the server
        /// from timing us out) until it pairs us with the other client.
        fn waitForOtherClient(io: Io) !void {
            Status.set(io, "Waiting for your other device to sync with key {s}...", .{clientState.key});
            const started = Io.Timestamp.now(io, .awake);
            while (!clientState.recieved_inital_info) {
                if (clientState.should_disconnect) return error.Disconnected;
                if (started.untilNow(io, .awake).toSeconds() >= 120) {
                    Status.set(io, "No other device synced with key {s}", .{clientState.key});
                    return error.NoOtherClient;
                }
                sendInitialServerMessage(io) catch {};
                for (0..20) |_| {
                    if (clientState.recieved_inital_info or clientState.should_disconnect) break;
                    try io.sleep(.fromMilliseconds(100), .awake);
                }
            }
        }
        /// Tells the other client we're leaving, then wakes our own listener
        /// (blocked in receive) with a TERMINATE sent to ourselves.
        fn stopListener(io: Io) void {
            if (clientState.recieved_inital_info) {
                for (0..3) |_| sendTerminate(io) catch {};
            }
            var self = Io.net.IpAddress.parse("127.0.0.1", clientState.client_socket.address.getPort()) catch return;
            clientState.client_socket.send(io, &self, &ClientCode.getByte(.TERMINATE)) catch {};
        }
        fn sendTerminate(io: Io) !void {
            if (clientState.cliendMode == .P2P) {
                try clientState.sendResolved(io, &ClientCode.getByte(.TERMINATE));
            } else {
                try clientState.sendResolved(io, &(ClientCode.getByte(.RELAY) ++ clientState.key ++ ClientCode.getByte(.TERMINATE)));
            }
        }
        /// Sends `payload` as a DATA message, wrapped for the relay if needed.
        fn sendData(io: Io, payload: []const u8) !void {
            var buf: [1024]u8 = undefined;
            var n: usize = 0;
            if (clientState.cliendMode == .Relay) {
                buf[0] = ClientCode.getByte(.RELAY)[0];
                @memcpy(buf[1..9], &clientState.key);
                n = 9;
            }
            buf[n] = ClientCode.getByte(.DATA)[0];
            @memcpy(buf[n + 1 ..][0..payload.len], payload);
            try clientState.sendResolved(io, buf[0 .. n + 1 + payload.len]);
        }
        /// Packets from the other client come from its local or public address,
        /// or from the server when relaying.
        fn isOtherClient(from: net.IpAddress) bool {
            if (clientState.cliendMode == .Relay) return from.eql(&clientState.server_ip);
            if (clientState.reciever_local_ip) |ip| if (from.eql(&ip)) return true;
            if (clientState.reciever_public_ip) |ip| if (from.eql(&ip)) return true;
            return from.eql(&clientState.resolved_ip);
        }
        fn listen(io: Io) void {
            var buffer: [1024]u8 = undefined;

            while (true) {
                // On Windows an ICMP "port unreachable" from an earlier send shows
                // up as a receive error; it isn't fatal, so keep listening.
                const message = clientState.client_socket.receive(io, &buffer) catch |err| switch (err) {
                    error.Canceled => return,
                    else => continue,
                };
                if (message.data.len == 0) continue;
                if (clientState.recieved_inital_info and isOtherClient(message.from)) LibrarySync.heardFromOtherClient(io);
                const code = ClientCode.getCode(message.data[0]);

                switch (code) {
                    .INITIAL => {
                        if (clientState.recieved_inital_info) {
                            std.debug.print("Already initalized\n", .{});
                            continue;
                        }
                        if (message.data.len == 13 and message.from.eql(&clientState.server_ip)) {
                            clientState.parseInitialResponse(message.data[1..13].*) catch continue;
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
                        if (!clientState.recieved_inital_info) continue;
                        if (clientState.reciever_local_ip) |ip| {
                            clientState.client_socket.send(io, &ip, ClientCode.getByte(.ACK) ++ "LOCAL IP") catch {};
                        } else {
                            if (message.data.len >= 9 and eql(message.data[1..9], "LOCAL IP")) {
                                clientState.reciever_local_ip = message.from;
                            }
                        }
                        clientState.client_socket.send(io, &clientState.reciever_public_ip.?, ClientCode.getByte(.ACK) ++ "PUBLIC IP") catch {};
                    },
                    .ACK => {
                        testPrint("ACK: {s}\n", .{message.data[1..]});
                        if (acknowledged or !clientState.recieved_inital_info) continue;
                        if (message.data.len >= 9 and std.mem.eql(u8, message.data[1..9], "LOCAL IP") and clientState.reciever_local_ip != null) {
                            std.debug.print("USE LOCAL IP\n", .{});
                            clientState.resolved_ip = clientState.reciever_local_ip.?;
                        } else if (message.data.len >= 10 and std.mem.eql(u8, message.data[1..10], "PUBLIC IP")) {
                            std.debug.print("USE PUBLIC IP\n", .{});
                            clientState.resolved_ip = clientState.reciever_public_ip.?;
                        }
                        acknowledged = true;
                    },
                    .DATA => {
                        if (message.data.len < 2 or !isOtherClient(message.from)) continue;
                        LibrarySync.onData(io, message.data[1..]);
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

/// Exchanges music libraries with the connected client (see sync.zig).
/// `run` drives it from the main thread; the listener thread calls `onData`.
const LibrarySync = struct {
    const gpa = std.heap.smp_allocator;
    const peer_timeout_s = 20;

    /// A blob (song list or song) being downloaded.
    const Fetch = struct {
        id: u32,
        file: ?Io.File,
        total: ?u32 = null,
        got: std.DynamicBitSetUnmanaged = .{},
        /// Chunks asked for this round that haven't arrived yet.
        pending: usize = 0,
        last_data: ?Io.Timestamp = null,
        /// Song list contents (when `file` is null).
        list: []u8 = &.{},
        list_len: usize = 0,

        fn deinit(f: *Fetch) void {
            f.got.deinit(gpa);
            gpa.free(f.list);
        }
    };

    // Shared with the listener thread; guarded by `state_lock`.
    var state_lock: Io.Mutex = .init;
    var fetch: ?Fetch = null;
    var peer_done: bool = false;
    var last_heard: Io.Timestamp = undefined;

    // Set before connecting, read-only afterwards.
    var music_dir: Io.Dir = undefined;
    var mine: sync.Library = undefined;
    var ready: bool = false;

    // Listener thread only.
    var served: std.DynamicBitSetUnmanaged = .{};
    var reader: ?struct { id: u32, file: Io.File } = null;

    // Main thread only.
    var window: usize = 128;

    fn run(io: Io) !void {
        Status.set(io, "Connected - exchanging song lists...", .{});
        heardFromOtherClient(io); // pairing may have taken a while

        var theirs = try fetchBlob(io, sync.list_id, null);
        defer theirs.deinit();
        const list = theirs.list[0..theirs.list_len];

        var skip_buf: [64 * 1024]u8 = undefined;
        const skip = Config.read(io, "skip.txt", &skip_buf) orelse "";

        // Songs we don't have, by their index in the other client's list.
        var want: std.ArrayList(struct { id: u32, path: []const u8 }) = .empty;
        defer want.deinit(gpa);
        var it = std.mem.splitScalar(u8, list, '\n');
        var id: u32 = 0;
        while (it.next()) |path| : (id += 1) {
            if (!sync.isSafeRelPath(path) or !sync.isAudio(path) or mine.contains(path)) continue;
            if (Config.hasLine(skip, path)) continue;
            try want.append(gpa, .{ .id = id, .path = path });
        }

        for (want.items, 1..) |w, i| {
            Status.set(io, "Downloading {d}/{d}: {s}", .{ i, want.items.len, w.path });
            try fetchFile(io, w.id, w.path);
        }

        Status.set(io, "Finishing up...", .{});
        try finish(io);
        Status.set(io, "Synced: received {d}, sent {d} song(s)", .{ want.items.len, served.count() });
    }

    /// Opens the music folder and lists our songs. Called before connecting
    /// so the other client can download our list as soon as we're paired.
    fn prepare(io: Io) !void {
        state_lock.lockUncancelable(io);
        fetch = null;
        peer_done = false;
        last_heard = Io.Timestamp.now(io, .awake);
        state_lock.unlock(io);
        window = 128;
        reader = null;

        music_dir = try Config.openMusicDir(io);
        errdefer music_dir.close(io);
        mine = try sync.Library.scan(io, gpa, music_dir);
        errdefer mine.deinit();
        served = try std.DynamicBitSetUnmanaged.initEmpty(gpa, mine.paths.len);
        ready = true;
    }

    fn cleanUp(io: Io) void {
        if (!ready) return;
        ready = false;
        if (reader) |r| r.file.close(io);
        reader = null;
        served.deinit(gpa);
        mine.deinit();
        music_dir.close(io);
    }

    fn heardFromOtherClient(io: Io) void {
        state_lock.lockUncancelable(io);
        defer state_lock.unlock(io);
        last_heard = Io.Timestamp.now(io, .awake);
    }

    fn checkConnected(io: Io) !void {
        if (clientState.should_disconnect) return error.Disconnected;
        state_lock.lockUncancelable(io);
        const last = last_heard;
        state_lock.unlock(io);
        if (last.untilNow(io, .awake).toSeconds() >= peer_timeout_s) {
            Status.set(io, "Lost connection to the other device", .{});
            return error.LostConnection;
        }
    }

    /// Downloads blob `id` (into `file`, or into memory for the song list).
    /// Each round asks for up to `window` missing chunks and waits for them;
    /// whatever got lost is asked for again in the next round.
    fn fetchBlob(io: Io, id: u32, file: ?Io.File) !Fetch {
        state_lock.lockUncancelable(io);
        fetch = .{ .id = id, .file = file };
        state_lock.unlock(io);
        errdefer {
            state_lock.lockUncancelable(io);
            fetch.?.deinit();
            fetch = null;
            state_lock.unlock(io);
        }

        var ask: [1024]u32 = undefined;
        var buf: [1024]u8 = undefined;
        while (true) {
            try checkConnected(io);

            var n: usize = 0;
            state_lock.lockUncancelable(io);
            const f = &fetch.?;
            const known = f.total != null;
            if (f.total) |total| {
                var i: u32 = 0;
                while (i < total and n < window) : (i += 1) {
                    if (!f.got.isSet(i)) {
                        ask[n] = i;
                        n += 1;
                    }
                }
            } else {
                ask[0] = 0; // the first chunk tells us the total
                n = 1;
            }
            f.pending = n;
            f.last_data = null;
            state_lock.unlock(io);
            if (n == 0) break;

            var s: usize = 0;
            while (s < n) : (s += sync.max_per_request) {
                const e = @min(n, s + sync.max_per_request);
                Networks.Client.sendData(io, sync.encodeRequest(&buf, id, ask[s..e])) catch {};
            }

            // Wait for the round; stop early once data arrived and then dried up.
            const started = Io.Timestamp.now(io, .awake);
            var lost: usize = 0;
            while (true) {
                try io.sleep(.fromMilliseconds(10), .awake);
                state_lock.lockUncancelable(io);
                lost = fetch.?.pending;
                const last = fetch.?.last_data;
                state_lock.unlock(io);
                if (lost == 0) break;
                if (started.untilNow(io, .awake).toMilliseconds() >= 500) break;
                if (last) |l| if (l.untilNow(io, .awake).toMilliseconds() >= 60) break;
            }
            if (known) {
                window = if (lost * 10 > n) @max(16, window / 2) else @min(ask.len, window + 64);
            }
        }

        state_lock.lockUncancelable(io);
        defer state_lock.unlock(io);
        const done = fetch.?;
        fetch = null;
        return done;
    }

    /// Downloads a song to "<path>.part", then renames it into place.
    fn fetchFile(io: Io, id: u32, path: []const u8) !void {
        if (std.fs.path.dirnamePosix(path)) |dir| try music_dir.createDirPath(io, dir);
        var part_buf: [512]u8 = undefined;
        const part = try std.fmt.bufPrint(&part_buf, "{s}.part", .{path});
        const file = try music_dir.createFile(io, part, .{ .read = true });
        var f = fetchBlob(io, id, file) catch |err| {
            file.close(io);
            music_dir.deleteFile(io, part) catch {};
            return err;
        };
        f.deinit();
        file.close(io);
        try Io.Dir.rename(music_dir, part, music_dir, path, io);
    }

    /// Says we're done until the other client is done too. Then both have
    /// everything and `start` sends TERMINATE.
    fn finish(io: Io) !void {
        while (true) {
            Networks.Client.sendData(io, &.{@intFromEnum(sync.Type.done)}) catch {};
            state_lock.lockUncancelable(io);
            const done = peer_done;
            state_lock.unlock(io);
            if (done) return;
            // The other client may leave right after getting our last chunk.
            checkConnected(io) catch return;
            try io.sleep(.fromMilliseconds(300), .awake);
        }
    }

    /// Handles a DATA payload from the other client (listener thread).
    fn onData(io: Io, p: []const u8) void {
        if (!ready) return;
        switch (@as(sync.Type, @enumFromInt(p[0]))) {
            .request => if (sync.Request.parse(p)) |r| serve(io, r),
            .data => if (sync.Data.parse(p)) |d| receive(io, d),
            .done => {
                state_lock.lockUncancelable(io);
                defer state_lock.unlock(io);
                peer_done = true;
            },
            _ => {},
        }
    }

    fn serve(io: Io, r: sync.Request) void {
        var size: u64 = mine.blob.len;
        var file: ?Io.File = null;
        if (r.id != sync.list_id) {
            if (r.id >= mine.paths.len) return;
            file = openReader(io, r.id) catch return;
            size = file.?.length(io) catch return;
            served.set(r.id);
        }
        const total = sync.totalChunks(size);
        if (total > sync.max_chunks) return;

        var buf: [sync.data_header + sync.chunk_size]u8 = undefined;
        for (0..r.count()) |i| {
            const idx = r.index(i);
            if (idx >= total) continue;
            const offset = @as(u64, idx) * sync.chunk_size;
            const n: usize = @intCast(@min(sync.chunk_size, size - offset));
            const body = buf[sync.data_header..][0..n];
            if (file) |f| {
                const got = f.readPositionalAll(io, body, offset) catch return;
                if (got != n) return;
            } else {
                @memcpy(body, mine.blob[@intCast(offset)..][0..n]);
            }
            sync.encodeDataHeader(&buf, r.id, idx, @intCast(total));
            Networks.Client.sendData(io, buf[0 .. sync.data_header + n]) catch return;
        }
    }

    fn openReader(io: Io, id: u32) !Io.File {
        if (reader) |r| {
            if (r.id == id) return r.file;
            r.file.close(io);
            reader = null;
        }
        const file = try music_dir.openFile(io, mine.paths[id], .{});
        reader = .{ .id = id, .file = file };
        return file;
    }

    fn receive(io: Io, d: sync.Data) void {
        state_lock.lockUncancelable(io);
        defer state_lock.unlock(io);
        const f = &(fetch orelse return);
        if (d.id != f.id) return;
        if (f.total) |total| {
            if (total != d.total) return;
        } else {
            if (f.file == null and d.total > sync.max_list_chunks) return;
            f.got = std.DynamicBitSetUnmanaged.initEmpty(gpa, d.total) catch return;
            if (f.file == null) f.list = gpa.alloc(u8, @as(usize, d.total) * sync.chunk_size) catch {
                f.got.deinit(gpa);
                return;
            };
            f.total = d.total;
        }
        if (f.got.isSet(d.idx)) return;

        const offset = @as(u64, d.idx) * sync.chunk_size;
        if (f.file) |file| {
            file.writePositionalAll(io, d.bytes, offset) catch return;
        } else {
            @memcpy(f.list[@intCast(offset)..][0..d.bytes.len], d.bytes);
            if (d.idx + 1 == d.total) f.list_len = @intCast(offset + d.bytes.len);
        }
        f.got.set(d.idx);
        f.pending -|= 1;
        f.last_data = Io.Timestamp.now(io, .awake);
    }
};

/// Small text files in the working directory that the app and backend share.
const Config = struct {
    /// Reads a whole file, trimmed; null if it's missing, empty or too big.
    fn read(io: Io, name: []const u8, buf: []u8) ?[]const u8 {
        const file = Io.Dir.cwd().openFile(io, name, .{}) catch return null;
        defer file.close(io);
        const n = file.readPositionalAll(io, buf, 0) catch return null;
        if (n == buf.len) return null;
        const text = std.mem.trim(u8, buf[0..n], " \t\r\n");
        return if (text.len == 0) null else text;
    }

    fn write(io: Io, name: []const u8, text: []const u8) void {
        const file = Io.Dir.cwd().createFile(io, name, .{}) catch return;
        defer file.close(io);
        file.writePositionalAll(io, text, 0) catch {};
    }

    fn hasLine(text: []const u8, line: []const u8) bool {
        var it = std.mem.tokenizeAny(u8, text, "\r\n");
        while (it.next()) |l| {
            if (eql(l, line)) return true;
        }
        return false;
    }

    /// The folder named in "musicDir.txt", or "music" in the working directory.
    fn openMusicDir(io: Io) !Io.Dir {
        var buf: [1024]u8 = undefined;
        const cwd = Io.Dir.cwd();
        const path = read(io, "musicDir.txt", &buf) orelse "music";
        cwd.createDirPath(io, path) catch {};
        return cwd.openDir(io, path, .{ .iterate = true });
    }
};

/// Progress for the app to show, in "status.txt" in the working directory.
const Status = struct {
    fn set(io: Io, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
        testPrint("{s}\n", .{text});
        Config.write(io, "status.txt", text);
    }
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
    clientState = Networks.ClientState.init(io) catch |err| {
        Status.set(io, "Sync failed: {s}", .{@errorName(err)});
        return err;
    };
    defer clientState.deinit(io);

    switch (args.len) {
        0 => {
            try syncLibrary(io);
        },
        1 => {
            if (eql(args[0], "sync")) {
                try syncLibrary(io);
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

                try syncLibrary(io);
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

/// Connects with the other client and exchanges songs. Progress and the
/// result go to status.txt; our UDP port goes to port.txt so the app can
/// stop the sync by sending TERMINATE to it.
fn syncLibrary(io: Io) !void {
    var port_buf: [8]u8 = undefined;
    Config.write(io, "port.txt", std.fmt.bufPrint(&port_buf, "{d}", .{clientState.client_socket.address.getPort()}) catch "");

    LibrarySync.prepare(io) catch |err| {
        Status.set(io, "Can't open the music folder: {s}", .{@errorName(err)});
        return err;
    };
    // Runs after Client.start has stopped the listener thread.
    defer LibrarySync.cleanUp(io);

    Networks.Client.start(io) catch |err| {
        switch (err) {
            error.NoOtherClient, error.LostConnection => {}, // already explained
            error.Disconnected => Status.set(io, "Sync stopped", .{}),
            else => Status.set(io, "Sync failed: {s}", .{@errorName(err)}),
        }
        return err;
    };
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
