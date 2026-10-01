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

// TODO: if only one device can get the local ip
// TODO: but they are under the same public ip
// TODO: then try to connect with client using local ip

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

        const ClientMode = enum(u8) {
            P2P,
            Relay,
        };

        fn init(io: Io) ClientState {
            return .{
                .client_socket = getClientSocket(io) catch unreachable,
                .server_ip = getServerIp() catch unreachable,
                .key = FileManager.getKey(io) catch unreachable,
            };
        }
        fn deinit(self: *ClientState, io: Io) void {
            self.client_socket.close(io);
        }
        fn sendResolvedWithCode(self: *ClientState, io: Io, cliendCode: ClientCode, comptime message: []const u8) !void {
            try self.client_socket.socket.send(io, &clientState.resolved_ip, ClientCode.getByte(cliendCode) ++ message);
        }
        fn sendResolved(self: *ClientState, io: Io, data: []u8) !void {
            try self.client_socket.send(io, &clientState.resolved_ip, data);
            testPrint("using {any}\n", .{clientState.resolved_ip});
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
            while (!clientState.recieved_inital_info) try io.sleep(.fromMilliseconds(100), .awake);
            var socket = clientState.client_socket;
            for (0..30) |_| {
                if (acknowledged) break;
                if (TESTING_RELAY) {
                    try io.sleep(.fromMilliseconds(100), .awake);
                    continue;
                }
                const v: u32 = @bitCast(clientState.reciever_local_ip.?.ip4.bytes[0..4].*);
                if (v != 0) {
                    testPrint("v = {d}\n", .{v});
                    try socket.send(io, &clientState.reciever_local_ip.?, ClientCode.getByte(.P2P) ++ "LOCAL IP");
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
        }
        fn clientStart(io: Io) !void {
            var buffer: [256]u8 = undefined;
            while (true) {
                const in = cin(io, &buffer);
                try send(io, in);
                if (std.mem.eql(u8, in, "EXIT")) return;
            }
        }
        fn send(io: Io, buf: []u8) !void {
            if (clientState.cliendMode == .P2P) {
                if (std.mem.eql(u8, buf, "EXIT")) {
                    try clientState.sendResolved(io, buf);
                    return;
                }
                var buffer: [256]u8 = undefined;
                var w = std.Io.Writer.fixed(&buffer);
                try w.writeAll(&ClientCode.getByte(.TEXT));
                try w.writeAll(buf);
                try clientState.sendResolved(io, w.buffered());
            } else {
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
            try clientStart(io);
            //try Syncing.sync(io);

            GlobalListeningThread.join();
        }
        fn listen(io: Io) !void {
            var buffer: [1024]u8 = undefined;
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
                            const l = clientState.reciever_local_ip.?.ip4.bytes;
                            std.debug.print("Initial message: Other Client Public IP: {d}.{d}.{d}.{d}:{d} Local IP: {d}.{d}.{d}.{d}:{d}\n", .{ p[0], p[1], p[2], p[3], clientState.reciever_public_ip.?.getPort(), l[0], l[1], l[2], l[3], clientState.reciever_local_ip.?.getPort() });
                        }
                    },
                    .TEXT => std.debug.print("recieved: {s}\n", .{message.data[1..]}),
                    .P2P => {
                        testPrint("P2P: {s}\n", .{message.data[1..]});
                        //clientState.reciever_local_ip.? = message.from;
                        clientState.resolved_ip = message.from;
                        const v: u32 = @bitCast(clientState.reciever_local_ip.?.ip4.bytes[0..4].*);
                        if (v != 0) {
                            testPrint("v = {d}\n", .{v});
                            try clientState.client_socket.send(io, &clientState.reciever_local_ip.?, ClientCode.getByte(.ACK) ++ "LOCAL IP");
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
                    .NONE => {
                        if (std.mem.eql(u8, message.data[0..], "EXIT")) {
                            try send(io, message.data[0..]);
                            std.debug.print("Disconnected\nEnter 'EXIT': ", .{});
                            break;
                        }
                        std.debug.print("Code not handled: {b}: {s}\n", .{ message.data[0], message.data[1..] });
                    },
                    else => std.debug.print("Not implemented yet!!: {any}\n", .{code}),
                }
            }
        }
        const Syncing = struct {
            fn sync(io: Io) !void {
                _ = io;
                return;
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
    fn getKeyFile(io: Io) !Io.File {
        const app_dir = try getAppDir(io);
        defer app_dir.close(io);
        const key_file_name = "key.txt";

        return app_dir.openFile(io, key_file_name, .{ .mode = .read_write }) catch try app_dir.createFile(io, key_file_name, .{ .read = true });
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
    fn getMusicDir(io: Io) !Io.Dir {
        const music_dir_name = "music";
        const cwd = std.Io.Dir.cwd();

        return cwd.openDir(io, music_dir_name, .{}) catch try cwd.createDirPathOpen(io, music_dir_name, .{});
    }
    // FILE HEAD
    // path to file
    // FILE CONTENT
    // file content
    // fn sendFile(io: Io, file: Io.File) !void {
    //     var rbuf: [1024]u8 = undefined;
    //     var wbuf: [1024]u8 = undefined;
    //     var file_name: [256]u8 = undefined;
    //     const len = try file.realPath(io, &file_name[1..]);
    //     var rfile = file.reader(io, &rbuf);
    //     var reader = &rfile.interface;
    //     var writer = Io.Writer.fixed(&wbuf);

    //     // wbuf[0] = ClientCode.getByte(.FILE_CONTENT)
    //     // clientState.sendResolved(io, file_name)

    //     // while (reader.stream(&writer, .unlimited)) |_| {
    //     //     clientState.sendResolved(io, data: []u8)
    //     // }
    // }
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    try start(init.io, args[1..]);
}
pub fn start(io: Io, args: []const [:0]const u8) !void {
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
                try FileManager.writeKey(io, try FileManager.generateNewKey(io));
            }
        },
        2 => {
            if (eql(args[0], "sync")) {
                if (args[1].len != 8) return error.KeyWrongLength;
                var key: [8]u8 = undefined;
                @memcpy(&key, args[1][0..8]);

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
