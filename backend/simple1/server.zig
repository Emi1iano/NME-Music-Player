const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Server = struct {
    io: Io,
    alloc: std.mem.Allocator,
    clients: std.StringHashMap(*Pair),
    group: Io.Group = .init,

    const Pair = struct {
        streams: [2]net.Stream = undefined,
        ready0: Io.Event = .unset, // client 1 finished init
        paired: Io.Event = .unset, // client 2 finished init and is attached
        finished: std.atomic.Value(u8) = .init(0),

        fn run(self: *Pair, io: Io, me: u1) void {
            self.runInner(io, me) catch |err| {
                std.debug.print("client {d} ended: {any}\n", .{ me, err });
            };
            self.streams[1 - me].shutdown(io, .send) catch {};
            if (self.finished.fetchAdd(1, .acq_rel) == 1) {
                self.streams[0].close(io);
                self.streams[1].close(io);
            }
        }

        fn runInner(self: *Pair, io: Io, me: u1) !void {
            const other = 1 - me;
            var rBuf: [64 * 1024]u8 = undefined;
            var wBuf: [64 * 1024]u8 = undefined;

            var reader = self.streams[me].reader(io, &rBuf);
            const r = &reader.interface;

            { // INIT CLIENT ID
                var writer = self.streams[me].writer(io, &wBuf);
                const w = &writer.interface;
                const id = try r.takeInt(u32, .little);
                if (id == 0) {
                    var buf: [4]u8 = undefined;
                    io.random(&buf);
                    try w.writeInt(u32, @bitCast(buf), .little);
                    std.debug.print("Client {d} got new key {d}\n", .{me+1, @as(u32, @bitCast(buf))});
                } else {
                    try w.writeInt(u32, 0, .little);
                    std.debug.print("Client with id {d} added\n", .{id});
                }
                try w.flush();
            }

            if (me == 0) {
                self.ready0.set(io);
                _ = r.peekByte() catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => return err,
                };
                try self.paired.wait(io);
            } else {
                try self.ready0.wait(io);
                var a = self.streams[0].writer(io, &.{});
                try a.interface.writeByte(' ');
                var b = self.streams[1].writer(io, &.{});
                try b.interface.writeByte(' ');
                self.paired.set(io);
            }

            var ow = self.streams[other].writer(io, &wBuf);
            const w = &ow.interface;
            while (true) {
                _ = r.stream(w, .unlimited) catch break;
                try w.flush();
            }
        }
    };
    fn init(io: Io, alloc: std.mem.Allocator) @This() {
        return .{
            .io = io,
            .alloc = alloc,
            .clients = .init(alloc),
        };
    }
    fn deinit(self: *@This()) void {
        self.clients.deinit();
    }
    fn listen(self: *@This(), listener: *net.Server) void {
        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const stream = listener.accept(self.io) catch |err| switch (err) {
                else => {
                    std.debug.print("Error accepting client {any}\n", .{err});
                    continue;
                },
            };
            var reader = stream.reader(self.io, &buf);
            var r = &reader.interface;
            const key_len = r.takeByte() catch |err| {
                std.debug.print("Error reading key length byte: {any}\n", .{err});
                continue;
            };
            const key = r.readAllocAll(self.alloc, key_len) catch |err| {
                std.debug.print("Error reading key: {any}\n", .{err});
                continue;
            };

            const c = self.clients.getOrPut(key) catch |err| {
                std.debug.print("Error using hash in server {any}\n", .{err});
                continue;
            };
            if (c.found_existing) {
                const pair = c.value_ptr.*;
                pair.streams[1] = stream;
                self.group.concurrent(self.io, Pair.run, .{ pair, self.io, @as(u1, 1) }) catch |err| {
                    std.debug.print("Failed to pair Client 1 with Client 2 {any}\n", .{err});
                    continue;
                };
                _ = self.clients.remove(key);
            } else {
                const pair = self.alloc.create(Pair) catch {
                    std.debug.print("Failed to create Client 1\n", .{});
                    continue;
                };
                pair.* = .{};
                pair.streams[0] = stream;
                c.value_ptr.* = pair;
                self.group.concurrent(self.io, Pair.run, .{ pair, self.io, @as(u1, 0) }) catch |err| {
                    std.debug.print("Failed to add Client 1 {any}\n", .{err});
                    _ = self.clients.remove(key);
                    continue;
                };
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const ip = try std.Io.net.IpAddress.parse("192.168.0.62", 5252);

    var server = try ip.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    //TODO change allocator to different one
    var s = Server.init(init.io, init.gpa);
    defer s.deinit();
    s.listen(&server);
}
