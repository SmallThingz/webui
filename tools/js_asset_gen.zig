const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 4) {
        std.debug.print("usage: js_asset_gen <input-js> <output-js> <minify:0|1>\n", .{});
        return error.InvalidArguments;
    }

    const input_path = args[1];
    const output_path = args[2];
    const minify = std.mem.eql(u8, args[3], "1");

    if (std.fs.path.dirname(output_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }

    try copyFile(input_path, output_path, minify);
}

fn copyFile(input_path: []const u8, output_path: []const u8, minify: bool) !void {
    const input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const data = try input.readToEndAlloc(std.heap.page_allocator, 4 * 1024 * 1024);
    defer std.heap.page_allocator.free(data);

    const output = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer output.close();
    if (!minify) {
        try output.writeAll(data);
        return;
    }

    // Pure Zig build: no external jsmin binary and no C compilation dependency.
    // Keep deterministic output by trimming trailing spaces and normalizing line-endings.
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer out.deinit();

    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line_raw| {
        var line = line_raw;
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        line = std.mem.trimRight(u8, line, " \t");
        try out.appendSlice(line);
        try out.append('\n');
    }

    try output.writeAll(out.items);
}
