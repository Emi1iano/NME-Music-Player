const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Shared = @import("shared.zig");
const Code = Shared.Code;

pub fn main(init: std.process.Init) !void {
    try Server.listen(init.io);
}
const Server = struct {
    fn listen(io: Io) !void {
        var buf: [Shared.MTU_SIZE]u8 = undefined;
        var socket = try bindSocket(io);
        defer socket.close(io);

        while (true) {
            const message = try socket.receive(io, &buf);
            const code = Code.get(message.data[0]);
            const data = message.data[1..];

            switch (code) {
                .INITIAL => {
                    var ipBuf: [24]u8 = undefined;
                    const ip = try std.fmt.bufPrint(ipBuf[0..], "{d}.{d}.{d}.{d}:{d}", const );
                    std.debug.print("Initial message from {any}\nWith local ip: {x}\nAnd key: {x}\n", .{message.from, data[0..6], data[6..14]});
                },
                else => std.debug.print("Code not handled: {any}\n", .{code}),
            }
        }
    }
    fn bindSocket(io: Io) !std.Io.net.Socket {
        const ip = try std.Io.net.IpAddress.parse("192.168.0.62", 5252);
        std.debug.print("Server Opened...\n", .{});
        return try ip.bind(io, .{ .mode = .dgram });
    }
};