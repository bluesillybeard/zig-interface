# zig-interface - an extremely simple and easy to use interface library for Zig.


## How does one make an automatic interface in Zig?

Making an interface in regular Zig is fairly simple.

There are a number of ways to do it, but here is one way that works similarly to Rust's wide pointers

You need a vtable
```Zig
pub const Vtable = struct {
    dynamicFunction: *const fn(self: *Base argument: i32) void,
}
```

And the base type
```Zig
pub const Base = struct {
    vtable: *Vtable,
    // This is cast to the actual implemented later
    object: *anyopaque,

    pub fn dynamicFunction(self: Base, argument: i32) void {
        self.vtable.dynamicFunction(self, argument);
    }
}
```

And implementer(s)
```Zig
pub const Sub = struct {
    value: i32,

    pub fn dynamicFunction(self_uncast: Base, argument: i32) void {
        // In a real implementation, it would make sense to make this line an inline function to make it easier to write
        var self: *Sub = @alignCast(@ptrCast(self_uncast.object));
        self.value += argument;
        std.debug.print("The dynamic function was called with argument {}, value is now {}", .{argument, self.value});
    }
}
```

## The problem with this approach

This works, but it's a bit tedious. You can already probably see why, but here is all that code again with the issue clearly marked:

```Zig
// boilerplate
pub const Vtable = struct {
    dynamicFunction: *const fn(self: *Base argument: i32) void,
}

pub const Base = struct {
    vtable: *Vtable,
    object: *anyopaque,

    pub fn dynamicFunction(self: Base, argument: i32) void {
        // more boilerplate
        self.vtable.dynamicFunction(self, argument);
    }
}

pub const Sub = struct {
    value: i32,

    pub fn dynamicFunction(self_uncast: Base, argument: i32) void {
        // even more boilerplate
        var self: *Sub = @alignCast(@ptrCast(self_uncast.object));
        self.value += argument;
        std.debug.print("The dynamic function was called with argument {}, value is now {}", .{argument, self.value});
    }
}
```

In an ideal world, only this much would be actually needed (obviously this code will not work, it is for demonstration)

```Zig
pub const Base = struct {
    pub fn dynamicFunction(self: Base, argument: i32) void {};
}

pub const Sub = struct {
    value: i32,

    pub fn dynamicFunction(self: *Sub, argument: i32) void {
        self.value += argument;
        std.debug.print("The dynamic function was called with argument {}, value is now {}", .{argument, self.value});
    }
}
```

## Ok so, how can we get closer to that?

On potential way would be to generate the vtable in comptime, however due to the circular dependency between the vtable and the interface, the compiler will make that very dificult without heavy use of anyopaque and casting.

https://github.com/alexnask/interface.zig presents an option, however it tries to do a lot with a single API, which is not ideal. It also hasn't been updated in quite a while, which leaves me to think it was abandoned. It also still has some boilerplate.

So, now I throw my hat into the ring.

## How to use it

```Zig

const std = @import("std");
const interface = @import("interface.zig");

// First, you need a function that returns a type
// VtableType is simply to give more useful info - it will rarely be needed
fn makeBase(comptime BaseType: type, comptime VtableType: type) type {
    // Note that this function is actually called twice.
    // Once with (void, void) to be able to get the declarations, and again with the real types.
    // So, if you are doing any complex logic with BaseType, keep that in mind,
    _ = VtableType;
    // If the first argument is a BaseType, then it is an instance function and a vtable entry will be generated
    // Note: It might be worth inlining this function, inline is not required because there are good reasons not to do it.
    pub fn dynamicFunction(self: BaseType, argument: i32) void {
        // This is required because zig cannot create functions at compile time.
        // If it was possible, this boilerplate would be generated as well.
        self.vtable.dynamicFunction(self.object);
    }
    // If the first argument is not BaseType, then it will still be forwarded, but a vtable entry will not be generated
    pub fn staticFunction(argument: i32) i32 {
        return argument+1;
    }
    // If you want an instance function that isn't dynamically dispatched,
    // the only way I could think to do that is by adding a prefix to the function name.
    // However, in future versions of Zig a better solution may exist
    // (Here is one such idea: https://github.com/ziglang/zig/issues/5132)
    pub fn static_instanceFunction(self: SubType, argument: i32) void {
        // You can then call a dynamic function
        self.dynamicFunction(argument * argument);
    }
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
        std.debug.print("The dynamic function was called with argument {}, value is now {}", .{argument, self.value});
    }
};

test "basic interface" {
    // create an instace of the implementer
    var object = Sub{
        .value = 0,
    };
    
    // call the function directly - does not go through any indirection (for calling the function itself)
    object.dynamicFunction(100);

    // initFromImplementer will create the implementation given an object that is an implementer,
    // generating its vtable and stuff at compile time.
    // Note that if object's lifetime ends before the baseObject, then very bad things are likely to happen.
    var baseObject = Base.initFromImplementer(&object);
    
    // This goes through two layers of indirection - object.vtable -> function -> (call the function)
    baseObject.dynamicFunction(50);
    
    // You can also (if you're insane):
    baseObject.vtable.dynamicFunction(&baseObject.object, 20);
    
    // Don't forget the static functions!
    baseObject.static_instanceFunction(Base.staticFunction(20));

    // You can also cast it back to the sub type - but beware: no type checking is done,
    // so if you cast it to the wrong type there is no way to know until memory corruption or a segmentation fault occurs.
    var subFromBase: *Sub = @alignCast(@ptrCast(baseObject.object));
    subFrombase.value = 0;
}
```
