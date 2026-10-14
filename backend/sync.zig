//! Library sync protocol, shared by the client and its tests.
//!
//! After two clients are connected (P2P or relayed), each one:
//!   1. downloads the other's song list (blob `list_id`),
//!   2. downloads every song it doesn't have (blob = index in that list),
//!   3. sends `done`, and leaves once the other side is done too.
//!
//! Every message is the payload of a DATA packet, so it works the same over
//! P2P and through the relay server. Downloads are pull-based: the receiver
//! asks for chunk numbers and asks again for any that get lost.
//!
//!   request: [0x01] id:u32 count:u16 count x idx:u32
//!   data:    [0x02] id:u32 idx:u32 total:u32 bytes (<= chunk_size)
//!   done:    [0x03]
//! Integers are big-endian.
const std = @import("std");
const Io = std.Io;

/// Fits a relayed packet (RELAY + key + DATA + data header + chunk) in the
/// server's and client's 1024-byte receive buffers.
pub const chunk_size: u32 = 896;
pub const data_header: usize = 13;
pub const list_id: u32 = 0xFFFF_FFFF;
/// Largest song we accept (~1.8 GB) and largest song list (~14 MB).
pub const max_chunks: u32 = 1 << 21;
pub const max_list_chunks: u32 = 1 << 14;
pub const max_per_request: usize = 64;

pub const Type = enum(u8) {
    request = 0x01,
    data = 0x02,
    done = 0x03,
    _,
};

const audio_extensions = [_][]const u8{ ".mp3", ".flac", ".wav", ".m4a", ".aac", ".ogg", ".opus", ".wma" };

pub fn isAudio(path: []const u8) bool {
    const ext = std.fs.path.extension(path);
    for (audio_extensions) |e| {
        if (std.ascii.eqlIgnoreCase(ext, e)) return true;
    }
    return false;
}

/// True for a relative path with '/' separators that stays inside the music folder.
pub fn isSafeRelPath(p: []const u8) bool {
    if (p.len == 0 or p.len > 300 or p[0] == '/') return false;
    for (p) |c| {
        if (c < 32 or c == '\\' or c == ':') return false;
    }
    var it = std.mem.splitScalar(u8, p, '/');
    while (it.next()) |seg| {
        if (seg.len == 0 or eql(seg, ".") or eql(seg, "..")) return false;
    }
    return true;
}

pub fn totalChunks(size: u64) u64 {
    return @max(1, (size + chunk_size - 1) / chunk_size);
}

/// The audio files in a music folder, as sorted '/'-separated relative paths.
pub const Library = struct {
    arena: std.heap.ArenaAllocator,
    paths: []const []const u8,
    /// `paths` joined with '\n': what the other client downloads as `list_id`.
    blob: []const u8,

    pub fn scan(io: Io, gpa: std.mem.Allocator, dir: Io.Dir) !Library {
        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const a = arena.allocator();

        var list: std.ArrayList([]const u8) = .empty;
        var walker = try dir.walk(a);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            const p = try a.dupe(u8, entry.path);
            std.mem.replaceScalar(u8, p, '\\', '/');
            if (isAudio(p) and isSafeRelPath(p)) try list.append(a, p);
        }
        std.mem.sort([]const u8, list.items, {}, lessThan);
        return .{ .arena = arena, .paths = list.items, .blob = try std.mem.join(a, "\n", list.items) };
    }

    pub fn deinit(self: *Library) void {
        self.arena.deinit();
    }

    pub fn contains(self: Library, path: []const u8) bool {
        return std.sort.binarySearch([]const u8, self.paths, path, order) != null;
    }
};

pub fn encodeRequest(buf: []u8, id: u32, idx: []const u32) []u8 {
    std.debug.assert(idx.len <= max_per_request);
    buf[0] = @intFromEnum(Type.request);
    std.mem.writeInt(u32, buf[1..5], id, .big);
    std.mem.writeInt(u16, buf[5..7], @intCast(idx.len), .big);
    for (idx, 0..) |v, i| std.mem.writeInt(u32, buf[7 + 4 * i ..][0..4], v, .big);
    return buf[0 .. 7 + 4 * idx.len];
}

pub const Request = struct {
    id: u32,
    raw: []const u8,

    /// Returns null if the packet is truncated.
    pub fn parse(p: []const u8) ?Request {
        if (p.len < 7) return null;
        const n: usize = std.mem.readInt(u16, p[5..7], .big);
        if (p.len < 7 + 4 * n) return null;
        return .{ .id = std.mem.readInt(u32, p[1..5], .big), .raw = p[7 .. 7 + 4 * n] };
    }

    pub fn count(self: Request) usize {
        return self.raw.len / 4;
    }

    pub fn index(self: Request, i: usize) u32 {
        return std.mem.readInt(u32, self.raw[4 * i ..][0..4], .big);
    }
};

/// Writes the data header into `buf`; the caller puts the bytes at `buf[data_header..]`.
pub fn encodeDataHeader(buf: []u8, id: u32, idx: u32, total: u32) void {
    buf[0] = @intFromEnum(Type.data);
    std.mem.writeInt(u32, buf[1..5], id, .big);
    std.mem.writeInt(u32, buf[5..9], idx, .big);
    std.mem.writeInt(u32, buf[9..13], total, .big);
}

pub const Data = struct {
    id: u32,
    idx: u32,
    total: u32,
    bytes: []const u8,

    /// Returns null if the packet is truncated or inconsistent.
    pub fn parse(p: []const u8) ?Data {
        if (p.len < data_header or p.len - data_header > chunk_size) return null;
        const d: Data = .{
            .id = std.mem.readInt(u32, p[1..5], .big),
            .idx = std.mem.readInt(u32, p[5..9], .big),
            .total = std.mem.readInt(u32, p[9..13], .big),
            .bytes = p[data_header..],
        };
        if (d.total == 0 or d.total > max_chunks or d.idx >= d.total) return null;
        // Every chunk but the last is full-size.
        if (d.idx + 1 < d.total and d.bytes.len != chunk_size) return null;
        return d;
    }
};

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn order(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "isSafeRelPath" {
    for ([_][]const u8{ "../x.mp3", "/x.mp3", "C:/x.mp3", "a\\x.mp3", "a//x.mp3", "a/./x.mp3", "a/../x.mp3", "" }) |p| {
        try std.testing.expect(!isSafeRelPath(p));
    }
    try std.testing.expect(isSafeRelPath("rock/Ember Light.mp3"));
}

test "isAudio" {
    try std.testing.expect(isAudio("a/b.MP3"));
    try std.testing.expect(isAudio("x.opus"));
    try std.testing.expect(!isAudio("notes.txt"));
    try std.testing.expect(!isAudio("mp3"));
}

test "request round trip" {
    var buf: [1024]u8 = undefined;
    const p = encodeRequest(&buf, 7, &.{ 0, 5, 1 << 20 });
    const r = Request.parse(p).?;
    try std.testing.expectEqual(7, r.id);
    try std.testing.expectEqual(3, r.count());
    try std.testing.expectEqual(1 << 20, r.index(2));
    try std.testing.expect(Request.parse(p[0 .. p.len - 1]) == null);
}

test "data parse rejects bad packets" {
    var buf: [1024]u8 = undefined;
    encodeDataHeader(&buf, list_id, 1, 2);
    try std.testing.expect(Data.parse(buf[0 .. data_header + 10]) != null); // short last chunk is fine
    encodeDataHeader(&buf, list_id, 0, 2);
    try std.testing.expect(Data.parse(buf[0 .. data_header + 10]) == null); // short middle chunk
    encodeDataHeader(&buf, list_id, 2, 2);
    try std.testing.expect(Data.parse(buf[0 .. data_header + 10]) == null); // idx >= total
    try std.testing.expect(Data.parse(buf[0..5]) == null);
}

test "scan finds audio files recursively" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "rock");
    for ([_][]const u8{ "b.mp3", "rock/a.flac", "notes.txt" }) |p| {
        const f = try tmp.dir.createFile(io, p, .{});
        f.close(io);
    }
    var lib = try Library.scan(io, std.testing.allocator, tmp.dir);
    defer lib.deinit();
    try std.testing.expectEqual(2, lib.paths.len);
    try std.testing.expectEqualStrings("b.mp3\nrock/a.flac", lib.blob);
    try std.testing.expect(lib.contains("rock/a.flac"));
    try std.testing.expect(!lib.contains("notes.txt"));
}
