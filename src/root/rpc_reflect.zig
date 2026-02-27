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

            var tuple: std.meta.ArgsTuple(Fn) = undefined;
            inline for (fn_info.params, 0..) |param, idx| {
                const param_type = param.type orelse @compileError("RPC parameter type is required");
                @field(tuple, std.fmt.comptimePrint("{d}", .{idx})) = try coerceJsonArg(param_type, args[idx]);
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

pub fn coerceJsonArg(comptime T: type, value: std.json.Value) !T {
    return switch (@typeInfo(T)) {
        .bool => switch (value) {
            .bool => |b| b,
            else => error.InvalidRpcArgType,
        },
        .int, .comptime_int => switch (value) {
            .integer => |v| @as(T, @intCast(v)),
            .float => |v| @as(T, @intFromFloat(v)),
            else => error.InvalidRpcArgType,
        },
        .float, .comptime_float => switch (value) {
            .float => |v| @as(T, @floatCast(v)),
            .integer => |v| @as(T, @floatFromInt(v)),
            else => error.InvalidRpcArgType,
        },
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) {
                break :blk switch (value) {
                    .string => |s| s,
                    else => error.InvalidRpcArgType,
                };
            }
            break :blk error.UnsupportedRpcArgType;
        },
        .optional => |opt| blk: {
            if (value == .null) break :blk @as(T, null);
            const unwrapped = try coerceJsonArg(opt.child, value);
            break :blk unwrapped;
        },
        .@"enum" => |enum_info| blk: {
            _ = enum_info;
            const raw = switch (value) {
                .string => |s| s,
                else => break :blk error.InvalidRpcArgType,
            };
            break :blk std.meta.stringToEnum(T, raw) orelse error.InvalidRpcArgType;
        },
        else => error.UnsupportedRpcArgType,
    };
}

pub fn encodeJsonValue(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, value, .{});
}
