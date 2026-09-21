const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

// COMMANDS FOR WINDOWS
// sync [key] - if key isnt provided read from cache if cache empty generate new key / key should be 8 bytes
// sync_new_key - generate new key
// 



pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    _ = try getLocalIpWindows(init.io);
    
    if (args.len == 1) {
        if (SYNCING.readKey(init.io)) |key| {
            std.debug.print("Found key: {s}\n", .{key});
            try SYNCING.start(init, key, 0);
        } else |_| {
            const key = try SYNCING.generateNewKey(init.io);
            std.debug.print("Couldn't find key. Generated new key: {s}\n", .{key});
            try SYNCING.start(init, key, 0);
        }
        return error.InvalidArgs;
    }
    if (std.mem.eql(u8, args[1], "sync")) {
        if (args.len == 2) {
            if (SYNCING.readKey(init.io)) |key| {
                std.debug.print("Found key: {s}\n", .{key});
                try SYNCING.start(init, key, 0);
            } else |_| {
                const key = try SYNCING.generateNewKey(init.io);
                std.debug.print("Couldn't find key. Generated new key: {s}\n", .{key});
                try SYNCING.start(init, key, 0);
            }
        } else if (args.len == 3) {
            // conenct with given key and saving key in cache
            if (args[2].len != 8) return error.InvalidArgs;

            var key: [8]u8 = undefined;
            @memcpy(&key, args[2][0..8]);

            std.debug.print("Connecting with key: {s}\n", .{key});
            try SYNCING.writeKey(init.io, key);
            try SYNCING.start(init, key, 0);
        }
    } else if (std.mem.eql(u8, args[1], "sync_new_key")) {
        std.debug.print("Generating new key\n", .{});
        _ = try SYNCING.generateNewKey(init.io);
    }
    else {
        try SYNCING.start(init, try SYNCING.readKey(init.io), SYNCING.getPortFromArg(args[1]));
    }
}
const SYNCING = struct {
    pub fn start(init: std.process.Init, key: [8]u8, port: u16) !void {
        const client_port: u16 = if (port == 0) 32145 else port;
        var client = try Io.net.IpAddress.parse("0.0.0.0", client_port);
        const server = try std.Io.net.IpAddress.parse("24.243.26.72", 5252);
        var client_socket: std.Io.net.Socket = undefined;
        while (true) {
            if (client.bind(init.io, .{ .mode = .dgram })) |socket| {
                client_socket = socket;
                break;
            } else |err| switch (err) {
                error.AddressInUse => {
                    client.setPort(client.ip4.port+1);
                },
                else => {return err;},
            }
        }
        defer client_socket.close(init.io);

        const local_ip_bytes = try getLocalIp(init.io);
        const local_ip = try formatIp(local_ip_bytes, client_socket.address.getPort());
        std.debug.print("Opening on local port: {d}\n", .{client_socket.address.getPort()});
        
        //SEND 6 BYTES FOR LOCAL IP FOLLOWED BY 8 BYTES OF THE KEY
        var info: [14]u8 = undefined;
        @memcpy(info[0..6], &local_ip);
        @memcpy(info[6..14], &key);
        try client_socket.send(init.io, &server, &info);

        var buffer: [1024]u8 = undefined;
        var message = try client_socket.receive(init.io, &buffer);

        if (message.data.len != 6) return error.ErrorGettingOtherClientIp;

        var bytes: [4]u8 = undefined;
        @memcpy(&bytes, message.data[0..4]);
        const other_client_port = getPortFromServer(message.data[4..6]);
        const other_client: std.Io.net.IpAddress = .{ .ip4 = .{ .bytes = bytes, .port = other_client_port } };
        
        std.debug.print("Connecting with {d}.{d}.{d}.{d}:{d}\n", .{bytes[0], bytes[1], bytes[2], bytes[3], other_client_port});

        const thread = try std.Thread.spawn(.{}, workerThread, .{init.io, client_socket});

        for (0..20) |_| {
            try client_socket.send(init.io, &other_client, "PUNCH");
            try init.io.sleep(.fromMilliseconds(200), .awake);
        }
        
        
        while (true) {
            const s = cin(init.io, &buffer);
            try client_socket.send(init.io, &other_client, s);
        }
        thread.join();
    }
    fn workerThread(io: std.Io, socket: std.Io.net.Socket) !void {
        var buffer: [1024]u8 = undefined;
        while (true) {
            const message = try socket.receive(io, &buffer);
            if (std.mem.eql(u8, message.data, "PUNCH")) continue;
            std.debug.print("{s}\n", .{message.data});
        }
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
        const cache = cwd_dir.openDir(io, "cache", .{}) 
                        catch try cwd_dir.createDirPathOpen(io, "cache", .{});
        const key_file = cache.openFile(io, "key.txt", .{ .mode = .write_only })
                        catch try cache.createFile(io, "key.txt", .{});

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
fn getLocalIp(io: Io) ![4]u8 {
    switch (builtin.os.tag) {
        .windows => {
            return try getLocalIpWindows(io);
        },
        else => {
            const result: [4]u8 = [_]u8{0} ** 4; 
            return result;
        }
    }
}
fn getLocalIpWindows(io: std.Io) ![4]u8 {
    var result: [4]u8 = .{192, 168, 0, 0};
    var child = try std.process.spawn(io, .{ .argv = &.{"ipconfig"}, .stdout = .pipe });
    
    var buffer: [1024]u8 = undefined;
    var wbuffer: [1024]u8 = undefined;
    var reader = child.stdout.?.reader(io, &buffer);
    var input = &reader.interface;
    var writer = std.Io.Writer.fixed(&wbuffer);

    _ = try input.streamRemaining(&writer);
    const result1 = std.mem.cut(u8, writer.buffered(), "192.168.");
    const result2 = std.mem.cut(u8, result1.?.@"1", "\n");

    var byte: u8 = 0;
    var x: usize = 0;
    for (result2.?.@"0") |c| {
        switch (c) {
            '0'...'9' => {
                byte = byte * 10 + (c - '0');
            },
            else => {
                result[2+x] = byte;
                x+=1;
            }
        }
    }

    _ = try child.wait(io);
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