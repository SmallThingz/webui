const std = @import("std");

pub const SEL = ?*anyopaque;

pub const ObjcGetClassFn = *const fn ([*:0]const u8) callconv(.c) ?*anyopaque;
pub const SelRegisterNameFn = *const fn ([*:0]const u8) callconv(.c) SEL;
pub const ObjcAutoreleasePoolPushFn = *const fn () callconv(.c) ?*anyopaque;
pub const ObjcAutoreleasePoolPopFn = *const fn (?*anyopaque) callconv(.c) void;

pub const Symbols = struct {
    objc: std.DynLib,
    appkit: std.DynLib,
    webkit: std.DynLib,

    objc_get_class: ObjcGetClassFn,
    sel_register_name: SelRegisterNameFn,
    objc_msg_send: *const anyopaque,
    autorelease_pool_push: ObjcAutoreleasePoolPushFn,
    autorelease_pool_pop: ObjcAutoreleasePoolPopFn,

    pub fn load() !Symbols {
        var objc = try std.DynLib.open("/usr/lib/libobjc.A.dylib");
        errdefer objc.close();

        var appkit = try std.DynLib.open("/System/Library/Frameworks/AppKit.framework/AppKit");
        errdefer appkit.close();

        var webkit = try std.DynLib.open("/System/Library/Frameworks/WebKit.framework/WebKit");
        errdefer webkit.close();

        const objc_get_class = objc.lookup(ObjcGetClassFn, "objc_getClass") orelse return error.MissingDynamicSymbol;
        const sel_register_name = objc.lookup(SelRegisterNameFn, "sel_registerName") orelse return error.MissingDynamicSymbol;
        const objc_msg_send = objc.lookup(*const anyopaque, "objc_msgSend") orelse return error.MissingDynamicSymbol;
        const autorelease_pool_push = objc.lookup(ObjcAutoreleasePoolPushFn, "objc_autoreleasePoolPush") orelse return error.MissingDynamicSymbol;
        const autorelease_pool_pop = objc.lookup(ObjcAutoreleasePoolPopFn, "objc_autoreleasePoolPop") orelse return error.MissingDynamicSymbol;

        return .{
            .objc = objc,
            .appkit = appkit,
            .webkit = webkit,
            .objc_get_class = objc_get_class,
            .sel_register_name = sel_register_name,
            .objc_msg_send = objc_msg_send,
            .autorelease_pool_push = autorelease_pool_push,
            .autorelease_pool_pop = autorelease_pool_pop,
        };
    }

    pub fn deinit(self: *Symbols) void {
        self.webkit.close();
        self.appkit.close();
        self.objc.close();
    }
};

test "objc selector type is pointer-sized" {
    try std.testing.expect(@sizeOf(SEL) == @sizeOf(?*anyopaque));
}
