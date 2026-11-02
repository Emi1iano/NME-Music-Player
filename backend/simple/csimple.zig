const std = @import("std");
const Io = std.Io;
const net = Io.net;
const builtin = @import("builtin");
const Shared = @import("shared.zig");
const MTU_BUF = [Shared.MTU_SIZE]u8;
const Code = Shared.Code;

pub const Local_Testing: bool = false;
const Testing_Relay_Mode: bool = false;
const Chat_Mode: bool = true;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);

    try start(init.io, args[1..]);
}
pub fn start(io: std.Io, args: []const []const u8) !void {
    var client = try Client.init(io);
    try client.start();
    _ = args;
}
const Client = struct {
    serverIp: net.IpAddress,
    clientIp: net.IpAddress,
    client_socket: net.Socket,
    resolvedIp: ?net.IpAddress,
    o_localIp: ?net.IpAddress,
    o_publicIp: net.IpAddress,
    key: [8]u8,
    io: Io,
    got_info: std.atomic.Value(bool) = .init(false),
    chat_disconnect: std.atomic.Value(bool) = .init(false),
    state: std.atomic.Value(Mode) = .init(.Punching),
    const Mode = enum(u8) {
        Punching,
        Claiming,
        P2P,
        Relay,
    };
    fn init(io: Io) !@This() {
        const socket = try getClientSocket(io);
        return @This(){
            .serverIp = try getServerIp(),
            .clientIp = socket.address,
            .client_socket = socket,
            .resolvedIp = null,
            .o_localIp = null,
            .o_publicIp = undefined,
            .key = getKey(),
            .io = io,
        };
    }
    fn start(self: *@This()) !void {
        var thread = try std.Io.concurrent(self.io, listen, .{self});

        try self.sendInitialMessage();
        try self.resolveIp();
        if (Chat_Mode) {
            try self.chatMode();
            _ = thread.cancel(self.io) catch |err| {
                std.debug.print("Listener thread canceled: {any}\n", .{err});
            };
            return;
        }

        _ = thread.await(self.io) catch |err| {
            std.debug.print("Listener thread canceled: {any}\n", .{err});
        };
    }
    fn listen(self: *@This()) !void {
        var buf: MTU_BUF = undefined;
        while (true) {
            const message = self.client_socket.receive(self.io, &buf) catch |err| {
                if (err == error.Canceled) return;
                std.debug.print("Error receiving message {any}\n", .{err});
                continue;
            };
            if (message.data.len < 2) continue;
            const code = Code.get(message.data[0]);
            const d = message.data[1..];
            switch (code) {
                .INITIAL => {
                    if (!message.from.eql(&self.serverIp)) continue;
                    if (d.len != 12) continue;
                    if (self.got_info.load(.acquire)) continue;
                    std.debug.print("Other client public ip: {d}.{d}.{d}.{d}:{d}\n", .{ d[0], d[1], d[2], d[3], std.mem.readInt(u16, d[4..6], .little) });
                    self.o_publicIp = .{ .ip4 = .{ .bytes = d[0..4].*, .port = std.mem.readInt(u16, d[4..6], .little) } };
                    self.o_localIp = if (@as(u32, @bitCast(d[6..10].*)) == 0) null else .{ .ip4 = .{ .bytes = d[6..10].*, .port = std.mem.readInt(u16, d[10..12], .little) } };
                    self.got_info.store(true, .release);
                },
                .P2P => {
                    if (!self.fromPeer(message.from)) continue;
                    if (!std.mem.eql(u8, d, "Ack")) {
                        if (self.state.load(.acquire) != .Relay) {
                            self.sendTo(message.from, Code.getByte(.P2P) ++ "Ack");
                        }
                        continue;
                    }
                    if (self.state.cmpxchgStrong(.Punching, .Claiming, .acq_rel, .acquire) == null) {
                        self.resolvedIp = message.from;
                        self.state.store(.P2P, .release);
                    }
                },
                .TEXT => {
                    if (!message.from.eql(&self.serverIp) and !self.fromPeer(message.from)) continue;
                    std.debug.print("{s}\n", .{d});
                },
                .CLIENT_DISCONNECT => {
                    if (d.len != 8) continue;
                    if (!std.mem.eql(u8, d, &self.key)) continue;
                    switch (self.state.load(.acquire)) {
                        .P2P => if (!message.from.eql(&self.resolvedIp.?)) continue,
                        .Relay => if (!self.serverIp.eql(&message.from)) continue,
                        else => continue,
                    }
                    std.debug.print("Other Client disconnected.\nPress Enter to exit.\n", .{});
                    self.chat_disconnect.store(true, .release);
                    return;
                },
                else => std.debug.print("Code not handled: {any}, {s}\n", .{ code, d }),
            }
        }
    }
    fn sendTo(self: *@This(), to: net.IpAddress, data: []const u8) void {
        self.client_socket.send(self.io, &to, data) catch |err| {
            std.debug.print("Error sending data: {any}\n", .{err});
        };
    }
    fn fromPeer(self: *@This(), from: net.IpAddress) bool {
        if (!self.got_info.load(.acquire)) return false;
        if (from.eql(&self.o_publicIp)) return true;
        if (self.o_localIp) |l| return from.eql(&l);
        return false;
    }
    fn resolveIp(self: *@This()) !void {
        if (self.chat_disconnect.load(.acquire)) return;
        std.debug.print("Got the info\nStart punching\n", .{});
        for (0..30) |_| {
            if (self.state.load(.acquire) != .Punching) break;
            if (Testing_Relay_Mode) break;
            if (self.o_localIp) |ip| {
                self.sendTo(ip, Code.getByte(.P2P) ++ "Local");
            }
            self.sendTo(self.o_publicIp, Code.getByte(.P2P) ++ "Public");
            try self.io.sleep(.fromMilliseconds(100), .awake);
        }
        if (self.state.cmpxchgStrong(.Punching, .Relay, .acq_rel, .acquire) != null) {
            while (self.state.load(.acquire) != .P2P) {
                try self.io.sleep(.fromMilliseconds(1), .awake);
            }
            std.debug.print("Using P2P\n", .{});
            return;
        }
        std.debug.print("Failed to P2P\nFalling back to Relaying\n", .{});
        self.resolvedIp = self.serverIp;
        var initial: [9]u8 = undefined;
        initial[0] = Code.getByte(.RELAY_INITITAL)[0];
        @memcpy(initial[1..], &self.key);
        for (0..5) |_| {
            self.sendTo(self.resolvedIp.?, &initial);
            try self.io.sleep(.fromMilliseconds(100), .awake);
        }
    }
    fn chatMode(self: *@This()) !void {
        if (self.chat_disconnect.load(.acquire)) return;
        var buffer: [256]u8 = undefined;
        const header: []u8 = blk: switch (self.state.load(.acquire)) {
            .P2P => {
                buffer[0] = Code.getByte(.TEXT)[0];
                break :blk buffer[0..1];
            },
            .Relay => {
                buffer[0] = Code.getByte(.RELAY)[0];
                @memcpy(buffer[1..9], &self.key);
                buffer[9] = Code.getByte(.TEXT)[0];
                break :blk buffer[0..10];
            },
            else => unreachable,
        };
        while (true) {
            const in = cin(self.io, buffer[header.len..]);
            if (self.chat_disconnect.load(.acquire)) break;
            if (std.mem.eql(u8, in, "EXIT")) {
                switch (self.state.load(.acquire)) {
                    .P2P => buffer[0] = Code.getByte(.CLIENT_DISCONNECT)[0],
                    .Relay => {
                        buffer[0] = Code.getByte(.RELAY_DISCONNECT)[0];
                        buffer[9] = Code.getByte(.CLIENT_DISCONNECT)[0];
                    },
                    else => unreachable,
                }
                const m = self.key;
                @memcpy(buffer[header.len .. header.len + m.len], &m);
                self.sendTo(self.resolvedIp.?, buffer[0 .. header.len + m.len]);
                return;
            }
            self.sendTo(self.resolvedIp.?, buffer[0 .. in.len + header.len]);
        }
    }
    // TEST ------------------------------
    // TEST Use proper send like mysend.send
    /// 1 byte code, 6 byte local ip, 8 byte key
    /// locks till initial message is recieved
    fn sendInitialMessage(self: *@This()) !void {
        var buf: [15]u8 = undefined;
        const message = try std.fmt.bufPrint(buf[0..], "{s}{s}{s}", .{ Code.getByte(.INITIAL), try self.getLocalIpAndPort(), &self.key });

        while (!self.got_info.load(.acquire)) {
            if (self.chat_disconnect.load(.acquire)) return;
            self.sendTo(self.serverIp, message);
            try self.io.sleep(.fromSeconds(1), .awake);
        }
    }
    // TEST ------------------------------
    // TEST This is a placeholder
    fn getKey() [8]u8 {
        return @splat('a');
    }
    fn getLocalIpAndPort(self: *@This()) ![6]u8 {
        switch (builtin.os.tag) {
            .windows => return try getLocalIpWindows(self.io, self.client_socket.address.getPort()),
            else => return @splat(0),
        }
    }
    fn getLocalIpWindows(io: Io, port: u16) ![6]u8 {
        var result: [6]u8 = undefined;
        std.mem.writeInt(u16, result[4..6], port, .little);
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
        if (Local_Testing) return try std.Io.net.IpAddress.parse("172.28.41.169", 5252);
        return try std.Io.net.IpAddress.parse("24.243.26.72", 5252);
    }
};
fn cin(io: Io, buffer: []u8) []u8 {
    var rbuffer: [256]u8 = undefined;
    var stdin = Io.File.stdin().reader(io, &rbuffer);
    var input = &stdin.interface;

    var writer = std.Io.Writer.fixed(buffer);

    const len = input.streamDelimiter(&writer, '\n') catch 1;

    if (builtin.os.tag == .windows) {
        return buffer[0 .. len - 1];
    } else return buffer[0..len];
}