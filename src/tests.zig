
const std = @import("std");
const interface = @import("interface.zig");

// First, you need a function that returns a type
// VtableType is simply to give more useful info - it will rarely be needed
fn makeBase(comptime BaseType: type) type {
    // Note that this function is actually called twice.
    // Once with a dummy type to be able to get the declarations, and again with the real thing.
    return struct{
    
    // If the first argument is a BaseType, then it is an instance function and a vtable entry will be generated
    // Note: It might be worth inlining this function, inline is not required because there are good reasons not to do it.
    pub fn dynamicFunction(self: BaseType, argument: i32) void {
        // This is required because zig cannot create functions at compile time.
        // If it was possible, this boilerplate would be generated as well.
        std.debug.print("{*}, {*}\n", .{&Sub.dynamicFunction, self.vtable.dynamicFunction});
        self.vtable.dynamicFunction(self.object, argument);
        std.debug.print("{*}, {*}\n", .{&Sub.dynamicFunction, self.vtable.dynamicFunction});
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
};

test "basic interface" {
    test1();
}

fn test1() void {
    // create an instace of the implementer
    var object = Sub{
        .value = 0,
    };
    
    // call the function directly - does not go through any indirection (for calling the function itself)
    object.dynamicFunction(100);

    // initFromImplementer will create the implementation given an object that is an implementer,
    // generating its vtable and stuff at compile time.
    // Note that if object's lifetime ends before the baseObject, then very bad things are likely to happen.
    var baseObject = Base.initFromImplementer(Sub, &object);

    // This goes through two layers of indirection - object.vtable -> function -> (call the function)
    baseObject.dynamicFunction(50);

    
    // You can also (if you're an insane masochist):
    baseObject.vtable.dynamicFunction(baseObject.object, 20);
    
    // Don't forget the static functions!
    // baseObject.static_instanceFunction(Base.staticFunction(20));

    // You can also cast it back to the sub type - but beware: no type checking is done,
    // so if you cast it to the wrong type there is no way to know until memory corruption or a segmentation fault occurs.
    var subFromBase: *Sub = @alignCast(@ptrCast(baseObject.object));
    subFromBase.dynamicFunction(29);
    (&object.value).* = 0;
}