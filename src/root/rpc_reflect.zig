const std = @import("std");
const types = @import("api_types.zig");

pub fn buildTsArgSignature(allocator: std.mem.Allocator, comptime params: anytype) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    inline for (params, 0..) |param, idx| {
        if (idx != 0) try out.appendSlice(", ");
        const param_type = param.type orelse return error.InvalidRpcParamType;
        try out.writer().print("arg{d}: {s}", .{ idx, tsTypeNameForType(param_type) });
    }

    return out.toOwnedSlice();
}

pub fn tsTypeNameForReturn(comptime return_type: type) []const u8 {
    if (@typeInfo(return_type) == .error_union) {
        const payload = @typeInfo(return_type).error_union.payload;
        return tsTypeNameForType(payload);
    }
    return tsTypeNameForType(return_type);
}

pub fn tsTypeNameForType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .bool => "boolean",
        .int, .comptime_int, .float, .comptime_float => "number",
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) break :blk "string";
            break :blk "unknown";
        },
        .optional => "unknown | null",
        .@"enum" => "string",
        .void => "void",
        else => "unknown",
    };
}

pub fn makeInvoker(comptime RpcStruct: type, comptime function_name: []const u8) types.RpcInvokeFn {
    return struct {
        fn invoke(allocator: std.mem.Allocator, args: []const std.json.Value) anyerror![]u8 {
            const function = @field(RpcStruct, function_name);
            const Fn = @TypeOf(function);
            const fn_info = @typeInfo(Fn).@"fn";

            if (args.len != fn_info.params.len) return error.InvalidRpcArgCount;

            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const arg_allocator = arena.allocator();

            var tuple: std.meta.ArgsTuple(Fn) = undefined;
            inline for (fn_info.params, 0..) |param, idx| {
                const param_type = param.type orelse @compileError("RPC parameter type is required");
                @field(tuple, std.fmt.comptimePrint("{d}", .{idx})) = try coerceJsonArg(param_type, arg_allocator, args[idx]);
            }

            const return_type = fn_info.return_type orelse void;

            if (@typeInfo(return_type) == .error_union) {
                const result = try @call(.auto, function, tuple);
                return try encodeJsonValue(allocator, result);
            }

            if (return_type == void) {
                @call(.auto, function, tuple);
                return try allocator.dupe(u8, "null");
            }

            const result = @call(.auto, function, tuple);
            return try encodeJsonValue(allocator, result);
        }
    }.invoke;
}

pub fn coerceJsonArg(comptime T: type, allocator: std.mem.Allocator, value: std.json.Value) !T {
    return std.json.parseFromValueLeaky(T, allocator, value, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return error.InvalidRpcArgType;
    };
}

pub fn encodeJsonValue(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, value, .{});
}
