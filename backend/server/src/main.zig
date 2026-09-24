const std = @import("std");
const Io = std.Io;

const MAX_CONNECTIONS: usize = 16;
const Connection = struct {key: [8]u8 = undefined, ip: std.Io.net.IpAddress, local_ip: ?std.Io.net.IpAddress = null, timestamp: std.Io.Timestamp};
var CLIENTS: [MAX_CONNECTIONS]?Connection = [_]?Connection{null} ** MAX_CONNECTIONS;
var CLIENTS_SIZE: usize = 0;
const CONNECTIONS = struct {
    fn add(conn: Connection) !void {
        for (&CLIENTS) |*client| {
            if (client.* == null) continue;
            //if (client.?.ip.eql(&conn.ip)) return error.ClientAlreadyWaiting;
            if (client.*.?.ip.eql(&conn.ip)) {
                client.* = conn;
                return;
            }
        }
        for (&CLIENTS) |*client| {
            if (client.* == null) {
                client.* = conn;
                CLIENTS_SIZE += 1;
                return;
            }
        } else {
            return error.TooManyClients;
        }
    }
    fn cleanUp() !void {

    }
    fn pairUp(io: Io, server_spcket: *std.Io.net.Socket) !void {
        for (0..CLIENTS.len) |x| {
            for (x+1..CLIENTS.len) |y| {
                if (CLIENTS[x] == null or CLIENTS[y] == null) continue;
                if (std.mem.eql(u8, &CLIENTS[x].?.key, &CLIENTS[y].?.key)) {
                    var client1: std.Io.net.IpAddress = undefined;
                    var client2: std.Io.net.IpAddress = undefined;
                    if (std.mem.eql(u8, &CLIENTS[x].?.ip.ip4.bytes, &CLIENTS[y].?.ip.ip4.bytes)) {
                        if (CLIENTS[x].?.local_ip == null or CLIENTS[y].?.local_ip == null) {
                            return error.NoLocalIp;
                        }
                        client1 = CLIENTS[x].?.local_ip.?;
                        client2 = CLIENTS[y].?.local_ip.?;
                    } else {
                        client1 = CLIENTS[x].?.ip;
                        client2 = CLIENTS[y].?.ip;
                    }
                    //TODO: make this not needed
                    var buffer: [6]u8 = undefined;

                    try server_spcket.send(io, &client1, formatIp(client2, &buffer));
                    try server_spcket.send(io, &client2, formatIp(client1, &buffer));

                    CLIENTS[x] = null;
                    CLIENTS[y] = null;
                    CLIENTS_SIZE -= 2; 
                }
            }
        } 
    }
};
// Wait for 2 clients to connect with the same password/key
// Connect them to each other
//TODO: if two clients on the same network fix that
// maybe use a map to store clients with key
pub fn main(init: std.process.Init) !void {
    const thread = try std.Thread.spawn(.{}, workerThread, .{init});
    try mainThread(init);
    thread.join();
}
fn mainThread(init: std.process.Init) !void {
    const ip = try std.Io.net.IpAddress.parse("192.168.0.62", 5252);
    std.debug.print("Server Opened...\n", .{});
    var server_socket = try ip.bind(init.io, .{ .mode = .dgram });
    defer server_socket.close(init.io);

    var buffer: [1024]u8 = undefined;
    while (true) {
        const message = try server_socket.receive(init.io, &buffer);
        
        if (message.data.len == 14) {
            const local_ip = bufToIp(message.data[0..6].*);
            const b = message.from.ip4.bytes;
            const key = message.data[6..14];
            try print(init.io, "\x1b[1APublic: {d}.{d}.{d}.{d}:{d}, Local: {d}.{d}.{d}.{d}:{d} Connected with key: {s}\x1b[1E\n", 
            .{b[0], b[1], b[2], b[3], message.from.getPort(), message.data[0], message.data[1], message.data[2], message.data[3], local_ip.getPort(), key});

            var conn = Connection {.ip = message.from, .timestamp = std.Io.Timestamp.now(init.io, .awake)};
            @memcpy(&conn.key, key);

            const aux: u32 = @bitCast(local_ip.ip4.bytes);
            if (aux != 0) conn.local_ip = local_ip; 

            CONNECTIONS.add(conn) catch |err| switch (err) {
                // error.ClientAlreadyWaiting => {
                //     try print(init.io, "\x1b[1A{any}\x1b[1E\n", .{err});
                //     continue;
                // },
                else => {},
            };
            try CONNECTIONS.pairUp(init.io, &server_socket);
        }
    }
}
fn workerThread(init: std.process.Init) !void {
    std.debug.print("size: {d}\n", .{CLIENTS_SIZE});
    while (true) {
        try print(init.io, "\x1b[1Asize: {d}\n", .{CLIENTS_SIZE});

        try init.io.sleep(.fromSeconds(1), .awake);
    }
}
var lock = std.Io.Mutex.init;
fn print(io: Io, comptime fmt: []const u8, args: anytype) !void {
    try lock.lock(io);
    std.debug.print(fmt, args);
    lock.unlock(io);
}
fn formatIp(ip: std.Io.net.IpAddress, buffer: []u8) []u8 {
    @memcpy(buffer[0..4], &ip.ip4.bytes);
    buffer[4] = 0x0; buffer[5] = 0x0;

    const port = ip.ip4.port;
    buffer[4] |= @truncate(port >> 8);
    buffer[5] |= @truncate(port);

    //std.debug.print("{b:0>16} : {b:0>8}{b:0>8}\n", .{ip.ip4.port, buffer[4], buffer[5]});
    return buffer;
}
fn bufToIp(bytes: [6]u8) std.Io.net.IpAddress {
    //.{bytes[0], bytes[1], bytes[2], bytes[3]}
    var port: u16 = 0;
    port |= bytes[4];
    port <<= 8;
    port |= bytes[5];
    return .{ .ip4 = .{ .bytes = bytes[0..4].*, .port = port } };
}