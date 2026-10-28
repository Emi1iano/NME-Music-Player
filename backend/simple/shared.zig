pub const MTU_SIZE = 1200;
pub const Code = enum(u8) {
    INITIAL,
    DUMMY,
    
    pub fn get(byte: u8) Code {
        return @fromBackingInt(byte);
    }
    pub fn getByte(code: Code) [1]u8 {
        return @splat(@backingInt(code));
    }
};