const std = @import("std");
const testing = std.testing;
const interface = @import("interface");

//=============Code to create the interface=============
fn MakePrintable(comptime BaseType: type) type {
    return struct {
        pub inline fn to_string(self: BaseType, a: std.mem.Allocator) ![]u8 {
            return self.vtable.to_string(self.object, a);
        }
    };
}
// makeInterface creates an interface type that can be used to create implementations
const Printable = interface.MakeInterface(MakePrintable, .{});

//==============Code to create a type which implements the interface==========
const SubType = struct {
    foo: i32,
    bar: i32,

    pub fn to_string(self: @This(), a: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(a, "[foo: {}, bar: {}]", .{ self.foo, self.bar });
    }
};

//==============Code to create a function which accepts the interface type===========
fn doSomething(a: std.mem.Allocator, printable: Printable) !void {
    const string = try printable.to_string(a);
    defer a.free(string);
    std.debug.print("{s}", .{string});
}

test "printable interface" {
    var sub_type_value = SubType{ .foo = 123, .bar = 456 };
    var sub_type_interface = Printable.initFromImplementer(SubType, &sub_type_value);

    const stringified = try sub_type_interface.to_string(std.testing.allocator);
    defer std.testing.allocator.free(stringified);

    try doSomething(std.testing.allocator, sub_type_interface);
}
