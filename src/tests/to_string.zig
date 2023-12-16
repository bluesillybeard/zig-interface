const std = @import("std");
const interface = @import("interface");

//=============Code to create the interface=============
fn MakePrintable(comptime BaseType: type) type {
    return struct {
        pub inline fn to_string(self: BaseType, a: std.mem.Allocator) ?[]u8 {
            return self.vtable.to_string(self.object, a) orelse null;
        }
    };
}
// makeInterface creates an interface type that can be used to create implementations
const Printable = interface.MakeInterface(MakePrintable, .{});

//==============Code to create a type which implements the interface==========
const SubType = struct {
    foo: i32,
    bar: i32,

    pub fn to_string(self: *const @This(), a: std.mem.Allocator) ?[]u8 {
        return std.fmt.allocPrint(a, "[foo: {}, bar: {}]", .{ self.foo, self.bar }) catch return null;
    }
};

//==============Code to create a function which accepts the interface type===========
fn doSomething(a: std.mem.Allocator, printable: Printable) !void {
    const string = printable.to_string(a) orelse "";
    defer a.free(string);
    //you could then do something with the string here
}

//============Example Usage===========
test "printable interface" {
    var sub_type_value = SubType{ .foo = 123, .bar = 456 };
    _ = &sub_type_value; //this line is needed or zig will complain that the variable is never mutated

    const sub_type_interface = Printable.initFromImplementer(SubType, &sub_type_value);
    try doSomething(std.testing.allocator, sub_type_interface);
}
