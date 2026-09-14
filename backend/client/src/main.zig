const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args[0..]);


    const client = try Io.net.IpAddress.parse("0.0.0.0", getPortFromArg(args[1]));
    const server = try std.Io.net.IpAddress.parse("24.243.26.72", 5252);
    const client_socket = try client.bind(init.io, .{ .mode = .dgram });
    defer client_socket.close(init.io);

    try client_socket.send(init.io, &server, "12345678");

    var buffer: [1024]u8 = undefined;
    while (true) {
        const message = try client_socket.receive(init.io, &buffer);
        std.debug.print("{s}\n", .{message.data});
    }
}
fn getPortFromArg(buffer: [:0]const u8) u16 {
    var result: u16 = 0;
    for (buffer) |c| switch (c) {
        '0'...'9' => result = result * 10 + c - '0',
        else => {},
    } else return result;
}