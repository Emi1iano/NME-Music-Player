const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const ip = try std.Io.net.IpAddress.parse("192.168.0.62", 5252);
    const client = try ip.connect(init.io, .{ .mode = .stream });
    defer client.close(init.io);
}