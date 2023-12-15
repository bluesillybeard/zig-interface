const std = @import("std");

pub const InterfaceOptions = struct {
    /// Whether to allow an implementation to use a different type than the interface, assuming the two types are both extern or packed and are the same size.
    allow_bitwise_compatibility: bool = false,
};

pub fn makeInterface(comptime makeTypeFn: fn(type)type, comptime options: InterfaceOptions) type {
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
            const objectTypeInfo = @typeInfo(Object);
            switch (objectTypeInfo) {
                .Struct => {        
                    // build the vtable
                    const vtableInfo = @typeInfo(Vtable);
                    // Needs to be comptime so it is embedded into the output artifact instead of being on the stack.
                    comptime var vtable: Vtable = undefined;
                    inline for(vtableInfo.Struct.fields) |field|{
                        if(!@hasDecl(Object, field.name)) @compileError("Object does not implement " ++ field.name);
                        const decl = @field(Object, field.name);
                        // make sure the decl is a function with the right parameters
                        const declInfo = @typeInfo(@TypeOf(decl));
                        switch (declInfo) {
                            .Fn => |implFn| {
                                const vtableFn = @typeInfo(@typeInfo(field.type).Pointer.child).Fn;
                                const valid = comptime implementationFunctionValid(vtableFn, implFn, options);
                                if(!valid) {
                                    @compileError("Function signatures for " ++ field.name ++ " are incompatible!");
                                }
                                @field(vtable, field.name) = @ptrCast(&decl);
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

// TODO: instead of returning a boolean, return a useful message if they aren't compatible
fn implementationFunctionValid(comptime vtableFn: std.builtin.Type.Fn, comptime implementerFn: std.builtin.Type.Fn, options: InterfaceOptions) bool {
    // A's allignment must be <= to B's, because otherwise B might be placed at an offset that is uncallable from A.
    if(
           vtableFn.alignment > implementerFn.alignment
        or vtableFn.calling_convention != implementerFn.calling_convention
        or vtableFn.is_generic != implementerFn.is_generic
        or vtableFn.is_var_args != implementerFn.is_var_args
        or vtableFn.params.len != implementerFn.params.len) return false;

    // TODO if A returns anyopaque, let B return any pointer
    // TODO: options.allow_bitwise_compatibility
    if(vtableFn.return_type != implementerFn.return_type) return false;
    // For each parameter
    inline for(vtableFn.params, 0..) |parameter_vt, index| {
        const parameter_impl = implementerFn.params[index];
        if(parameter_vt.is_generic != parameter_impl.is_generic) return false;
        if(parameter_vt.is_noalias != parameter_impl.is_noalias) return false;
        if(parameter_vt.type == *anyopaque) {
            if(parameter_impl.type == null) return false;
            const parameter_b_info = @typeInfo(parameter_impl.type.?);
            if(parameter_b_info != .Pointer) return false;
        } else {
            if(options.allow_bitwise_compatibility ){
                return areTypesBitCompatible(parameter_vt.type.?, parameter_impl.type.?);
            }
            else if (parameter_vt.type != parameter_impl.type) return false;
        }
    }

    // If all the above checks succeed, then return true.
    return true;
}

/// returns true if two types are allowed to be directly cast when the allow_bitwise_compatibility option is set.
fn areTypesBitCompatible(comptime vt: type, comptime impl: type) bool {
    // TODO: non-structs
    switch (@typeInfo(vt)) {
        .Struct => |svt|{
            if(@typeInfo(impl) == .Struct) {
                const simpl = @typeInfo(impl).Struct;
                // two structs are compatible if:
                // - they are both extern or both packed
                // - they are the same size
                // TODO: change those terms to also include the fields of the structs
                if(svt.layout == .Auto or simpl.layout == .Auto) return false;
                return if(svt.layout != simpl.layout) false else @sizeOf(vt) == @sizeOf(impl);

            } else return false;
        },
        else => return false
    }
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
            .Inline => .Unspecified,
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