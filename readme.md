# zig-interface - an extremely simple and easy to use interface library for Zig.


## How does one make an automatic interface in Zig?

Making an interface in regular Zig is fairly simple.

There are a number of ways to do it, but here is one way that works similarly to Rust's wide pointers

You need a vtable
```Zig
pub const Vtable = struct {
    dynamicFunction: *const fn(self: *Base, argument: i32) void,
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
    dynamicFunction: *const fn(self: *Base, argument: i32) void,
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

On potential way would be to simply generate the vtable in comptime, however due to the circular dependency between the vtable and the interface, the compiler will make that very dificult without heavy use of anyopaque and casting.

https://github.com/alexnask/interface.zig presents an option, however it tries to do a lot with a single API, which is not ideal. It also hasn't been updated in quite a while, which leaves me to think it was abandoned. It also still requires some boilerplate.

So, now I throw my hat into the ring.

## How to use it

Beware, this library has literally existed for less than a week, and is very early and buggy.

Look at [src/tests.zig](src/tests.zig) for examples of how to use it.

It is currently tested and developed with zig 0.12.0-dev.1819+5c1428ea9

## Planned features
- fields instead of just functions
- optional functions, with a default implementation that can be overriden
- static instance function (a function that is part of the vtable but does not resieve an instance of the object it was called from)
    - this may sound pointless, but one of my actual real-use-case projects would make use of this.
- More types of dynamic dispatch
    - [DONE-ish] Wide pointer / Rust style (the only option at the moment)
    - C++ style
    - struct of function pointers / C style
- integration with Zig package managers (I won't add this myself as I always use a git submodule, feel free to make a poll request.)
- proper documentation system using a github wiki
- CI/CD

## Contributing

I am a fairly busy person who values their time, so I won't develop this library much more than I need for my own projects. I will accept poll requests though, so they are very highly appreciated.

Try to keep it one bugfix / feature per PR, and if you're adding new features please save me some work and document the new functions / types.
