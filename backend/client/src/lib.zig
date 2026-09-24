const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

pub fn handleArgs(io: Io, args: []const [:0]const u8) !void {
    //temp
    if (args.len == 1) {
        if (SYNCING.readKey(io)) |key| {
            std.debug.print("Found key: {s}\n", .{key});
            try SYNCING.start(io, key);
        } else |_| {
            const key = try SYNCING.generateNewKey(io);
            std.debug.print("Couldn't find key. Generated new key: {s}\n", .{key});
            try SYNCING.start(io, key);
        }
        return error.InvalidArgs;
    }

    if (std.mem.eql(u8, args[1], "sync")) {
        if (args.len == 2) {
            if (SYNCING.readKey(io)) |key| {
                std.debug.print("Found key: {s}\n", .{key});
                try SYNCING.start(io, key);
            } else |_| {
                const key = try SYNCING.generateNewKey(io);
                std.debug.print("Couldn't find key. Generated new key: {s}\n", .{key});
                try SYNCING.start(io, key);
            }
        } else if (args.len == 3) {
            // conenct with given key and saving key in cache
            if (args[2].len != 8) return error.InvalidArgs;

            var key: [8]u8 = undefined;
            @memcpy(&key, args[2][0..8]);

            std.debug.print("Connecting with key: {s}\n", .{key});
            try SYNCING.writeKey(io, key);
            try SYNCING.start(io, key);
        }
    } else if (std.mem.eql(u8, args[1], "sync_new_key")) {
        std.debug.print("Generating new key\n", .{});
        _ = try SYNCING.generateNewKey(io);
    } else if (std.mem.eql(u8, args[1], "rename")) {
        if (args.len != 4) return error.InvalidArgs;
        try EDITING.renameFile(io, args[2], args[3]);
    } else if (std.mem.eql(u8, args[1], "add")) {
        if (args.len != 3) return error.InvalidArgs;
        try EDITING.add(io, args[2]);
    }
}

const SYNCING = struct {
    pub fn start(io: Io, key: [8]u8) !void {
        const server = try std.Io.net.IpAddress.parse("24.243.26.72", 5252);
        const client_socket = try openClientSocket(io);
        defer client_socket.close(io);

        const local_ip_bytes = try getLocalIp(io);
        const local_ip = try formatIp(local_ip_bytes, client_socket.address.getPort());
        std.debug.print("Opening on local port: {d}\n", .{client_socket.address.getPort()});

        //SEND 6 BYTES FOR LOCAL IP FOLLOWED BY 8 BYTES OF THE KEY
        const info = formatClientInfoForServer(local_ip, key);
        try client_socket.send(io, &server, &info);

        var buffer: [1024]u8 = undefined;
        var message: std.Io.net.IncomingMessage = undefined;

        // TODO: MAKE BETTER
        while (true)  {
            message = try client_socket.receive(io, &buffer);
            if (message.data.len != 5) continue;
        }
        if (message.data.len != 6) return error.ErrorGettingOtherClientIp;

        const other_client = bufToIp(message.data[0..6].*);
        std.debug.print("Connecting with {d}.{d}.{d}.{d}:{d}\n", .{ message.data[0], message.data[1], message.data[2], message.data[3], other_client.getPort() });

        const thread = try std.Thread.spawn(.{}, workerThread, .{ io, client_socket });
        try mainThread(io, client_socket, other_client);
        thread.join();
    }
    fn mainThread(io: Io, client_socket: std.Io.net.Socket, other_client: std.Io.net.IpAddress) !void {
        for (0..5) |_| {
            try io.sleep(.fromMilliseconds(100), .awake);
            try client_socket.send(io, &other_client, "PUNCH");
        }
        var buffer: [1024]u8 = undefined;
        while (true) {
            const s = cin(io, &buffer);
            try client_socket.send(io, &other_client, s);
        }
    }
    fn workerThread(io: std.Io, socket: std.Io.net.Socket) !void {
        var buffer: [1024]u8 = undefined;
        while (true) {
            const message = try socket.receive(io, &buffer);
            if (std.mem.eql(u8, message.data, "PUNCH")) continue;

            std.debug.print("{s}\n", .{message.data});
        }
    }
    fn formatClientInfoForServer(ip: [6]u8, key: [8]u8) [14]u8 {
        var result: [14]u8 = undefined;
        @memcpy(result[0..6], &ip);
        @memcpy(result[6..14], &key);
        return result;
    }
    fn openClientSocket(io: Io) !std.Io.net.Socket {
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
    fn getPortFromArg(buffer: [:0]const u8) u16 {
        var result: u16 = 0;
        for (buffer) |c| switch (c) {
            '0'...'9' => result = result * 10 + c - '0',
            else => {},
        } else return result;
    }
    fn getPortFromServer(buffer: []u8) u16 {
        var result: u16 = 0;
        for (0..buffer.len) |i| {
            result <<= 8;
            result |= buffer[i];
        }
        return result;
    }
    fn generateNewKey(io: Io) ![8]u8 {
        const seed: u64 = @bitCast(std.Io.Timestamp.now(io, .awake).toMicroseconds());
        var rand = std.Random.DefaultPrng.init(seed);

        var key: [8]u8 = undefined;
        for (&key) |*c| {
            const offset: u8 = @intCast(rand.next() % 10);
            c.* = '0' + offset;
        }
        try writeKey(io, key);
        return key;
    }
    fn writeKey(io: Io, key: [8]u8) !void {
        const cwd_dir = std.Io.Dir.cwd();
        const cache = cwd_dir.openDir(io, app_path++"cache", .{}) catch try cwd_dir.createDirPathOpen(io, "cache", .{});
        const key_file = cache.openFile(io, "key.txt", .{ .mode = .write_only }) catch try cache.createFile(io, "key.txt", .{});

        var wBuffer: [128]u8 = undefined;
        var writer = key_file.writer(io, &wBuffer);
        var output = &writer.interface;

        _ = try output.write(&key);
        try output.flush();
        try writer.end();
    }
    fn readKey(io: Io) ![8]u8 {
        const cwd_dir = std.Io.Dir.cwd();
        const cache = try cwd_dir.openDir(io, "cache", .{});
        const key_file = try cache.openFile(io, "key.txt", .{});

        var rBuffer: [128]u8 = undefined;
        var wBuffer: [128]u8 = undefined;
        var reader = key_file.reader(io, &rBuffer);
        var input = &reader.interface;
        var writer = std.Io.Writer.fixed(&wBuffer);

        const len = try input.streamRemaining(&writer);
        if (len != 8) return error.ErrorReadingKey;

        var result: [8]u8 = undefined;
        @memcpy(&result, wBuffer[0..8]);
        return result;
    }
    fn getLocalIp(io: Io) ![4]u8 {
        switch (builtin.os.tag) {
            .windows => {
                return try getLocalIpWindows(io);
            },
            .linux => {
                return try getLocalIpAndroid(io);
            },
            else => {
                const result: [4]u8 = [_]u8{0} ** 4;
                return result;
            },
        }
    }
    fn getLocalIpWindows(io: std.Io) ![4]u8 {
        var result: [4]u8 = .{ 192, 168, 0, 0 };
        var child = try std.process.spawn(io, .{ .argv = &.{"ipconfig"}, .stdout = .pipe });

        var buffer: [1024]u8 = undefined;
        var wbuffer: [1024]u8 = undefined;
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
    fn formatIp(bytes: [4]u8, port: u16) ![6]u8 {
        var result: [6]u8 = [_]u8{0} ** 6;
        @memcpy(result[0..4], &bytes);

        result[4] |= @truncate(port >> 8);
        result[5] |= @truncate(port);

        return result;
    }
    fn formatIpAddress(ip: std.Io.net.IpAddress) ![6]u8 {
        return formatIp(ip.ip4.bytes, ip.ip4.bytes);
    }
    fn bufToIp(bytes: [6]u8) std.Io.net.IpAddress {
        //.{bytes[0], bytes[1], bytes[2], bytes[3]}
        var port: u16 = 0;
        port |= bytes[4];
        port <<= 8;
        port |= bytes[5];
        return .{ .ip4 = .{ .bytes = bytes[0..4].*, .port = port } };
    }
};
// rename [path] [newname]
// update [path] playcount [amount]
// update [path] playtime [time in seconds]
// add [path] - when a new song is downloaded or added to library / to make sure it is traacked / can be a folder
// 

const app_path = "app/";
pub const EDITING = struct {
    pub fn openHistoryFile(io: Io) !std.Io.File {
        const change_dir_name = app_path ++ "changes";
        const history_file_name = "history.txt";

        const cwd = std.Io.Dir.cwd();

        const change_dir = cwd.openDir(io, change_dir_name, .{})
                                catch try cwd.createDirPathOpen(io, change_dir_name, .{});
        defer change_dir.close(io);

        return change_dir.openFile(io, history_file_name, .{ .mode = .read_write })
                catch try change_dir.createFile(io, history_file_name, .{.read = true});
    }
    pub fn clearHistoryFile(io: Io) !void {
        const file = try openHistoryFile(io);
        defer file.close(io);

        var wBuffer: [256]u8 = undefined;
        var writer = file.writer(io, &wBuffer);

        try writer.end();
    }
    fn openMusicDir(io: Io) !std.Io.Dir {
        const music_dir_name = app_path ++ "music";
        
        const cwd = std.Io.Dir.cwd();

        return cwd.openDir(io, music_dir_name, .{})
                catch try cwd.createDirPathOpen(io, music_dir_name, .{});
    }
    pub fn appendLine(io: Io, line: []const u8) !void {
        const file = try openHistoryFile(io);
        defer file.close(io);

        var wBuffer: [256]u8 = undefined;
        var writer = file.writer(io, &wBuffer);
        var out = &writer.interface;

        try writer.seekTo(try file.length(io));
        try out.writeAll(line);
        try out.writeAll("\n");
        try out.flush();
    }
    // TODO: make sure path is being tracked first before  
    fn renameFile(io: Io, path: []const u8, new_name: []const u8) !void {
        const music_dir = try openMusicDir(io);
        defer music_dir.close(io);

        if (music_dir.openFile(io, path, .{})) |_| {
            var buffer: [128]u8 = undefined;
            const old_path: []const u8 = std.fs.path.dirname(path) orelse "";
            const dir = try music_dir.openDir(io, old_path, .{});
            
            const total_len = old_path.len + new_name.len;
            if (total_len >= buffer.len) return error.RanOutofBufferSpace;
            @memcpy(buffer[0..old_path.len], old_path);
            @memcpy(buffer[old_path.len..total_len], new_name);
            
            music_dir.renamePreserve(path, dir, new_name, io) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    std.debug.print("Other song with name \"{s}\" found\n", .{new_name});
                    return err;
                },
                else => {
                    std.debug.print("Error renaming song: {any}\n", .{err});
                    return err;
                },
            };

            var buffer1: [128]u8 = undefined;
            var list = std.ArrayList(u8).initBuffer(&buffer1);
            
            try list.appendSliceBounded("rename ");
            try list.appendSliceBounded(path);
            try list.appendSliceBounded(" ");
            try list.appendSliceBounded(new_name);

            try appendLine(io, list.items);

        } else |err| switch (err) {
            std.Io.File.OpenError.FileNotFound => {
                std.debug.print("Path doesnt exist: \"{s}\"\n", .{path});
                return err;
            },
            else => {
                std.debug.print("Error opening song: {any}\n", .{err});
                return err;
            },
        }
    }
    fn add(_: Io, _: []const u8) !void {

    }
};
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
fn stringToNum(bytes: []u8) usize {
    var result: usize = 0;
    for (bytes) |c| switch (c) {
        '0'...'9' => {
            result = result * 10 + (c - '0');
        },
        else => {},
    };
    return result;
}