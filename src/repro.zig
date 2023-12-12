const std = @import("std");
const testing = std.testing;


const Z = struct {
    int: i32,
};

fn function1(z: *Z, i: i32) void {
    z.int += i;
}

fn function2(z: *anyopaque, i:i32) void {
    _ = i;
    std.io.getStdOut().writer().print("{*}", .{z}) catch @panic("wot");
}

test "functionPointerMadness" {
    var z = Z{
        .int = 0,
    };
    function1(&z, 3);
    function2(&z, 4);

    const fp1 = &function1;
    const fp2 = &function2;

    fp1(&z, 1);

    fp2(&z, 2);
}