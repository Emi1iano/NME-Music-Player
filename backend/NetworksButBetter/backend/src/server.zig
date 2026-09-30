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

        pub fn init(buffer: [14]u8, public_ip: std.Io.net.IpAddress) ClientConnection {
            const local_ip = getLocalIp(buffer[0..6]);
            const key = buffer[6..14];

            return .{ .public_ip = public_ip, .local_ip = local_ip, .key = key.* };
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
        ACK = 0x5,
        RELAY = 0x6,
        NONE = 0x7,
        

        pub fn getCode(byte: u8) ClientCode {
            switch (byte) {
                0x0 => return ClientCode.INITIAL,
                0x1 => return ClientCode.UDP,
                0x2 => return ClientCode.TCP,
                0x3 => return ClientCode.TEXT,
                0x4 => return ClientCode.P2P,
                0x5 => return ClientCode.ACK,
                0x6 => return ClientCode.RELAY,
                else => return ClientCode.NONE,
            }
        }
        pub fn getByte(comptime code: ClientCode) [1]u8 {
            switch (code) {
                .INITIAL => return .{0x00},
                .UDP => return .{0x01},
                .TCP => return .{0x02},
                .TEXT => return .{0x03},
                .P2P => return .{0x04},
                .ACK => return .{0x05},
                .RELAY => return .{0x06},
                else => unreachable,
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
            print(io, "sending {any} to {any}\n", .{other.public_ip, ip});

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
    const Temp = struct {
        var relayClients: [16]?RelayClient = [_]?RelayClient{null} ** 16;
        var size: usize = 0;

        const RelayClient = struct {
            from_ip: net.IpAddress,
            key: [8]u8,

            fn init(ip: net.IpAddress, key: [8]u8) RelayClient {
                return .{
                    .from_ip = ip,
                    .key = key,
                };
            }
        };
        fn add(new: RelayClient) !void {
            //check if exists
            for (&relayClients) |*client| {
                if (client.* != null) {
                    //std.debug.print("already tracked relay client\n", .{});
                    if (client.*.?.from_ip.eql(&new.from_ip)) return;
                }
            } 
            for (&relayClients) |*client| {
                if (client.* == null) {
                    //std.debug.print("added new relay client\n", .{});
                    client.* = new;
                    size += 1;
                    return;
                }
            } else {
                return error.TooManyClients;
            }
        }
        fn remove(io: Io, ip: net.IpAddress) !void {
            for (&relayClients) |*client| {
                if (client.* != null) {
                    if (client.*.?.from_ip.eql(&ip)) {
                        const key = client.*.?.key;
                        for (&relayClients) |*client1| {
                            if (std.mem.eql(u8, &key, &client1.*.?.key)) {
                                try serverState.server_socket.send(io, &client.*.?.from_ip, "EXIT");
                                try serverState.server_socket.send(io, &client1.*.?.from_ip, "EXIT");
                                client.* = null;
                                client1.* = null;
                                size -= 2;
                                return;
                            }
                        }
                    }
                }
            }
        }
        fn resolve(io: Io, ip: net.IpAddress, key: [8]u8, data: []u8) !void {
            for (&relayClients) |*client| {
                if (client.* != null) {
                    if (!client.*.?.from_ip.eql(&ip) and std.mem.eql(u8, &client.*.?.key, &key)) {
                        std.debug.print("Sending data between relay clients\n", .{});
                        try serverState.server_socket.send(io, &client.*.?.from_ip, data);
                    }
                }
            }
        }
    };
    const Server = struct {
        fn listen(io: Io) !void {
            serverState.server_socket = try bindSocket(io);
            defer serverState.server_socket.close(io);

            var messageBuf: [1024]u8 = undefined;
            while (serverState.server_socket.receive(io, &messageBuf)) |message| {
                print(io, "Client Size {d}\n", .{serverState.clients_size});
                const code = ClientCode.getCode(message.data[0]);
                switch (code) {
                    .INITIAL => {
                        if (message.data.len != 15) {
                            print(io, "Invalid Client Message: {s}\n", .{message.data});
                            continue;
                        }
                        const connection = Networks.ClientConnection.init(message.data[1..15].*, message.from);
                        const p = connection.public_ip.ip4;
                        const l = connection.local_ip.?.ip4;
                        print(io, "Public: {d}.{d}.{d}.{d}:{d}, Local: {d}.{d}.{d}.{d}:{d} Connected with key: {s}\n", .{ p.bytes[0], p.bytes[1], p.bytes[2], p.bytes[3], p.port, l.bytes[0], l.bytes[1], l.bytes[2], l.bytes[3], l.port, connection.key });

                        try serverState.add(io, connection);
                        try serverState.pairUp(io);
                    },
                    .RELAY => {
                        if (message.data.len == 14) {
                            if (std.mem.eql(u8, message.data[10..14], "EXIT")) {
                                try Temp.remove(io, message.from);
                                print(io, "Relay Size {d}\n", .{Temp.size});
                                continue;
                            }
                        }
                        
                        try Temp.add(.init(message.from, message.data[1..9].*));
                        print(io, "Relay Size {d}\n", .{Temp.size});
                        try Temp.resolve(io, message.from, message.data[1..9].*, message.data[9..]);
                    },
                    else => {
                        print(io, "Code not implemented\n", .{});
                    }
                }
            } else |_| {}
        }
        fn workerThread(io: Io) !void {
            std.debug.print("size: {d}\n", .{serverState.clients_size});
            while (true) {
                //print(io, "size: {d}", .{serverState.clients_size});

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
    std.debug.print(fmt, args);
    //std.debug.print("\x1b[1A" ++ fmt ++ "\x1b[1E", args);
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
