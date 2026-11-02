 const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Shared = @import("shared.zig");
const Code = Shared.Code;
const Local_Testing = @import("csimple.zig").Local_Testing;

const CLIENT_TIMEOUT_TIME = 5;
const RELAY_TIMEOUT_TIME = 5;

pub fn main(init: std.process.Init) !void {
    var server = try Server.init(init.io);
    var thread = try std.Thread.spawn(.{}, Server.cleanup, .{&server});
    try server.listen();
    thread.join();
    server.deinit();
}
const Server = struct {
    clients: Clients,
    relay: Clients,
    io: Io,
    socket: net.Socket,
    const Clients = struct {
        gpa: std.heap.ArenaAllocator,
        list: std.ArrayList(?Client),
        name: []const u8,
        amount: usize,
        time: usize,
        lock: Io.Mutex = .init,
        const Client = struct {
            key: [8]u8,
            from: net.IpAddress,
            timestamp: Io.Timestamp,
            local: [6]u8,

            fn initFormat(self: *@This()) [13]u8 {
                var result: [13]u8 = undefined;
                result[0] = Code.getByte(.INITIAL)[0];
                @memcpy(result[1..5], &self.from.ip4.bytes);
                std.mem.writeInt(u16, result[5..7], self.from.getPort(), .little);
                @memcpy(result[7..13], &self.local);
                return result;
            }
        };
        fn init(time: usize, name: []const u8) @This() {
            return .{
                .gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .list = .empty,
                .amount = 0,
                .time = time,
                .name = name,
            };
        }
        fn deinit(self: *@This()) void {
            self.gpa.deinit();
        }
        fn add(self: *@This(), io: Io, ip: net.IpAddress, local: []const u8, key: []u8) void {
            self.lock.lock(io) catch unreachable;
            defer self.lock.unlock(io);
            for (self.list.items) |*x| {
                if (x.* == null) continue;
                if (x.*.?.from.eql(&ip)) {
                    x.*.?.timestamp = Io.Timestamp.now(io, .awake);
                    x.*.?.key = key[0..8].*;
                    return;
                }
            }
            const client: Client = .{ .from = ip, .local = local[0..6].*, .key = key[0..8].*, .timestamp = Io.Timestamp.now(io, .awake) };
            for (self.list.items) |*x| {
                if (x.* == null) {
                    x.* = client;
                    self.amount += 1;
                    std.debug.print("{s} size: {d}\n", .{ self.name, self.amount });
                    return;
                }
            }

            self.list.append(self.gpa.allocator(), client) catch |err| {
                //TODO maybe send a message to client
                std.debug.print("Failed to add client in {s}: {any}\n", .{ self.name, err });
                return;
            };
            self.amount += 1;
            std.debug.print("{s} size: {d}\n", .{ self.name, self.amount });
        }
        fn pair(self: *@This(), io: Io, socket: net.Socket) void {
            self.lock.lock(io) catch unreachable;
            defer self.lock.unlock(io);
            if (self.amount < 2) return;
            for (self.list.items, 1..) |*x, i| {
                for (self.list.items[i..]) |*y| {
                    if (x.* == null or y.* == null) continue;
                    if (!std.mem.eql(u8, &x.*.?.key, &y.*.?.key)) continue;

                    send(io, socket, x.*.?.from, &y.*.?.initFormat());
                    send(io, socket, y.*.?.from, &x.*.?.initFormat());

                    x.* = null;
                    y.* = null;
                    self.amount -= 2;
                    std.debug.print("{s} size: {d}\n", .{ self.name, self.amount });
                    return;
                }
            }
        }
        fn sendMessage(self: *@This(), io: Io, socket: net.Socket, from: net.IpAddress, key: []u8, data: []const u8) void {
            self.lock.lock(io) catch unreachable;
            defer self.lock.unlock(io);
            self.sendMessageUnlocked(io, socket, from, key, data);
        }
        fn sendMessageUnlocked(self: *@This(), io: Io, socket: net.Socket, from: net.IpAddress, key: []u8, data: []const u8) void {
            for (self.list.items) |*x| {
                if (x.* == null) continue;
                if (!std.mem.eql(u8, key, &x.*.?.key)) continue;
                if (from.eql(&x.*.?.from)) continue;
                socket.send(io, &x.*.?.from, data) catch |err| {
                    std.debug.print("Failed to send message: {any}\n", .{err});
                };
            }
        }
        fn isRegistered(self: *@This(), io: Io, from: net.IpAddress, key: []const u8) bool {
            self.lock.lock(io) catch unreachable;
            defer self.lock.unlock(io);
            for (self.list.items) |x| {
                if (x == null) continue;
                if (from.eql(&x.?.from) and std.mem.eql(u8, &x.?.key, key)) return true;
            }
            return false;
        }
        fn remove(self: *@This(), io: Io, key: []const u8) void {
            self.lock.lock(io) catch unreachable;
            defer self.lock.unlock(io);
            for (self.list.items) |*x| {
                if (x.* == null) continue;
                if (std.mem.eql(u8, key, &x.*.?.key)) {
                    x.* = null;
                    self.amount -= 1;
                    std.debug.print("{s} size: {d}\n", .{ self.name, self.amount });
                }
            }
        }
        fn updateTime(self: *@This(), io: Io, key: []const u8) void {
            self.lock.lock(io) catch unreachable;
            defer self.lock.unlock(io);
            for (self.list.items) |*x| {
                if (x.* == null) continue;
                if (std.mem.eql(u8, key, &x.*.?.key)) {
                    x.*.?.timestamp = Io.Timestamp.now(io, .awake);
                }
            }
        }
    };
    fn init(io: Io) !@This() {
        return .{
            .clients = Clients.init(CLIENT_TIMEOUT_TIME, "Client"),
            .relay = Clients.init(RELAY_TIMEOUT_TIME, "Relay"),
            .io = io,
            .socket = try bindSocket(io),
        };
    }
    fn deinit(self: *@This()) void {
        self.relay.deinit();
        self.clients.deinit();
        self.socket.close(self.io);
    }
    fn send(io: Io, socket: net.Socket, to: net.IpAddress, data: []const u8) void {
        socket.send(io, &to, data) catch |err| {
            std.debug.print("Failed to send message: {any}\n", .{err});
        };
    }
    fn listen(self: *@This()) !void {
        var buf: [Shared.MTU_SIZE]u8 = undefined;

        while (true) {
            const message = self.socket.receive(self.io, &buf) catch |err| {
                std.debug.print("Error recieving message: {any}\n", .{err});
                continue;
            };
            if (message.data.len < 2) continue;
            const code = Code.get(message.data[0]);
            const data = message.data[1..];

            switch (code) {
                .INITIAL => {
                    if (data.len != 14) continue;
                    var ipBuf: [24]u8 = undefined;
                    const d = message.from.ip4.bytes;
                    const ip = try std.fmt.bufPrint(ipBuf[0..], "{d}.{d}.{d}.{d}:{d}", .{ d[0], d[1], d[2], d[3], message.from.getPort() });
                    std.debug.print("Initial message from {s}\nWith local ip: {x}\nAnd key: {s}\n", .{ ip, data[0..6], data[6..14] });
                    self.clients.add(self.io, message.from, data[0..6], data[6..14]);
                    self.clients.pair(self.io, self.socket);
                },
                .RELAY_INITITAL => {
                    if (data.len != 8) continue;
                    self.relay.add(self.io, message.from, &@as([6]u8, @splat(0)), data[0..8]);
                },
                //TEST -------------------------
                // make this better
                .RELAY => {
                    if (data.len < 9) continue;
                    if (!self.relay.isRegistered(self.io, message.from, data[0..8])) continue;
                    self.relay.sendMessage(self.io, self.socket, message.from, data[0..8], data[8..]);
                    self.relay.updateTime(self.io, data[0..8]);
                },
                .RELAY_DISCONNECT => {
                    if (data.len < 8) continue;
                    if (!self.relay.isRegistered(self.io, message.from, data[0..8])) continue;
                    self.relay.sendMessage(self.io, self.socket, message.from, data[0..8], data[8..]);
                    self.relay.remove(self.io, data[0..8]);
                },
                .TEXT => std.debug.print("{s}\n", .{data}),
                else => std.debug.print("Code not handled: {any}\n", .{code}),
            }
        }
    }
    fn cleanup(self: *@This()) void {
        while (true) {
            self.clients.lock.lock(self.io) catch unreachable;
            for (self.clients.list.items) |*c| {
                if (c.* == null) continue;
                const d = c.*.?.timestamp.untilNow(self.io, .awake);
                if (d.toSeconds() >= self.clients.time) {
                    send(self.io, self.socket, c.*.?.from, &(Code.getByte(.CLIENT_DISCONNECT) ++ c.*.?.key));
                    c.* = null;
                    self.clients.amount -= 1;
                    std.debug.print("Client Size: {d}\n", .{self.clients.amount});
                }
            }
            self.clients.lock.unlock(self.io);
            self.relay.lock.lock(self.io) catch unreachable;
            for (self.relay.list.items) |*c| {
                if (c.* == null) continue;
                const d = c.*.?.timestamp.untilNow(self.io, .awake);
                if (d.toSeconds() >= self.relay.time) {
                    for (self.relay.list.items) |*x| {
                        if (x.* == null) continue;
                        if (c.*.?.from.eql(&x.*.?.from)) continue;
                        if (!std.mem.eql(u8, &c.*.?.key, &x.*.?.key)) continue;
                        self.relay.sendMessageUnlocked(self.io, self.socket, c.*.?.from, &c.*.?.key, &(Code.getByte(.CLIENT_DISCONNECT) ++ c.*.?.key));
                        self.relay.sendMessageUnlocked(self.io, self.socket, x.*.?.from, &x.*.?.key, &(Code.getByte(.CLIENT_DISCONNECT) ++ x.*.?.key));

                        x.* = null;
                        self.relay.amount -= 1;
                    }
                    c.* = null;
                    self.relay.amount -= 1;
                    std.debug.print("{s} size: {d}\n", .{ self.relay.name, self.relay.amount });
                    break;
                }
            }
            self.relay.lock.unlock(self.io);
            self.io.sleep(.fromMilliseconds(500), .awake) catch unreachable;
        }
    }
    fn bindSocket(io: Io) !std.Io.net.Socket {
        const ip = if (Local_Testing) try std.Io.net.IpAddress.parse("172.28.41.169", 5252) else try std.Io.net.IpAddress.parse("192.168.0.62", 5252);
        std.debug.print("Server Opened...\n", .{});
        return try ip.bind(io, .{ .mode = .dgram });
    }
};
