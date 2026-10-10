//! Semantic fixture documentation.
pub const child = @import("child.zig");
/// Direct official fixture docs.
pub const DirectType = struct {
    pub const Self = @This();
    pub fn method() void {}
};
pub const Alias = DirectType;
pub const Reexport = child.ChildType;
pub const ImportMember = @import("child.zig").ChildType;
const SomeNamespace = child;
pub const FooAlias = SomeNamespace.ChildType;
const Foo = struct {
    const Self = @This();
    pub const Parent = Self;
};
pub const FooExport = Foo;
pub fn Generic(comptime T: type) type {
    const Unused = struct {
        pub fn phantom() void {}
    };
    _ = Unused;
    return struct {
        value: T,
        pub fn member() void {}
    };
}
pub const number = 42;
pub const NumberType = u32;
pub const A = B;
pub const B = C;
pub const C = A;
pub const CycleMember = A.missing;
pub const Unknown = missing.Type;
pub const Branch = if (true) u32 else false;
pub fn ValueFunction() struct { x: u8 } {
    return .{ .x = 0 };
}
