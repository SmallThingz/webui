const std = @import("std");
const template = @import("bridge_template");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("usage: bridge_gen <output-js-path> [comma-separated-functions] [output-dts-path]\n", .{});
        return error.InvalidArguments;
    }

    const output_js_path = args[1];
    const function_csv: []const u8 = if (args.len >= 3) args[2] else "ping";
    const output_dts_path: ?[]const u8 = if (args.len >= 4) args[3] else null;

    var metas = std.array_list.Managed(template.RpcFunctionMeta).init(allocator);
    defer metas.deinit();

    var it = std.mem.splitScalar(u8, function_csv, ',');
    while (it.next()) |name| {
        const trimmed = std.mem.trim(u8, name, " \t\n\r");
        if (trimmed.len == 0) continue;
        try metas.append(.{ .name = trimmed, .arity = 0 });
    }

    const script_js = try template.renderForWrittenOutput(allocator, .{}, metas.items);
    defer allocator.free(script_js);

    if (std.fs.path.dirname(output_js_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }

    const file = try std.fs.cwd().createFile(output_js_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(script_js);

    if (output_dts_path) |dts_path| {
        const script_dts = try template.renderTypeScriptDeclarations(allocator, .{}, metas.items);
        defer allocator.free(script_dts);

        if (std.fs.path.dirname(dts_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }

        const dts_file = try std.fs.cwd().createFile(dts_path, .{ .truncate = true });
        defer dts_file.close();
        try dts_file.writeAll(script_dts);
    }
}
