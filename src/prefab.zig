const AnyPrefab = @This();

ptr: *const anyopaque,
impl: *const Interface,

pub const Interface = struct {
    init: *const fn (ctx: *const anyopaque) *anyopaque,
};

pub fn init(self: *const AnyPrefab) *anyopaque {
    return self.impl.init(self.ptr);
}
