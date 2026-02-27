const std = @import("std");

pub const Level = enum {
    debug,
    info,
    warn,
    err,
};

pub const Handler = *const fn (context: ?*anyopaque, level: Level, message: []const u8) void;

pub const Sink = struct {
    handler: ?Handler = null,
    context: ?*anyopaque = null,
};

pub fn emitf(sink: Sink, enabled: bool, level: Level, comptime fmt: []const u8, args: anytype) void {
    if (!enabled) return;
    if (sink.handler) |handler| {
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        handler(sink.context, level, msg);
        return;
    }
    std.debug.print(fmt, args);
}
