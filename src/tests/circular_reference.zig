const std = @import("std");
const testing = @import("std").testing;
const interface = @import("interface");

// The way this library works has a tendency to create 'unresolvable' circular references.
// However, there is a way around it.

// This is the interface
fn mI(comptime B: type) type {
    return struct {
        // FakeZ is the same as Z, but it doesn't reference the interface
        pub fn iz(self: B, z: FakeZ) i32 {
            return self.vtable.iz(self.object, z);
        }
    };
}

// Make the interface, HOWEVER if the implementer's functions aren't equal,
// if they are instead bitwise compatible (TODO: explain rules in more detail) then it's allowed.
const I = interface.makeInterface(mI, .{.allow_bitwise_compatibility = true});

const Impl = struct {
    pub fn iz(self: *Impl, z: Z) i32 {
        _ = self;
        return z.int + 5;
    }
};

// This is 'referenced' by and references the interface.
// It is extern so that its 'fake' type is guaranteed to have the same memory layout.
const Z = extern struct {
    int: i32,
    i: *I,

    fn izo(self: *Z) i32 {
        const prev = self.int;
        // When the function is called, it is cast to the fake type.
        // When the function pointer is called, it doesn't need to know it's given the wrong type,
        // because the real and fake versions are bit-for-bit compatible.
        self.int = self.i.iz(@bitCast(self.*));
        return prev;
    }
};

// A copy of Z that doesn't reference the interface.
const FakeZ = extern struct {
    int: i32,
    i: *anyopaque,
};

test "circular reference" {
    var a = Impl{};
    var i = I.initFromImplementer(Impl, &a);
    var z = Z{.int = 5, .i = &i};
    try testing.expectEqual(@as(i32, 5), z.izo());
    try testing.expectEqual(@as(i32, 10), z.int);
}
