const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Shared = @import("shared.zig");
const Code = Shared.Code;
const Local_Testing = @import("csimple.zig").Local_Testing;

pub fn main(init: std.process.Init) !void {
    try Server.listen(init.io);
}
const Server = struct {
    const Clients = struct {
        gpa: std.heap.ArenaAllocator,
        list: std.ArrayList(?Client),
        amount: usize,
        const Client = struct {
            key: [8]u8,
            from: net.IpAddress,
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
        fn init() @This() {
            return .{
                .gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .list = .empty,
                .amount = 0,
            };
        }
        fn deinit(self: *@This()) void {
            self.gpa.deinit();
        }
        fn add(self: *@This(), ip: net.IpAddress, local: []u8, key: []u8) !void {
            for (self.list.items) |x| {
                if (x.?.from.eql(&ip)) {
                    return;
                }
            }
            const client: Client = .{ .from = ip, .local = local[0..6].*, .key = key[0..8].* };
            for (self.list.items) |*x| {
                if (x.* == null) {
                    x.* = client;
                    self.amount += 1;
                    return;
                }
            }

            try self.list.append(self.gpa.allocator(), client);
            self.amount += 1;
        }
        fn pair(self: *@This(), io: Io, socket: net.Socket) !void {
            if (self.amount < 1) return;
            for (self.list.items, 1..) |*x, i| {
                for (self.list.items[i..]) |*y| {
                    if (x.* == null or y.* == null) continue;
                    if (!std.mem.eql(u8, &x.*.?.key, &y.*.?.key)) continue;

                    try socket.send(io, &x.*.?.from, &y.*.?.initFormat());
                    try socket.send(io, &y.*.?.from, &x.*.?.initFormat());

                    x.* = null;
                    y.* = null;
                    self.amount -= 2;
                    return;
                }
            }
        }
    };
    fn listen(io: Io) !void {
        var buf: [Shared.MTU_SIZE]u8 = undefined;
        var socket = try bindSocket(io);
        defer socket.close(io);

        var clients = Clients.init();
        defer clients.deinit();

        while (true) {
            const message = try socket.receive(io, &buf);
            const code = Code.get(message.data[0]);
            const data = message.data[1..];

            switch (code) {
                .INITIAL => {
                    var ipBuf: [24]u8 = undefined;
                    const d = message.from.ip4.bytes;
                    const ip = try std.fmt.bufPrint(ipBuf[0..], "{d}.{d}.{d}.{d}:{d}", .{ d[0], d[1], d[2], d[3], message.from.getPort() });
                    std.debug.print("Initial message from {s}\nWith local ip: {x}\nAnd key: {a}\n", .{ ip, data[0..6], data[6..14] });
                    try clients.add(message.from, data[0..6], data[6..14]);
                    try clients.pair(io, socket);
                    std.debug.print("Clients size: {d}\n", .{clients.amount});
                },
                //TEST -------------------------
                // make this better
                .RELAY => {},
                else => std.debug.print("Code not handled: {any}\n", .{code}),
            }
        }
    }
    fn bindSocket(io: Io) !std.Io.net.Socket {
        const ip = if (Local_Testing) try std.Io.net.IpAddress.parse("172.28.41.169", 5252) else
        try std.Io.net.IpAddress.parse("192.168.0.62", 5252);
        std.debug.print("Server Opened...\n", .{});
        return try ip.bind(io, .{ .mode = .dgram });
    }
};
