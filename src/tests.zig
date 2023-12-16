const testing = @import("std").testing;

test "interface" {
    testing.refAllDecls(@import("tests/basic.zig"));
    testing.refAllDecls(@import("tests/circular_reference.zig"));
    testing.refAllDecls(@import("tests/to_string.zig"));

    //This test below should fail to compile because it has a function with an inferred error set
    //testing.refAllDecls(@import("tests/to_string_error.zig"));
}
