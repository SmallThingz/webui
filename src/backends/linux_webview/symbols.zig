const std = @import("std");
const common = @import("common.zig");

pub const GtkApi = enum {
    gtk3,
    gtk4,
};

pub const Symbols = struct {
    gtk: std.DynLib,
    gdk: std.DynLib,
    webkit: std.DynLib,
    gobject: std.DynLib,
    glib: std.DynLib,
    cairo: std.DynLib,
    gtk_api: GtkApi,

    gtk_init_gtk3: ?*const fn (?*c_int, ?*anyopaque) callconv(.c) void = null,
    gtk_init_gtk4: ?*const fn () callconv(.c) void = null,
    gtk_window_new_gtk3: ?*const fn (c_int) callconv(.c) ?*common.GtkWidget = null,
    gtk_window_new_gtk4: ?*const fn () callconv(.c) ?*common.GtkWidget = null,
    gtk_window_set_child: ?*const fn (*common.GtkWindow, ?*common.GtkWidget) callconv(.c) void = null,

    gtk_window_set_title: *const fn (*common.GtkWindow, [*:0]const u8) callconv(.c) void,
    gtk_window_set_default_size: *const fn (*common.GtkWindow, c_int, c_int) callconv(.c) void,
    gtk_window_set_decorated: *const fn (*common.GtkWindow, c_int) callconv(.c) void,
    gtk_window_set_resizable: *const fn (*common.GtkWindow, c_int) callconv(.c) void,
    gtk_window_set_position: ?*const fn (*common.GtkWindow, c_int) callconv(.c) void = null,
    gtk_window_move: ?*const fn (*common.GtkWindow, c_int, c_int) callconv(.c) void = null,
    gtk_window_iconify: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_minimize: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_maximize: *const fn (*common.GtkWindow) callconv(.c) void,
    gtk_window_unmaximize: *const fn (*common.GtkWindow) callconv(.c) void,

    gtk_widget_set_app_paintable: ?*const fn (*common.GtkWidget, c_int) callconv(.c) void = null,
    gtk_widget_get_screen: ?*const fn (*common.GtkWidget) callconv(.c) ?*common.GdkScreen = null,
    gdk_screen_get_rgba_visual: ?*const fn (*common.GdkScreen) callconv(.c) ?*common.GdkVisual = null,
    gtk_widget_set_visual: ?*const fn (*common.GtkWidget, *common.GdkVisual) callconv(.c) void = null,

    gtk_widget_get_allocated_width: *const fn (*common.GtkWidget) callconv(.c) c_int,
    gtk_widget_get_allocated_height: *const fn (*common.GtkWidget) callconv(.c) c_int,
    gtk_container_add: ?*const fn (*common.GtkContainer, *common.GtkWidget) callconv(.c) void = null,
    gtk_widget_shape_combine_region: ?*const fn (*common.GtkWidget, ?*common.cairo_region_t) callconv(.c) void = null,
    gtk_widget_input_shape_combine_region: ?*const fn (*common.GtkWidget, ?*common.cairo_region_t) callconv(.c) void = null,
    gtk_widget_show: *const fn (*common.GtkWidget) callconv(.c) void,
    gtk_widget_hide: *const fn (*common.GtkWidget) callconv(.c) void,
    gtk_widget_destroy: ?*const fn (*common.GtkWidget) callconv(.c) void = null,
    gtk_window_destroy: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_close: ?*const fn (*common.GtkWindow) callconv(.c) void = null,

    webkit_web_view_new: *const fn () callconv(.c) ?*common.GtkWidget,
    webkit_web_view_load_uri: *const fn (*common.WebKitWebView, [*:0]const u8) callconv(.c) void,
    webkit_web_view_set_background_color: *const fn (*common.WebKitWebView, *const common.GdkRGBA) callconv(.c) void,

    g_signal_connect_data: *const fn (
        *anyopaque,
        [*:0]const u8,
        *const anyopaque,
        ?*anyopaque,
        ?*const anyopaque,
        c_uint,
    ) callconv(.c) c_ulong,
    g_idle_add: *const fn (*const fn (?*anyopaque) callconv(.c) c_int, ?*anyopaque) callconv(.c) c_uint,
    g_main_loop_new: *const fn (?*anyopaque, c_int) callconv(.c) ?*common.GMainLoop,
    g_main_loop_run: *const fn (*common.GMainLoop) callconv(.c) void,
    g_main_loop_quit: *const fn (*common.GMainLoop) callconv(.c) void,
    g_main_loop_unref: *const fn (*common.GMainLoop) callconv(.c) void,

    gdk_cairo_region_create_from_surface: ?*const fn (*common.cairo_surface_t) callconv(.c) ?*common.cairo_region_t = null,
    cairo_image_surface_create: ?*const fn (c_int, c_int, c_int) callconv(.c) ?*common.cairo_surface_t = null,
    cairo_surface_destroy: ?*const fn (*common.cairo_surface_t) callconv(.c) void = null,
    cairo_create: ?*const fn (*common.cairo_surface_t) callconv(.c) ?*common.cairo_t = null,
    cairo_destroy: ?*const fn (*common.cairo_t) callconv(.c) void = null,
    cairo_set_source_rgba: ?*const fn (*common.cairo_t, f64, f64, f64, f64) callconv(.c) void = null,
    cairo_paint: ?*const fn (*common.cairo_t) callconv(.c) void = null,
    cairo_new_path: ?*const fn (*common.cairo_t) callconv(.c) void = null,
    cairo_arc: ?*const fn (*common.cairo_t, f64, f64, f64, f64, f64) callconv(.c) void = null,
    cairo_close_path: ?*const fn (*common.cairo_t) callconv(.c) void = null,
    cairo_rectangle: ?*const fn (*common.cairo_t, f64, f64, f64, f64) callconv(.c) void = null,
    cairo_fill: ?*const fn (*common.cairo_t) callconv(.c) void = null,
    cairo_region_destroy: ?*const fn (*common.cairo_region_t) callconv(.c) void = null,

    pub fn load() !Symbols {
        var syms: Symbols = undefined;
        try syms.loadDynLibs();
        errdefer syms.deinit();
        try syms.loadFunctions();
        return syms;
    }

    pub fn deinit(self: *Symbols) void {
        _ = self;
        // Intentionally do not dlclose GTK/WebKit/GLib stacks at runtime.
        // These GUI libraries may retain internal callbacks/threads beyond our
        // local loop teardown window; unloading them can cause shutdown-time
        // crashes when late callbacks land in unmapped code.
        //
        // Process-exit cleanup is sufficient for this host runtime.
    }

    pub fn initToolkit(self: *const Symbols) void {
        if (self.gtk_api == .gtk4) {
            if (self.gtk_init_gtk4) |init| {
                init();
                return;
            }
        }
        if (self.gtk_init_gtk3) |init| init(null, null);
    }

    pub fn newTopLevelWindow(self: *const Symbols) ?*common.GtkWidget {
        return switch (self.gtk_api) {
            .gtk3 => if (self.gtk_window_new_gtk3) |create| create(common.GTK_WINDOW_TOPLEVEL) else null,
            .gtk4 => if (self.gtk_window_new_gtk4) |create| create() else null,
        };
    }

    pub fn addWindowChild(self: *const Symbols, window_widget: *common.GtkWidget, child_widget: *common.GtkWidget) void {
        switch (self.gtk_api) {
            .gtk3 => {
                if (self.gtk_container_add) |add| add(@ptrCast(window_widget), child_widget);
            },
            .gtk4 => {
                if (self.gtk_window_set_child) |set_child| set_child(@ptrCast(window_widget), child_widget);
            },
        }
    }

    pub fn showWindow(self: *const Symbols, window_widget: *common.GtkWidget, child_widget: *common.GtkWidget) void {
        self.gtk_widget_show(child_widget);
        self.gtk_widget_show(window_widget);
    }

    pub fn destroyWindow(self: *const Symbols, window_widget: *common.GtkWidget) void {
        switch (self.gtk_api) {
            .gtk3 => {
                if (self.gtk_widget_destroy) |destroy| destroy(window_widget);
            },
            .gtk4 => {
                const window: *common.GtkWindow = @ptrCast(window_widget);
                if (self.gtk_window_destroy) |destroy_window| {
                    destroy_window(window);
                    return;
                }
                if (self.gtk_window_close) |close_window| {
                    close_window(window);
                    return;
                }
                if (self.gtk_widget_destroy) |destroy| destroy(window_widget);
            },
        }
    }

    pub fn setWindowPositionCenter(self: *const Symbols, window: *common.GtkWindow) void {
        if (self.gtk_window_set_position) |set_pos| set_pos(window, common.GTK_WIN_POS_CENTER);
    }

    pub fn setWindowPosition(self: *const Symbols, window: *common.GtkWindow, x: c_int, y: c_int) void {
        if (self.gtk_window_move) |move| move(window, x, y);
    }

    pub fn applyTransparentVisual(self: *const Symbols, window_widget: *common.GtkWidget) void {
        if (self.gtk_widget_set_app_paintable) |set_paintable| set_paintable(window_widget, 1);
        if (self.gtk_widget_get_screen) |get_screen| {
            if (get_screen(window_widget)) |screen| {
                if (self.gdk_screen_get_rgba_visual) |get_visual| {
                    if (get_visual(screen)) |visual| {
                        if (self.gtk_widget_set_visual) |set_visual| set_visual(window_widget, visual);
                    }
                }
            }
        }
    }

    pub fn minimizeWindow(self: *const Symbols, window: *common.GtkWindow) void {
        if (self.gtk_window_iconify) |iconify| {
            iconify(window);
            return;
        }
        if (self.gtk_window_minimize) |minimize| minimize(window);
    }

    pub fn supportsRoundedShape(self: *const Symbols) bool {
        return self.gtk_widget_shape_combine_region != null and
            self.gtk_widget_input_shape_combine_region != null and
            self.gdk_cairo_region_create_from_surface != null and
            self.cairo_image_surface_create != null and
            self.cairo_surface_destroy != null and
            self.cairo_create != null and
            self.cairo_destroy != null and
            self.cairo_set_source_rgba != null and
            self.cairo_paint != null and
            self.cairo_new_path != null and
            self.cairo_arc != null and
            self.cairo_close_path != null and
            self.cairo_rectangle != null and
            self.cairo_fill != null and
            self.cairo_region_destroy != null;
    }

    pub fn setRoundedRegion(self: *const Symbols, window_widget: *common.GtkWidget, region: ?*common.cairo_region_t) void {
        if (self.gtk_widget_shape_combine_region) |shape| shape(window_widget, region);
        if (self.gtk_widget_input_shape_combine_region) |input_shape| input_shape(window_widget, region);
    }

    fn loadDynLibs(self: *Symbols) !void {
        // Prefer GTK4/WebKitGTK stack first for native webview mode.
        // If that stack is unavailable or incomplete, automatically fall back
        // to GTK3/WebKit2GTK compatibility libs.
        if (self.loadDynLibsFor(
            .gtk4,
            &.{ "libgtk-4.so.1", "libgtk-4.so" },
            // Some distros do not ship a separate libgdk-4 soname and expose
            // GDK symbols via libgtk-4 instead.
            &.{ "libgdk-4.so.1", "libgdk-4.so", "libgtk-4.so.1", "libgtk-4.so" },
            &.{ "libwebkitgtk-6.0.so.4", "libwebkitgtk-6.0.so" },
        )) return;

        if (self.loadDynLibsFor(
            .gtk3,
            &.{ "libgtk-3.so.0", "libgtk-3.so" },
            &.{ "libgdk-3.so.0", "libgdk-3.so" },
            &.{ "libwebkit2gtk-4.1.so.0", "libwebkit2gtk-4.1.so", "libwebkit2gtk-4.0.so.37", "libwebkit2gtk-4.0.so" },
        )) return;

        return error.MissingSharedLibrary;
    }

    fn loadDynLibsFor(
        self: *Symbols,
        api: GtkApi,
        gtk_names: []const []const u8,
        gdk_names: []const []const u8,
        webkit_names: []const []const u8,
    ) bool {
        var gtk = openAny(gtk_names) catch return false;
        errdefer gtk.close();
        var gdk = openAny(gdk_names) catch return false;
        errdefer gdk.close();
        var webkit = openAny(webkit_names) catch return false;
        errdefer webkit.close();

        var gobject = openAny(&.{ "libgobject-2.0.so.0", "libgobject-2.0.so" }) catch return false;
        errdefer gobject.close();
        var glib = openAny(&.{ "libglib-2.0.so.0", "libglib-2.0.so" }) catch return false;
        errdefer glib.close();
        var cairo = openAny(&.{ "libcairo.so.2", "libcairo.so" }) catch return false;
        errdefer cairo.close();

        self.gtk = gtk;
        self.gdk = gdk;
        self.webkit = webkit;
        self.gobject = gobject;
        self.glib = glib;
        self.cairo = cairo;
        self.gtk_api = api;
        return true;
    }

    fn loadFunctions(self: *Symbols) !void {
        self.gtk_init_gtk3 = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_init_gtk3), "gtk_init");
        self.gtk_init_gtk4 = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_init_gtk4), "gtk_init");
        self.gtk_window_new_gtk3 = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_new_gtk3), "gtk_window_new");
        self.gtk_window_new_gtk4 = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_new_gtk4), "gtk_window_new");
        self.gtk_window_set_child = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_set_child), "gtk_window_set_child");

        self.gtk_window_set_title = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_title), "gtk_window_set_title");
        self.gtk_window_set_default_size = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_default_size), "gtk_window_set_default_size");
        self.gtk_window_set_decorated = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_decorated), "gtk_window_set_decorated");
        self.gtk_window_set_resizable = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_resizable), "gtk_window_set_resizable");
        self.gtk_window_set_position = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_set_position), "gtk_window_set_position");
        self.gtk_window_move = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_move), "gtk_window_move");
        self.gtk_window_iconify = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_iconify), "gtk_window_iconify");
        self.gtk_window_minimize = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_minimize), "gtk_window_minimize");
        self.gtk_window_maximize = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_maximize), "gtk_window_maximize");
        self.gtk_window_unmaximize = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_unmaximize), "gtk_window_unmaximize");

        self.gtk_widget_set_app_paintable = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_app_paintable), "gtk_widget_set_app_paintable");
        self.gtk_widget_get_screen = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_get_screen), "gtk_widget_get_screen");
        self.gdk_screen_get_rgba_visual = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_screen_get_rgba_visual), "gdk_screen_get_rgba_visual");
        self.gtk_widget_set_visual = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_visual), "gtk_widget_set_visual");

        self.gtk_widget_get_allocated_width = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_get_allocated_width), "gtk_widget_get_allocated_width");
        self.gtk_widget_get_allocated_height = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_get_allocated_height), "gtk_widget_get_allocated_height");
        self.gtk_container_add = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_container_add), "gtk_container_add");
        self.gtk_widget_shape_combine_region = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_shape_combine_region), "gtk_widget_shape_combine_region");
        self.gtk_widget_input_shape_combine_region = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_input_shape_combine_region), "gtk_widget_input_shape_combine_region");
        self.gtk_widget_show = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_show), "gtk_widget_show");
        self.gtk_widget_hide = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_hide), "gtk_widget_hide");
        self.gtk_widget_destroy = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_destroy), "gtk_widget_destroy");
        self.gtk_window_destroy = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_destroy), "gtk_window_destroy");
        self.gtk_window_close = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_close), "gtk_window_close");

        self.webkit_web_view_new = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_new), "webkit_web_view_new");
        self.webkit_web_view_load_uri = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_load_uri), "webkit_web_view_load_uri");
        self.webkit_web_view_set_background_color = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_set_background_color), "webkit_web_view_set_background_color");

        self.g_signal_connect_data = try lookupSym(&self.gobject, @TypeOf(self.g_signal_connect_data), "g_signal_connect_data");
        self.g_idle_add = try lookupSym(&self.glib, @TypeOf(self.g_idle_add), "g_idle_add");
        self.g_main_loop_new = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_new), "g_main_loop_new");
        self.g_main_loop_run = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_run), "g_main_loop_run");
        self.g_main_loop_quit = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_quit), "g_main_loop_quit");
        self.g_main_loop_unref = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_unref), "g_main_loop_unref");

        self.gdk_cairo_region_create_from_surface = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_cairo_region_create_from_surface), "gdk_cairo_region_create_from_surface");
        self.cairo_image_surface_create = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_image_surface_create), "cairo_image_surface_create");
        self.cairo_surface_destroy = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_surface_destroy), "cairo_surface_destroy");
        self.cairo_create = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_create), "cairo_create");
        self.cairo_destroy = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_destroy), "cairo_destroy");
        self.cairo_set_source_rgba = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_set_source_rgba), "cairo_set_source_rgba");
        self.cairo_paint = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_paint), "cairo_paint");
        self.cairo_new_path = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_new_path), "cairo_new_path");
        self.cairo_arc = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_arc), "cairo_arc");
        self.cairo_close_path = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_close_path), "cairo_close_path");
        self.cairo_rectangle = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_rectangle), "cairo_rectangle");
        self.cairo_fill = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_fill), "cairo_fill");
        self.cairo_region_destroy = lookupOptionalSym(&self.cairo, @TypeOf(self.cairo_region_destroy), "cairo_region_destroy");

        if (self.gtk_api == .gtk3 and self.gtk_window_new_gtk3 == null) return error.MissingDynamicSymbol;
        if (self.gtk_api == .gtk4 and self.gtk_window_new_gtk4 == null) return error.MissingDynamicSymbol;
        if (self.gtk_api == .gtk3 and self.gtk_widget_destroy == null) return error.MissingDynamicSymbol;
        if (self.gtk_api == .gtk4 and self.gtk_window_destroy == null and self.gtk_window_close == null and self.gtk_widget_destroy == null) return error.MissingDynamicSymbol;
    }
};

fn lookupSym(lib: *std.DynLib, comptime T: type, name: [:0]const u8) !T {
    return lib.lookup(T, name) orelse error.MissingDynamicSymbol;
}

fn lookupOptionalSym(lib: *std.DynLib, comptime T: type, name: [:0]const u8) T {
    switch (@typeInfo(T)) {
        .optional => |opt| return lib.lookup(opt.child, name),
        else => return lib.lookup(T, name),
    }
}

fn openAny(names: []const []const u8) !std.DynLib {
    for (names) |name| {
        if (std.DynLib.open(name)) |lib| return lib else |_| {}
    }
    return error.MissingSharedLibrary;
}
