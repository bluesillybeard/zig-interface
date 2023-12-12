const std = @import("std");

pub fn makeInterface(comptime makeTypeFn: fn(type)type) type {
    // First, make a dummy type so we can get the declarations
    const DummyInterface = struct {
        vtable: *anyopaque,
        object: *anyopaque,
        // This is a strange use of usingnamespace but it works
        pub usingnamespace makeTypeFn(@This());
    };

    const Vtable = makeVtable(DummyInterface);

    // build the interface struct
    return struct {
        vtable: *Vtable,
        object: *anyopaque,

        const This = @This();
        pub usingnamespace makeTypeFn(This);

        pub fn initFromImplementer(comptime Object: type, object: *Object) This{
            //verifyInterface(Interface);
            const objectTypeInfo = @typeInfo(Object);
            switch (objectTypeInfo) {
                .Struct => {        
                    // build the vtable
                    const vtableInfo = @typeInfo(Vtable);
                    var vtable: Vtable = undefined;
                    inline for(vtableInfo.Struct.fields) |field|{
                        if(!@hasDecl(Object, field.name)) @compileError("Object does not implement " ++ field.name);
                        const decl = @field(Object, field.name);
                        // make sure the decl is a function with the right parameters
                        const declInfo = @typeInfo(@TypeOf(decl));
                        switch (declInfo) {
                            .Fn => {
                                // TODO: validate that the function signature matches
                                const ptr = &@field(Object, field.name);
                                @field(vtable, field.name) = @ptrCast(ptr);
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
    };
}

fn functionsEqual(comptime a: std.builtin.Type.Fn, comptime b: std.builtin.Type.Fn) bool {
    _ = a;
    _ = b;

    // TODO
    return true;
}

/// Takes the base type and returns the vtable type
fn makeVtable(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Struct => |dummyInfo|{
            var vtableFields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
            inline for(dummyInfo.decls) |decl| {
                const name = decl.name;
                // skip functions prefixed with static_
                // TODO: change when zig adds a way to differentiate without a prefix
                const isStaticInstanceFunction = comptime std.mem.startsWith(u8, name, "static_");
                if(!isStaticInstanceFunction){
                    // mildly annoys me that @field is used for both fields and declarations
                    const actualDecl = @field(T, name);
                    const DeclType = @TypeOf(actualDecl);
                    switch (@typeInfo(DeclType)) {
                        .Fn => |f|{
                            // skip non-instance functions
                            if(f.params[0].type == T){
                                const VtableFieldType = @Type(std.builtin.Type{
                                    .Fn = makeVtableFn(T, *anyopaque, f),
                                });
                                const vtableField = std.builtin.Type.StructField{
                                    .alignment = @alignOf(VtableFieldType),
                                    .default_value = null,
                                    .is_comptime = false,
                                    .name = name,
                                    .type = *const VtableFieldType,
                                };
                                vtableFields = vtableFields ++ &[_]std.builtin.Type.StructField{vtableField};
                            }
                        },
                        // non-function declarations are allowed - they are just skipped
                        else => {},
                    }
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