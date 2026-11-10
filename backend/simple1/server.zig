const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Relay = struct {
    gpa: std.mem.Allocator,
    mutex: std.Io.Mutex = .init,
    waiting: std.StringHashMapUnmanaged(*Waiter) = .empty,
    const Waiter = struct {
        stream: net.Stream,
        reader: *std.Io.Reader,
        done: std.Io.Event = .unset,
        watcher: std.Io.Group = .init,
        gone: bool = false, // set by the watcher if the client died while waiting
    };
    fn serve(self: *Relay, io: std.Io, listener: *std.Io.net.Server) void {
        var group: std.Io.Group = .init;
        defer group.cancel(io);

        while (true) {
            const stream = listener.accept(io) catch |err| switch (err) {
                error.Canceled => return,
                else => {
                    std.debug.print("accept failed: {any}\n", .{err});
                    continue;
                },
            };
            group.concurrent(io, handle, .{ self, io, stream }) catch stream.close(io);
        }
    }
    fn handle(self: *Relay, io: std.Io, stream: net.Stream) void {
        defer stream.close(io);

        var rbuf: [4096]u8 = undefined;
        var reader = stream.reader(io, &rbuf);
        const r = &reader.interface;

        var key_buf: [255]u8 = undefined;
        const klen = r.takeByte() catch return;
        if (klen == 0) return;
        const key = key_buf[0..klen];
        r.readSliceAll(key) catch return;

        self.mutex.lockUncancelable(io);
        if (self.waiting.fetchRemove(key)) |kv| {
            self.mutex.unlock(io);
            const peer = kv.value;

            // stop the peer's watcher before we touch its reader
            peer.watcher.cancel(io);

            // tell both sides they're paired; if the peer died in the gap, bail out
            sendAck(io, peer.stream) catch {
                peer.done.set(io);
                return;
            };
            sendAck(io, stream) catch {
                peer.done.set(io);
                return;
            };

            var g: std.Io.Group = .init;
            g.concurrent(io, pump, .{ io, peer.reader, stream }) catch {};
            pump(io, r, peer.stream);
            g.await(io) catch {};
            peer.done.set(io);
            return;
        }

        // nobody waiting: register ourselves and start watching our socket.
        // The watcher is spawned while holding the lock so it can't try to
        // unregister before we're in the map.
        var me: Waiter = .{ .stream = stream, .reader = r };
        me.watcher.concurrent(io, watch, .{ self, io, &me, key }) catch {
            self.mutex.unlock(io);
            return;
        };
        self.waiting.put(self.gpa, key, &me) catch {
            self.mutex.unlock(io);
            me.watcher.cancel(io);
            return;
        };
        self.mutex.unlock(io);

        me.done.wait(io) catch {
            // canceled (server shutting down)
            self.mutex.lockUncancelable(io);
            const mine = self.waiting.remove(key);
            self.mutex.unlock(io);
            if (mine) {
                me.watcher.cancel(io);
            } else {
                me.done.waitUncancelable(io); // a peer or the watcher already took us
                if (me.gone) me.watcher.await(io) catch {};
            }
            return;
        };

        // woken by the peer (which already stopped the watcher) or by the watcher
        if (me.gone) me.watcher.await(io) catch {};
    }

    fn watch(self: *Relay, io: std.Io, me: *Waiter, key: []const u8) void {
        // Blocks until the client closes, resets, sends early data, or a peer cancels us.
        _ = me.reader.peekByte() catch {};

        // Whatever the reason, try to unregister. If a peer already claimed us,
        // remove() fails and we leave quietly. If it succeeds, nobody claimed us,
        // so the client is dead (or misbehaving): release the handler.
        self.mutex.lockUncancelable(io);
        const removed = self.waiting.remove(key);
        self.mutex.unlock(io);
        if (removed) {
            me.gone = true;
            me.done.set(io);
        }
    }

    fn sendAck(io: std.Io, stream: net.Stream) !void {
        var buf: [1]u8 = undefined;
        var writer = stream.writer(io, &buf);
        try writer.interface.writeByte(1);
        try writer.interface.flush();
    }
    fn pump(io: std.Io, from: *std.Io.Reader, to: net.Stream) void {
        var wbuf: [4096]u8 = undefined;
        var writer = to.writer(io, &wbuf);
        const w = &writer.interface;

        _ = w.write("STARTSENDING") catch return;
        w.flush() catch return;
        while (true) {
            _ = from.stream(w, .unlimited) catch break; // EndOfStream / Canceled / error
            w.flush() catch break;
        }
        to.shutdown(io, .send) catch {}; // propagate EOF to the other side
    }
};
const Server = struct {
    const ServerState = struct {
        gpa: std.mem.Allocator,
        mutex: std.Io.Mutex = .init,
        waiting: std.StringHashMapUnmanaged(*Waiter) = .empty,

        const Waiter = struct {
            stream: net.Stream,
            reader: *std.Io.Reader, // reuse it: it may already hold bytes read past the handshake
            done: std.Io.Event = .unset,
            paired: std.Io.Event = .unset,
        };
    };
    fn start(io: Io, gpa: std.mem.Allocator, server: *net.Server) !void {
        var server_state: ServerState = .{ .gpa = gpa };
        defer server_state.waiting.deinit(gpa);

        var group: std.Io.Group = .init;
        defer group.cancel(io);

        while (true) {
            const stream = server.accept(io) catch |err| switch (err) {
                error.Canceled => return,
                else => {
                    std.debug.print("accept failed: {any}\n", .{err});
                    continue;
                },
            };
            group.concurrent(io, handle, .{ &server_state, io, stream }) catch stream.close(io);
        }
    }
    fn handle(self: *ServerState, io: Io, stream: net.Stream) void {
        defer stream.close(io);

        var rbuf: [4096]u8 = undefined;
        var reader = stream.reader(io, &rbuf);
        const r = &reader.interface;

        // handshake: [len][key]
        var key_buf: [255]u8 = undefined;
        const klen = r.takeByte() catch return;
        if (klen == 0) return;
        const key = key_buf[0..klen];
        r.readSliceAll(key) catch return;

        self.mutex.lockUncancelable(io);
        if (self.waiting.fetchRemove(key)) |entry| {
            self.mutex.unlock(io);
            const peer = entry.value;

            peer.paired.set(io);
        } else {
            std.debug.print("HERE\n", .{});
            var me: ServerState.Waiter = .{ .stream = stream, .reader = r };
            self.waiting.put(self.gpa, key, &me) catch {
                self.mutex.unlock(io);
                return;
            };
            self.mutex.unlock(io);

            _ = r.takeByte() catch {
                self.mutex.lockUncancelable(io);
                _ = self.waiting.remove(key);
                self.mutex.unlock(io);
                std.debug.print("Client with key {s} disconnected\n", .{key});
                return;
            };
            me.paired.wait(io) catch return;
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // const ip = try std.Io.net.IpAddress.parse("127.0.0.1", 4003);
    const ip = try std.Io.net.IpAddress.parse("192.168.0.62", 5252);

    var server = try ip.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    // try Server.start(init.io, init.gpa, &server);
    var relay: Relay = .{ .gpa = init.gpa };
    defer relay.waiting.deinit(init.gpa);

    var server_s = try std.Io.concurrent(io, Relay.serve, .{ &relay, io, &server });

    server_s.await(io);
}
