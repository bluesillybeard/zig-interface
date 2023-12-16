const testing = @import("std").testing;

test "interface" {
    testing.refAllDecls(@import("tests/basic.zig"));
    testing.refAllDecls(@import("tests/circular_reference.zig"));
    testing.refAllDecls(@import("tests/to_string.zig"));
    
    // Inferred error sets on interfaces break the compiler.
    // So, defined error sets are required.
    testing.refAllDecls(@import("tests/to_string_error.zig"));
}
