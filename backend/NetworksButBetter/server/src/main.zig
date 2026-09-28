const std = @import("std");
const net = std.Io.net;
const Io = std.Io;

// Start server wait for connections
// Will recieve 6bytes for local ip 8bytes for key
// Clients attempt to p2p
// If fails use tcp connection between server

//1st byte will be a code

var serverState: Networks.ServerState = .{};

pub const Networks = struct {
    const ClientConnection = struct {
        public_ip: std.Io.net.IpAddress = undefined,
        local_ip: ?std.Io.net.IpAddress = null,
        key: [8]u8 = undefined,
        client_code: ClientCode = undefined,

        pub fn init(buffer: [15]u8, public_ip: std.Io.net.IpAddress) !ClientConnection {
            const code = try ClientCode.getCode(buffer[0]);
            const local_ip = getLocalIp(buffer[1..7]);
            const key = buffer[7..15];

            return .{ .public_ip = public_ip, .local_ip = local_ip, .key = key.*, .client_code = code };
        }
        fn getLocalIp(bytes: []const u8) std.Io.net.IpAddress {
            var port: u16 = 0;
            port |= bytes[4];
            port <<= 8;
            port |= bytes[5];
            return .{ .ip4 = .{ .bytes = bytes[0..4].*, .port = port } };
        }
    };
    pub const ClientCode = enum(u8) {
        INITIAL = 0x0,
        UDP = 0x1,
        TCP = 0x2,
        TEXT = 0x3,
        P2P = 0x4,

        pub fn getCode(byte: u8) !ClientCode {
            switch (byte) {
                0x0 => return ClientCode.INITIAL,
                0x1 => return ClientCode.UDP,
                0x2 => return ClientCode.TCP,
                0x3 => return ClientCode.TEXT,
                0x4 => return ClientCode.P2P,
                else => {
                    std.debug.print("Invalid Code: {b}", .{byte});
                    return error.InvalidCode;
                },
            }
        }
    };
    const ServerState = struct {
        clients: [16]?ClientConnection = [_]?ClientConnection{null} ** 16,
        server_socket: net.Socket = undefined,
        clients_size: u8 = 0,
        lock: std.Io.Mutex = .init,

        pub fn add(self: *ServerState, io: Io, connection: ClientConnection) !void {
            try self.lock.lock(io);
            defer self.lock.unlock(io);
            for (&self.clients) |*client| {
                if (client.* == null) continue;
                if (client.*.?.public_ip.eql(&connection.public_ip)) {
                    client.* = connection;
                    return;
                }
            }
            for (&self.clients) |*client| {
                if (client.* == null) {
                    client.* = connection;
                    self.clients_size += 1;
                    return;
                }
            } else {
                return error.TooManyClients;
            }
        }
        pub fn pairUp(self: *ServerState, io: Io) !void {
            try self.lock.lock(io);
            defer self.lock.unlock(io);
            for (&self.clients, 1..) |*x, i| {
                for (self.clients[i..]) |*y| {
                    if (x.* == null or y.* == null) continue;
                    if (!std.mem.eql(u8, &x.*.?.key, &y.*.?.key)) continue;

                    try self.initialResponse(io, x.*.?.public_ip, y.*.?);
                    try self.initialResponse(io, y.*.?.public_ip, x.*.?);

                    x.* = null;
                    y.* = null;
                    self.clients_size -= 2;
                }
            }
        }
        pub fn initialResponse(self: *ServerState, io: Io, ip: net.IpAddress, other: ClientConnection) !void {
            var response: [13]u8 = undefined;
            response[0] = @intFromEnum(ClientCode.INITIAL);
            @memcpy(response[1..13], &bothIpToBuf(other));

            try self.server_socket.send(io, &ip, &response);
        }
        fn bothIpToBuf(client: ClientConnection) [12]u8 {
            var result: [12]u8 = undefined;

            @memcpy(result[0..6], &ipToBuf(client.public_ip));
            @memcpy(result[6..12], &ipToBuf(client.local_ip.?));

            return result;
        }
        fn ipToBuf(ip: net.IpAddress) [6]u8 {
            var result: [6]u8 = [_]u8{0} ** 6;
            @memcpy(result[0..4], &ip.ip4.bytes);

            result[4] |= @truncate(ip.getPort() >> 8);
            result[5] |= @truncate(ip.getPort());

            return result;
        }
    };
    // TODO: for TCP
    const ClientState = struct {};
    const Server = struct {
        fn listen(io: Io) !void {
            serverState.server_socket = try bindSocket(io);
            defer serverState.server_socket.close(io);

            var messageBuf: [1024]u8 = undefined;
            while (serverState.server_socket.receive(io, &messageBuf)) |message| {
                if (message.data.len != 15) {
                    print(io, "Invalid Client Message: {s}\n", .{message.data});
                    continue;
                }
                const connection = Networks.ClientConnection.init(message.data[0..15].*, message.from) catch |err| switch (err) {
                    error.InvalidCode => {
                        print(io, "Invalid Client Code: {b}\n", .{message.data[0]});
                        continue;
                    },
                    else => unreachable,
                };
                const p = connection.public_ip.ip4;
                const l = connection.local_ip.?.ip4;
                print(io, "Public: {d}.{d}.{d}.{d}:{d}, Local: {d}.{d}.{d}.{d}:{d} Connected with key: {s} with code: {any}\n",
                 .{ p.bytes[0], p.bytes[2], p.bytes[2], p.bytes[3], p.port, l.bytes[0], l.bytes[1], l.bytes[2], l.bytes[3], l.port, connection.key, connection.client_code});

                try serverState.add(io, connection);
                try serverState.pairUp(io);
            } else |_| {}
        }
        fn workerThread(io: Io) !void {
            std.debug.print("size: {d}\n", .{serverState.clients_size});
            while (true) {
                print(io, "size: {d}", .{serverState.clients_size});

                try io.sleep(.fromMilliseconds(100), .awake);
            }
        }
        fn bindSocket(io: Io) !std.Io.net.Socket {
            const ip = try std.Io.net.IpAddress.parse("192.168.0.62", 5252);
            std.debug.print("Server Opened...\n", .{});
            return try ip.bind(io, .{ .mode = .dgram });
        }
    };
};

pub fn main(init: std.process.Init) !void {
    const thread = try std.Thread.spawn(.{}, Networks.Server.workerThread, .{init.io});
    try Networks.Server.listen(init.io);
    thread.join();
}

var lock = std.Io.Mutex.init;
fn print(io: Io, comptime fmt: []const u8, args: anytype) void {
    lock.lock(io) catch unreachable;
    std.debug.print("\x1b[1A" ++ fmt ++ "\x1b[1E", args);
    lock.unlock(io);
}

test "ClientConnection" {
    const string1: []const u8 = &.{ 0x1, 192, 62, 0, 100, 0x12, 0x12, '1', '2', '3', '4', '5', '6', '7', '8' };
    const string2: []const u8 = &.{ 0x2, 192, 62, 0, 100, 0x12, 0x12, '1', '2', '3', '4', '5', '6', '7', '9' };

    const test1 = Networks.ClientConnection.init(string1[0..15].*, undefined);
    std.debug.print("{any}\n", .{test1});
    const test2 = Networks.ClientConnection.init(string2[0..15].*, undefined);
    std.debug.print("{any}\n", .{test2});
}
