const std = @import("std");
const Io = std.Io;

const PORT: u16 = 5252;
const MAX_CONNECTIONS: usize = 16;
// A client that hasn't been paired within this many seconds is dropped.
const TIMEOUT_NS: i96 = 60 * std.time.ns_per_s;

const Connection = struct {key: [8]u8 = undefined, ip: std.Io.net.IpAddress, timestamp: std.Io.Timestamp};
// CLIENTS is only touched by the main thread; the worker thread only reads CLIENTS_SIZE.
var CLIENTS: [MAX_CONNECTIONS]?Connection = [_]?Connection{null} ** MAX_CONNECTIONS;
var CLIENTS_SIZE = std.atomic.Value(usize).init(0);
const CONNECTIONS = struct {
    fn add(conn: Connection) !void {
        for (&CLIENTS) |*client| {
            if (client.* == null) continue;
            // Same client retrying: refresh its key and timestamp instead of failing.
            if (client.*.?.ip.eql(&conn.ip)) {
                client.* = conn;
                return;
            }
        }
        for (&CLIENTS) |*client| {
            if (client.* == null) {
                client.* = conn;
                _ = CLIENTS_SIZE.fetchAdd(1, .monotonic);
                return;
            }
        } else {
            return error.TooManyClients;
        }
    }
    fn remove(i: usize) void {
        if (CLIENTS[i] == null) return;
        CLIENTS[i] = null;
        _ = CLIENTS_SIZE.fetchSub(1, .monotonic);
    }
    // Drops clients that have been waiting longer than TIMEOUT_NS.
    fn cleanUp(now: std.Io.Timestamp) void {
        for (0..CLIENTS.len) |i| {
            const client = CLIENTS[i] orelse continue;
            if (now.nanoseconds - client.timestamp.nanoseconds > TIMEOUT_NS) remove(i);
        }
    }
    fn pairUp(io: Io, server_socket: *std.Io.net.Socket) void {
        for (0..CLIENTS.len) |x| {
            for (x+1..CLIENTS.len) |y| {
                if (CLIENTS[x] == null or CLIENTS[y] == null) continue;
                if (std.mem.eql(u8, &CLIENTS[x].?.key, &CLIENTS[y].?.key)) {
                    const client1 = CLIENTS[x].?.ip;
                    const client2 = CLIENTS[y].?.ip;

                    // Free the slots first so a failed send can't leave them stuck.
                    remove(x);
                    remove(y);

                    var buffer1: [6]u8 = undefined;
                    var buffer2: [6]u8 = undefined;
                    server_socket.send(io, &client1, formatIp(client2, &buffer1)) catch |err|
                        std.debug.print("send to client1 failed: {}\n", .{err});
                    server_socket.send(io, &client2, formatIp(client1, &buffer2)) catch |err|
                        std.debug.print("send to client2 failed: {}\n", .{err});
                    break;
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
    const ip = try std.Io.net.IpAddress.parse("0.0.0.0", PORT);
    std.debug.print("Server Opened...\n", .{});
    var server_socket = try ip.bind(init.io, .{ .mode = .dgram });
    defer server_socket.close(init.io);

    var buffer: [1024]u8 = undefined;
    while (true) {
        const message = server_socket.receive(init.io, &buffer) catch |err| {
            std.debug.print("receive failed: {}\n", .{err});
            continue;
        };
        if (message.data.len != 8) continue;
        // Pairing replies are IPv4-only (4 bytes + port), so ignore IPv6 senders.
        if (message.from != .ip4) continue;
        if (!isDigits(message.data)) continue;

        const b = message.from.ip4.bytes;
        std.debug.print("{d}.{d}.{d}.{d}:{d} Connected with key: {s}\n", .{b[0], b[1], b[2], b[3], message.from.getPort(), message.data});

        const now = std.Io.Timestamp.now(init.io, .awake);
        CONNECTIONS.cleanUp(now);

        var conn = Connection {.ip = message.from, .timestamp = now};
        @memcpy(&conn.key, message.data[0..8]);
        CONNECTIONS.add(conn) catch |err| {
            std.debug.print("rejected client: {}\n", .{err});
            continue;
        };
        CONNECTIONS.pairUp(init.io, &server_socket);
    }
}
fn workerThread(init: std.process.Init) !void {
    while (true) {
        std.debug.print("size: {d}\n", .{CLIENTS_SIZE.load(.monotonic)});

        try init.io.sleep(.fromSeconds(1), .awake);
    }
}
fn isDigits(data: []const u8) bool {
    for (data) |c| if (c < '0' or c > '9') return false;
    return true;
}
fn formatIp(ip: std.Io.net.IpAddress, buffer: *[6]u8) []u8 {
    @memcpy(buffer[0..4], &ip.ip4.bytes);
    const port = ip.ip4.port;
    buffer[4] = @truncate(port >> 8);
    buffer[5] = @truncate(port);
    return buffer;
}
