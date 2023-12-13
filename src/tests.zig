const std = @import("std");
const testing = std.testing;
const interface = @import("interface.zig");

// First, you need a function that returns a type
// VtableType is simply to give more useful info - it will rarely be needed
fn makeBase(comptime BaseType: type) type {
    // Note that this function is actually called twice.
    // Once with a dummy type to be able to get the declarations, and again with the real thing.
    return struct{
    
    // If the first argument is a BaseType, then it is an instance function and a vtable entry will be generated
    // The function is inline because that reduces calling overhead.
    pub inline fn dynamicFunction(self: BaseType, argument: i32) void {
        // This is required because zig cannot create functions at compile time.
        // If it was possible, this boilerplate would be generated as well.
        self.vtable.dynamicFunction(self.object, argument);
    }
    // If the first argument is not BaseType, then it will still be forwarded, but a vtable entry will not be generated
    pub fn staticFunction(argument: i32) i32 {
        return argument+1;
    }
    // If you want an instance function that isn't dynamically dispatched,
    // the only way I could think to do that is by adding a prefix to the function name.
    // However, in future versions of Zig a better solution may exist
    // (Here is one such idea: https://github.com/ziglang/zig/issues/5132)
    pub fn static_instanceFunction(self: BaseType, argument: i32) void {
        // You can then call a dynamic function
        self.dynamicFunction(argument * argument);
    }

    pub inline fn otherDynamicFunction(self: BaseType) void {
        self.dynamicFunction(10);
        self.vtable.otherDynamicFunction(self.object);
    }
};
}
// makeInterface creates an interface type that can be used to create implementations
pub const Base = interface.makeInterface(makeBase);

// You don't actually need to do anything with the sub type - as long as it has all the required functions.
pub const Sub = struct {
    value: i32,

    // The call convention of this function must match that of the base one, 
    // With the exception of when the base function is inline; in that case the call convention must be default,
    // since getting the pointer of an inline function is not allowed.
    pub fn dynamicFunction(self: *Sub, argument: i32) void {
        self.value += argument;
    }

    pub fn otherDynamicFunction(self: *Sub) void {
        _ = self;
    }
};

test "basic interface" {
    // create an instace of the implementer
    var object = Sub{
        .value = 0,
    };
    
    // call the function directly - does not go through any indirection (for calling the function itself)
    object.dynamicFunction(100);

    try testing.expectEqual(@as(i32, 100), object.value);

    // initFromImplementer will create the implementation given an object that is an implementer,
    // generating its vtable and stuff at compile time.
    // Note that if object's lifetime ends before the baseObject, then very bad things are likely to happen.
    var baseObject = Base.initFromImplementer(Sub, &object);

    // This goes through two layers of indirection - object.vtable -> function -> (call the function)
    baseObject.dynamicFunction(50);
    // because baseObject holds a reference to Object, it changes the original's value
    try testing.expectEqual(@as(i32, 150), object.value);

    // If you're feeling naughty, you can also do this:
    baseObject.vtable.dynamicFunction(baseObject.object, 20);
    try testing.expectEqual(@as(i32, 170), object.value);
    
    // Don't forget the static functions!
    const int = Base.staticFunction(20);
    baseObject.static_instanceFunction(int);
    try testing.expectEqual(@as(i32, 611), object.value);

    // You can also cast it back to the sub type - but beware: no type checking is done,
    // so if you cast it to the wrong type there is no way to know until memory corruption or a segmentation fault occurs.
    var subFromBase: *Sub = @alignCast(@ptrCast(baseObject.object));
    subFromBase.dynamicFunction(29);
    try testing.expectEqual(@as(i32, 640), object.value);
    object.value = 0;
    try testing.expectEqual(@as(i32, 0), object.value);
}
