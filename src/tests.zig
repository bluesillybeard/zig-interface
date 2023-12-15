const testing = @import("std").testing;

test "interface" {
    testing.refAllDecls(@import("tests/basic.zig"));  
    testing.refAllDecls(@import("tests/circular_reference.zig"));   
}

