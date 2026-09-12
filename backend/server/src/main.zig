const std = @import("std");
const Io = std.Io;

const MAX_CONNECTIONS: usize = 16;
const CLIENTS: [MAX_CONNECTIONS]std.Io.net.Stream = undefined;

// Wait for 2 clients to connect with the same password/key
// Connect them to each other
pub fn main(init: std.process.Init) !void {
    const thread = try std.Thread.spawn(.{}, workerThread, .{init});
    try mainThread(init);
    thread.join();
}
fn mainThread(init: std.process.Init) !void {
    const ip = try std.Io.net.IpAddress.parse("192.168.0.62", 5252);
    std.debug.print("Server Opened...\n", .{});
    var server = try ip.listen(init.io, .{ .mode = .stream });
    defer server.deinit(init.io);

    while (true) {
        var client = try server.accept(init.io);
        
        std.debug.print("{any} Connected", .{client.socket.address.ip4});
        client.close(init.io);
    }
}
fn workerThread(init: std.process.Init) !void {
    _ = init;
}