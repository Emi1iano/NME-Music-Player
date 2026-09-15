const std = @import("std");
const Io = std.Io;

const MAX_CONNECTIONS: usize = 16;
const Connection = struct {key: [8]u8 = undefined, ip: std.Io.net.IpAddress, timestamp: std.Io.Timestamp};
var CLIENTS: [MAX_CONNECTIONS]?Connection = [_]?Connection{null} ** MAX_CONNECTIONS;
var CLIENTS_SIZE: usize = 0;
const CONNECTIONS = struct {
    fn add(conn: Connection) !void {
        for (CLIENTS) |client| {
            if (client == null) continue;
            if (client.?.ip.eql(&conn.ip)) return error.ClientAlreadyWaiting;
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
                    const client1 = CLIENTS[x].?.ip;
                    const client2 = CLIENTS[y].?.ip;
                    
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
        
        if (message.data.len == 8) {
            const b = message.from.ip4.bytes;
            std.debug.print("{d}.{d}.{d}.{d}:{d} Connected with key: {s}\n", .{b[0], b[1], b[2], b[3], message.from.getPort(), message.data});

            var conn = Connection {.ip = message.from, .timestamp = std.Io.Timestamp.now(init.io, .awake)};
            @memcpy(&conn.key, message.data[0..8]);
            try CONNECTIONS.add(conn);
            try CONNECTIONS.pairUp(init.io, &server_socket);
        }
    }
}
fn workerThread(init: std.process.Init) !void {
    while (true) {
        std.debug.print("size: {d}\n", .{CLIENTS_SIZE});

        try init.io.sleep(.fromSeconds(1), .awake);
    }
}
fn formatIp(ip: std.Io.net.IpAddress, buffer: []u8) []u8 {
    @memcpy(buffer[0..4], &ip.ip4.bytes);
    buffer[4] = 0x0; buffer[5] = 0x0;

    const port = ip.ip4.port;
    buffer[4] |= @truncate(port >> 8);
    buffer[5] |= @truncate(port);

    std.debug.print("{b:0>16} : {b:0>8}{b:0>8}\n", .{ip.ip4.port, buffer[4], buffer[5]});
    return buffer;
}