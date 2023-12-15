## Idea of how to create functions in comptime

Previous suggestions would have the comptime code create a string. This was not accepted for hopefully clear reasons, however the ability for comptime code to create a function seems very doable considering structs can be created in comptime.

## How it would work (from a user's perspective)

This is really two features: declarations in a comptime-generated type, and generating function bodies in comptime.

First up, declarations. A struct can have a list of fields, why not a list declarations? This would simply add a way for a declaration's value and publicity to be given when creating a struct, rather than just its name.

```Zig
const s = @Type(
    std.builtin.Type{
        .Struct = .{
            // other info is hidden for reasier reading
            .declarations = &[_]std.builtin.Type.Declaration {
                .{
                    .name = "a_declaration",
                    // The exact way through which the following three fields are filled out does not matter,
                    // Only that a way for the values of declarations can be created by code like this
                    .publicity = .public,
                    .type = comptime_int,
                    .value = 7,
                },
            }
        }
    }
)
```

Next, generating functions in comptime. This is a bit more complex, but still not too bad.

To generate a function, a new builtin, `@Fn` could be added. It would work similarly to `@Type`, just instead of returning a type, it returns a function.

It takes a function's type information (`std.builtin.Type.Fn`) and the implementation of that function

```Zig
const std = @import("std");

const my_fn_type = fn(i32) void;

const my_fn_info = @typeInfo(my_fn_type).Fn;

const number = 20;
const myFn = @Fn(my_fn_info, {
    //params is a tuple with all of the parameters
    return args[0] + number;
})

test "fn" {
    std.testing.expectEqual(120, myFn(100));
}
```

In the case of this library, it could be used to create the vtable wrapper functions, similar to this:

```zig
// These would be local variables of the function that generates the wrapper functions
const fn_type = fn(Instance, i32) void;

const fn_info = @typeInfo(fn_type).Fn;

const function_name = "dynamicFunction";

const function = @Fn(function_info, {
    // Pretend tuples can be sliced like this. In the real code, one could use an inline-for loop to build the tuple
    const arguments_to_pass = args[1..];
    const vtable_entry = @field(args[0].vtable, function_name);
    @call(.auto, vtable_entry, arguments_to_pass);
});
```


These two features, when combined, would make it possible to take a list of functions and just straight up build the entire interface type in comptime
