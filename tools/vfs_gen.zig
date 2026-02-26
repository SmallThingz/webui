const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("usage: vfs_gen <input-file> <output-zig>\n", .{});
        return error.InvalidArguments;
    }

    const input_path = args[1];
    const output_path = args[2];

    const content = try std.fs.cwd().readFileAlloc(allocator, input_path, 16 * 1024 * 1024);
    defer allocator.free(content);

    if (std.fs.path.dirname(output_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }

    const out = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out.close();

    try out.writeAll("pub const bytes = [_]u8{\n");
    for (content, 0..) |byte, idx| {
        if (idx % 16 == 0) try out.writeAll("    ");

        var num_buf: [16]u8 = undefined;
        const num = try std.fmt.bufPrint(&num_buf, "0x{x:0>2}", .{byte});
        try out.writeAll(num);

        if (idx + 1 != content.len) try out.writeAll(", ");
        if (idx % 16 == 15) try out.writeAll("\n");
    }
    if (content.len % 16 != 0) try out.writeAll("\n");
    try out.writeAll("};\n");
}
