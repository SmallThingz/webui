const std = @import("std");

pub const types = @import("types.zig");
pub const handle_form = @import("handle_form.zig");
pub const matcher = @import("match.zig");
pub const md5 = @import("md5.zig");
pub const response = @import("response.zig");
pub const sha1 = @import("sha1.zig");
pub const sort = @import("sort.zig");

pub const Server = struct {
    allocator: std.mem.Allocator,
    port: u16,

    pub fn init(allocator: std.mem.Allocator, port: u16) Server {
        return .{ .allocator = allocator, .port = port };
    }

    pub fn deinit(self: *Server) void {
        _ = self;
    }

    pub fn start(self: *Server) !void {
        if (self.port == 0) return error.InvalidPort;
    }
};
