const std = @import("std");
const net = std.Io.net;
pub const MTU_SIZE = 1200;
pub const Code = enum(u8) {
    INITIAL,
    RELAY,
    _,
    
    pub fn get(byte: u8) Code {
        return @fromBackingInt(byte);
    }
    pub fn getByte(code: Code) [1]u8 {
        return @splat(@backingInt(code));
    }
};
pub const NetworkBuffer = struct {
    from: net.Ip4Address,
    alloc: std.heap.ArenaAllocator,

    pub fn init(from: net.IpAddress) @This() {
        return .{
            .from = from,
            .alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };
    }
    pub fn deinit(self: *@This()) void {
        self.alloc.deinit();
    }
};
test "shared" {
    std.debug.print("{any}\n", .{Code.get(4)});
    switch (Code.get(4)) {
        .INITIAL => std.debug.print("Initial\n", .{}),
        else => std.debug.print("idk\n", .{}),
    }
}