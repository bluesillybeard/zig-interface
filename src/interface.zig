const std = @import("std");
const testing = std.testing;

pub fn makeInterface(comptime makeTypeFn: fn(type)type) type {
    // First, make a dummy type so we can get the declarations
    const DummyInterface = struct {
        vtable: *anyopaque,
        object: *anyopaque,
        // This is an unorthodox use of usingnamespace but it works
        usingnamespace makeTypeFn(@This());
    };

    const Vtable = makeVtableType(DummyInterface);

    // build the interface struct
    const Interface = struct {
        vtable: *Vtable,
        object: *anyopaque,

        usingnamespace makeTypeFn(@This());
    };

    return Interface;
}

pub fn initFromImplementer(comptime Interface: type, comptime Object: type, object: *Object) Interface{
    //verifyInterface(Interface);
    const objectTypeInfo = @typeInfo(Object);
    switch (objectTypeInfo) {
        .Struct => {        
            // build the vtable
            const dummyInterfaceInstance: Interface = undefined;
            const Vtable = @typeInfo(@TypeOf(dummyInterfaceInstance.vtable)).Pointer.child;
            const vtableInfo = @typeInfo(Vtable);
            var vtable: Vtable = undefined;
            inline for(vtableInfo.Struct.fields) |field|{
                if(!@hasDecl(Object, field.name)) @compileError("Object does not implement " ++ field.name);
                const decl = @field(Object, field.name);
                // make sure the decl is a function with the right parameters
                const declInfo = @typeInfo(@TypeOf(decl));
                switch (declInfo) {
                    .Fn => |f| {
                        const expectedFn = makeVtableFn(Interface, Object, f);
                        _ = expectedFn;
                        //if(!functionsEqual(expectedFn, f)) @compileError("TODO: put a useful error message here");
                        @field(vtable, field.name) = @ptrCast(&@field(Object, field.name));
                    },
                    else => {@compileError("Implementation of " ++ field.name ++ " Must be a function");},
                }
            }

            return .{
                .object = object,
                .vtable = &vtable,
            };

        },
        else => {@compileError("Object must be a struct");}
    }
}

fn functionsEqual(comptime a: std.builtin.Type.Fn, comptime b: std.builtin.Type.Fn) bool {
    _ = a;
    _ = b;

    // TODO
    return true;
}

/// Takes the base type and returns the vtable type
fn makeVtableType(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Struct => |dummyInfo|{
            var vtableFields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
            inline for(dummyInfo.decls) |decl| {
                const name = decl.name;
                // mildly annoys me that @field is used for both fields and declarations
                const actualDecl = @field(T, name);
                const DeclType = @TypeOf(actualDecl);
                switch (@typeInfo(DeclType)) {
                    .Fn => |f|{
                        const VtableFieldType = @Type(std.builtin.Type{
                            .Fn = makeVtableFn(T, *anyopaque, f),
                        });
                        const vtableField = std.builtin.Type.StructField{
                            .alignment = @alignOf(VtableFieldType),
                            .default_value = null,
                            .is_comptime = false,
                            .name = name,
                            .type = *VtableFieldType,
                        };
                        vtableFields = vtableFields ++ &[_]std.builtin.Type.StructField{vtableField};
                    },
                    // non-function declarations are allowed
                    else => {},
                }
            }
            return @Type(std.builtin.Type{
                .Struct = .{
                    .decls = &[_]std.builtin.Type.Declaration{},
                    .fields = vtableFields,
                    .is_tuple = false,
                    .layout = .Auto
                }
            });
        },
        else => @compileError("Expected a struct"),
    }
}

fn verifyInterface(comptime Interface: type) void {
    switch (@typeInfo(Interface)) {
        .Struct => |s| {
            // make sure it has vtable and object
            if(std.mem.eql(u8, s.fields[0].name, "vtable")) @compileError("First field of interface must be \"vtable\", it was \"" ++ s.fields[0].name ++ "\" instead");
            // vtable needs to be a struct
            if(@typeInfo(s.fields[0].type) != .Struct)@compileError("vtable must be a struct of function pointers");
            // TODO: verify every field is a function pointer
            if(std.mem.eql(u8, s.fields[1].name, "object")) @compileError("First field of interface must be \"object\", it was \"" ++ s.fields[1].name ++ "\" instead");
            if(s.fields[1].type != *anyopaque) @compileError("object must be *anyopaque");
        },
        else => @compileError("Interface must be a struct"),
    }
}

// if T == Interface, it returns Object. Otherwise returns T.
fn interfaceTypeToImplementerType(comptime Interface: type, comptime Object: type, comptime T: ?type) ?type {
    if(T == Interface){
        return Object;
    }
    return T;
}

/// Turns a function info from the interface into a function for the vtable or implementer
fn makeVtableFn(comptime Interface: type, comptime Object: type, comptime f: std.builtin.Type.Fn) std.builtin.Type.Fn {
    return std.builtin.Type.Fn {
        .alignment = f.alignment,
        .calling_convention = switch (f.calling_convention) {
            .Inline => .default,
            else => f.calling_convention,
        },
        .is_generic = f.is_generic,
        .is_var_args = f.is_var_args,
        .params = Blk: {
            var params: []const std.builtin.Type.Fn.Param = &[_]std.builtin.Type.Fn.Param{};
            inline for(f.params) |param| {
                const p = std.builtin.Type.Fn.Param {
                    .is_generic = param.is_generic,
                    .is_noalias = param.is_noalias,
                    .type = interfaceTypeToImplementerType(Interface, Object, param.type),
                };
                params = params ++ &[_]std.builtin.Type.Fn.Param{p};
            }
            break :Blk params;
        },
        .return_type = interfaceTypeToImplementerType(Interface, Object, f.return_type),

    };
}


test "extremely basic interface" {
    const Basic = struct {
        // First, you need a function that returns a type
        // VtableType is simply to give more useful info - it will rarely be needed
        fn makeBase(comptime BaseType: type) type {
            // Note that this function is actually called twice.
            // Once with with a dummy type (it's almost the same as the real one, but vtable is *anyopaque instead of the real vtable)
            // to be able to get the declarations, and again with the real types.
            // So, if you are doing any complex logic with BaseType, keep that in mind,
            return struct{
                // If the first argument is a BaseType, then it is an instance function and a vtable entry will be generated
                // Note: It might be worth inlining this function, inline is not required because there are good reasons not to do it.
                pub fn dynamicFunction(self: BaseType, argument: i32) void {
                    // This is required because zig cannot create functions at compile time.
                    // If it was possible, this boilerplate would be generated as well.
                    self.vtable.dynamicFunction(self.object, argument);
                }
            };
        }

        const Vtable = struct {
            dynamicFunction: *const fn(*anyopaque, i32) void,
        };
        // makeInterface creates an interface type that can be used to create implementations
        pub const Base = struct {
            vtable: *Vtable,
            object: *anyopaque,

            pub fn dynamicFunction(self: Base, argument: i32) void {
                self.vtable.dynamicFunction(self.object, argument);
            }
        };
        //makeInterface(makeBase);

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
    };
    
    // create an instace of the implementer
    var object = Basic.Sub{
        .value = 0,
    };
    
    // call the function directly - does not go through any indirection (for calling the function itself)
    object.dynamicFunction(100);
    try testing.expectEqual(@as(i32, 100), object.value);
    // initFromImplementer will create the implementation given an object that is an implementer,
    // generating its vtable and stuff at compile time.
    // Note that if object's lifetime ends before the baseObject, then very bad things are likely to happen.
    var baseObject = initFromImplementer(Basic.Base, Basic.Sub, &object);
    
    // This goes through two layers of indirection - object.vtable -> function -> (call the function)
    baseObject.dynamicFunction(50);

    // It should have modified the original object
    try testing.expectEqual(@as(i32, 150), object.value);
}