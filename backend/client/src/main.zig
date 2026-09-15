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
    var message = try client_socket.receive(init.io, &buffer);

    if (message.data.len != 6) return error.ErrorGettingOtherClientIp;

    var bytes: [4]u8 = undefined;
    @memcpy(&bytes, message.data[0..4]);
    const port = getPortFromServer(message.data[4..6]);
    const other_client: std.Io.net.IpAddress = .{ .ip4 = .{ .bytes = bytes, .port = port } };
    for (0..20) |_| {
        try client_socket.send(init.io, &other_client, "PUNCH");
        try init.io.sleep(.fromMilliseconds(200), .awake);
    }
    //std.debug.print("{b:0>16}\n{b:0>8}{b:0>8}\n", .{other_client.ip4.port, message.data[4], message.data[5]});
    std.debug.print("{any}", .{other_client});
    
    const thread = try std.Thread.spawn(.{}, workerThread, .{init.io, client_socket});
    while (true) {
        _ = cin(init.io, &buffer);
        try client_socket.send(init.io, &other_client, "Hello");
    }
    thread.join();
}
fn workerThread(io: std.Io, socket: std.Io.net.Socket) !void {
    var buffer: [1024]u8 = undefined;
    while (true) {
        const message = try socket.receive(io, &buffer);
        std.debug.print("{s}\n", .{message.data});
    }
}
fn cin(io: std.Io, buffer: []u8) []u8 {
    var rBuffer: [256]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &rBuffer);
    var input = &stdin.interface;

    var writer = std.Io.Writer.fixed(buffer);

    const len = input.streamDelimiter(&writer, '\n') catch 1;

    return buffer[0 .. len - 1];
}
fn getPortFromArg(buffer: [:0]const u8) u16 {
    var result: u16 = 0;
    for (buffer) |c| switch (c) {
        '0'...'9' => result = result * 10 + c - '0',
        else => {},
    } else return result;
}
fn getPortFromServer(buffer: []u8) u16 {
    var result: u16 = 0;
    for (0..buffer.len) |i| {
        result <<= 8;
        result |= buffer[i];
    }
    return result;
}