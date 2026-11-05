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
    start_sending: std.Io.Mutex = .init,
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
                    if (self.o_localIp != null) std.debug.print("Other Client local ip: {any}\n", .{self.o_localIp.?});
                    self.got_info.store(true, .release);
                },
                .P2P => {
                    if (!self.fromPeer(message.from)) blk: {
                        if (d.len < 9) continue;
                        if (std.mem.eql(u8, &self.key, d[0..8])) {
                            if (std.mem.eql(u8, "Local", d[8..])) {
                                self.o_localIp = message.from;
                                break :blk;
                            }
                        }
                        continue;
                    }
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
                self.sendTo(ip, Code.getByte(.P2P) ++ self.key ++ "Local");
            }
            self.sendTo(self.o_publicIp, Code.getByte(.P2P) ++ self.key ++ "Public");
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
        var result: [6]u8 = undefined;
        @memcpy(result[0..4], &(try LocalIp.getLocalIp4()));
        std.mem.writeInt(u16, result[4..6], self.client_socket.address.getPort(), .little);
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
    const LocalIp = struct {
        //! Find this machine's local IPv4 address with no per-OS output parsing.
        //!
        //! Trick: connect() a UDP socket to an external address (nothing is sent),
        //! then getsockname() tells you which local address the OS routing table
        //! picked for that destination.
        //!
        //! Backends:
        //!   - Linux / Android: raw kernel syscalls via std.os.linux. No libc needed,
        //!     so `zig build -Dtarget=aarch64-linux-android` works without the NDK.
        //!   - Windows: ws2_32 (Winsock), declared directly.
        //!   - macOS / BSD: libc, declared directly (link libc for these targets).
        const is_bsd = switch (builtin.os.tag) {
            .macos, .freebsd, .netbsd, .openbsd, .dragonfly => true,
            else => false,
        };
    
        const AF_INET = 2; // same value on every OS we support
        const SOCK_DGRAM_GENERIC = 2; // Windows / macOS / BSD (Linux uses std constants)
    
        // BSD/macOS sockaddr_in starts with a length byte and a u8 family.
        const SockAddrIn = if (is_bsd)
            extern struct { len: u8, family: u8, port: u16, addr: [4]u8, zero: [8]u8 }
        else
            extern struct { family: u16, port: u16, addr: [4]u8, zero: [8]u8 };
    
        fn makeAddr(ip: [4]u8, port: u16) SockAddrIn {
            var a = std.mem.zeroes(SockAddrIn);
            if (is_bsd) {
                a.len = @sizeOf(SockAddrIn);
                a.family = AF_INET;
            } else {
                a.family = AF_INET;
            }
            a.port = std.mem.nativeToBig(u16, port);
            a.addr = ip;
            return a;
        }
    
        const linux_impl = struct {
            fn localIp4(target: [4]u8) ![4]u8 {
                const linux = std.os.linux;
    
                const rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM | linux.SOCK.CLOEXEC, 0);
                if (linux.errno(rc) != .SUCCESS) return error.SocketFailed;
                const fd: i32 = @intCast(rc);
                defer _ = linux.close(fd);
    
                const dest = makeAddr(target, 53);
                const crc = linux.connect(fd, @ptrCast(&dest), @sizeOf(SockAddrIn));
                if (linux.errno(crc) != .SUCCESS) return error.NoRoute;
    
                var local = std.mem.zeroes(SockAddrIn);
                var len: linux.socklen_t = @sizeOf(SockAddrIn);
                const grc = linux.getsockname(fd, @ptrCast(&local), &len);
                if (linux.errno(grc) != .SUCCESS) return error.GetSockNameFailed;
    
                return local.addr;
            }
        };
        const windows_impl = struct {
            const Socket = usize;
            const invalid_socket: Socket = std.math.maxInt(usize);
    
            extern "ws2_32" fn WSAStartup(version: u16, data: *anyopaque) callconv(.winapi) c_int;
            extern "ws2_32" fn WSACleanup() callconv(.winapi) c_int;
            extern "ws2_32" fn socket(af: c_int, ty: c_int, proto: c_int) callconv(.winapi) Socket;
            extern "ws2_32" fn connect(s: Socket, name: *const SockAddrIn, len: c_int) callconv(.winapi) c_int;
            extern "ws2_32" fn getsockname(s: Socket, name: *SockAddrIn, len: *c_int) callconv(.winapi) c_int;
            extern "ws2_32" fn closesocket(s: Socket) callconv(.winapi) c_int;
    
            fn localIp4(target: [4]u8) ![4]u8 {
                var wsa: [512]u8 align(8) = undefined; // WSADATA is < 512 bytes
                if (WSAStartup(0x0202, &wsa) != 0) return error.WinsockInit;
                defer _ = WSACleanup();
    
                const s = socket(AF_INET, SOCK_DGRAM_GENERIC, 0);
                if (s == invalid_socket) return error.SocketFailed;
                defer _ = closesocket(s);
    
                const dest = makeAddr(target, 53);
                if (connect(s, &dest, @sizeOf(SockAddrIn)) != 0) return error.NoRoute;
    
                var local = std.mem.zeroes(SockAddrIn);
                var len: c_int = @sizeOf(SockAddrIn);
                if (getsockname(s, &local, &len) != 0) return error.GetSockNameFailed;
    
                return local.addr;
            }
        };
        const libc_impl = struct {
            extern "c" fn socket(af: c_int, ty: c_int, proto: c_int) callconv(.c) c_int;
            extern "c" fn connect(s: c_int, name: *const SockAddrIn, len: u32) callconv(.c) c_int;
            extern "c" fn getsockname(s: c_int, name: *SockAddrIn, len: *u32) callconv(.c) c_int;
            extern "c" fn close(s: c_int) callconv(.c) c_int;
    
            fn localIp4(target: [4]u8) ![4]u8 {
                const s = socket(AF_INET, SOCK_DGRAM_GENERIC, 0);
                if (s < 0) return error.SocketFailed;
                defer _ = close(s);
    
                const dest = makeAddr(target, 53);
                if (connect(s, &dest, @sizeOf(SockAddrIn)) != 0) return error.NoRoute;
    
                var local = std.mem.zeroes(SockAddrIn);
                var len: u32 = @sizeOf(SockAddrIn);
                if (getsockname(s, &local, &len) != 0) return error.GetSockNameFailed;
    
                return local.addr;
            }
        };
        const impl = switch (builtin.os.tag) {
            .linux => linux_impl, // includes Android (abi = .android)
            .windows => windows_impl,
            else => libc_impl,
        };
        pub fn getLocalIp4() ![4]u8 {
            return impl.localIp4(.{ 8, 8, 8, 8 });
        }
    };

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
