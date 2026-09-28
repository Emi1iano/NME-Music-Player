const std = @import("std");
const net = std.Io.net;
const builtin = @import("builtin");
const ClientCode = @import("server").Networks.ClientCode;

const Io = std.Io;

// Goal for now
// Connect two clients to allow talk between the two

// send initial message to server
// recieve reciever ip
// attempt to connect to reciever ip
// if fails fall back to relaying
var clientState: Networks.ClientState = undefined;

const Networks = struct {
    const ClientState = struct {
        client_socket: net.Socket = undefined,
        server_ip: net.IpAddress = undefined,
        reciever_public_ip: ?net.IpAddress = null,
        reciever_local_ip: ?net.IpAddress = null,
        key: [8]u8 = undefined,
        lock: std.Io.Mutex = .init,


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
        fn send(self: *ClientState, io: Io, data: []u8) !void {
            //TODO: MAKE THIS BETTER
            const ip = if (self.reciever_public_ip == null) self.server_ip else self.reciever_public_ip.?;
            try self.client_socket.send(io, &ip, data);
        }
        pub fn parseInitialResponse(self: *ClientState, buffer: [12]u8) !void {
            self.reciever_public_ip = parseRecieverIp(buffer[0..6]);
            self.reciever_local_ip = parseRecieverIp(buffer[6..12]);
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
        fn parseRecieverIp(bytes: []const u8) net.IpAddress {
            var port: u16 = 0;
            port |= bytes[4];
            port <<= 8;
            port |= bytes[5];
            return .{ .ip4 = .{ .bytes = bytes[0..4].*, .port = port } };
        }
        fn getKey(self: ClientState, io: Io) !void {
            self.key = FileManager.getKey(io) catch unreachable;
        }

    }; 
    const Client = struct {
        // for Peer to Peer connection
        const P2P = struct {
            fn start(io: Io) !void {
                std.debug.print("public: {any}\n", .{clientState.reciever_public_ip.?});
                var thread = try std.Thread.spawn(.{}, listen, .{ io });
                try sending(io);
                thread.join();
            }
            fn sending(io: Io) !void {
                for (0..20) |_| {
                    try clientState.client_socket.send(io, &clientState.reciever_local_ip.?, "LOCAL IP");
                    try clientState.client_socket.send(io, &clientState.reciever_public_ip.?, "PUBLIC IP");
                    try io.sleep(.fromMilliseconds(100), .awake);
                }
            }
            fn listen(io: Io) !void {
                var buffer: [1024]u8 = undefined;
                while (true) {
                    const message = try clientState.client_socket.receive(io, &buffer);
                    std.debug.print("recieved: {s}\n", .{message.data[1..]});
                    //const code = try ClientCode.getCode(message.data[0]);
                    // switch (code) {
                    //     .INITIAL => {
                    //         if (message.data.len == 13) {
                    //             try clientState.parseInitialResponse(message.data[1..13].*);
                    //             print(io, "Already initiated\n", .{});
                    //         }
                    //     },
                    //     .TEXT => {
                    //         std.debug.print("{s}\n", .{message.data[1..]});
                    //     },
                    //     .P2P => {
                    //         //try clientState.lock.lock(io);
                    //         if (std.mem.eql(u8, message.data[1..], "LOCAL IP")) {
                    //             //try clientState.client_socket.send(io, &clientState.reciever_local_ip.?, "\x03ACK LOCAL IP 1");
                    //             //try clientState.client_socket.send(io, &clientState.reciever_public_ip.?, "\x03ACK LOCAL IP 2");
                    //         } else if (std.mem.eql(u8, message.data[1..], "PUBLIC IP")) {
                    //             //try clientState.client_socket.send(io, &clientState.reciever_local_ip.?, "\x03ACK PUBLIC IP 1");
                    //             //try clientState.client_socket.send(io, &clientState.reciever_public_ip.?, "\x03ACK PUBLIC IP 2");
                    //         }
                    //         //clientState.lock.unlock(io);
                    //     },
                    //     else => {
                    //         std.debug.print("Code not handled: {b}\n", .{message.data[0]});
                    //     }
                    // }
                }
            }
        };
        // if P2P fails rely on server
        const Relaying = struct {
            fn start(io: Io) !void {
                _ = io;
            }
        };
        fn start(io: Io) !void {
            try initialMessage(io);
            try initialResponse(io);

            try P2P.start(io);
            try Relaying.start(io);
        }
        fn initialMessage(io: Io) !void {
            var message: [15]u8 = undefined;
            // client code
            message[0] = @intFromEnum(ClientCode.INITIAL);
            // local ip
            @memcpy(message[1..7], &LocalIp.ipToBuf(try LocalIp.getLocalIp(io), clientState.client_socket.address.getPort()));
            // key
            @memcpy(message[7..15], &clientState.key);

            try clientState.send(io, &message);
        }
        fn initialResponse(io: Io) !void {
            var buffer: [1024]u8 = undefined;
            const message = try clientState.client_socket.receive(io, &buffer);
            const code = try ClientCode.getCode(message.data[0]);
            switch (code) {
                .INITIAL => {
                    if (message.data.len == 13) {
                        try clientState.parseInitialResponse(message.data[1..13].*);
                        std.debug.print("Initial message: Other Client Public IP: {any} Local IP: {any}\n", .{clientState.reciever_public_ip.?, clientState.reciever_local_ip.?});
                    }
                },
                else => {
                    std.debug.print("Code not handled: {b} {s}\n", .{message.data[0], message.data[1..]});
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
                        return net.IpAddress.parse("0.0.0.0", 0) catch unreachable;
                    },
                }
            }
            fn getLocalIpWindows(io: std.Io) ![4]u8 {
                var result: [4]u8 = undefined;
                var child = try std.process.spawn(io, .{ .argv = &.{"ipconfig"}, .stdout = .pipe });

                var buffer: [1024]u8 = undefined;
                var wbuffer: [1024*2]u8 = undefined;
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
const FileManager = struct {
    fn getKey(io: Io) ![8]u8 {
        _ = io;
        const result: [8]u8 = [_]u8{'5'} ** 8;
        std.debug.print("Do getKey function\n", .{});
        return result;
    }
};

pub fn main(init: std.process.Init) !void {
    clientState = .init(init.io);
    defer clientState.deinit(init.io);
    try Networks.Client.start(init.io); 
}

var lock = std.Io.Mutex.init;
fn print(io: Io, comptime fmt: []const u8, args: anytype) void {
    lock.lock(io) catch unreachable;
    std.debug.print("\x1b[1A" ++ fmt ++ "\x1b[1E", args);
    lock.unlock(io);
}