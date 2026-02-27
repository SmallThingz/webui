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
    gtk_frame_new: ?*const fn (?[*:0]const u8) callconv(.c) ?*common.GtkWidget = null,
    gtk_frame_set_child: ?*const fn (*common.GtkFrame, ?*common.GtkWidget) callconv(.c) void = null,
    gtk_widget_set_hexpand: ?*const fn (*common.GtkWidget, c_int) callconv(.c) void = null,
    gtk_widget_set_vexpand: ?*const fn (*common.GtkWidget, c_int) callconv(.c) void = null,

    gtk_window_set_title: *const fn (*common.GtkWindow, [*:0]const u8) callconv(.c) void,
    gtk_window_set_default_size: *const fn (*common.GtkWindow, c_int, c_int) callconv(.c) void,
    gtk_window_set_decorated: *const fn (*common.GtkWindow, c_int) callconv(.c) void,
    gtk_window_set_resizable: *const fn (*common.GtkWindow, c_int) callconv(.c) void,
    gtk_window_set_position: ?*const fn (*common.GtkWindow, c_int) callconv(.c) void = null,
    gtk_window_move: ?*const fn (*common.GtkWindow, c_int, c_int) callconv(.c) void = null,
    gtk_window_iconify: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_minimize: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_fullscreen: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_unfullscreen: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_set_icon_from_file: ?*const fn (*common.GtkWindow, [*:0]const u8, *?*common.GError) callconv(.c) c_int = null,
    gtk_window_set_icon_name: ?*const fn (*common.GtkWindow, ?[*:0]const u8) callconv(.c) void = null,
    gtk_window_maximize: *const fn (*common.GtkWindow) callconv(.c) void,
    gtk_window_unmaximize: *const fn (*common.GtkWindow) callconv(.c) void,

    gtk_widget_set_app_paintable: ?*const fn (*common.GtkWidget, c_int) callconv(.c) void = null,
    gtk_widget_get_screen: ?*const fn (*common.GtkWidget) callconv(.c) ?*common.GdkScreen = null,
    gdk_screen_get_rgba_visual: ?*const fn (*common.GdkScreen) callconv(.c) ?*common.GdkVisual = null,
    gtk_widget_set_visual: ?*const fn (*common.GtkWidget, *common.GdkVisual) callconv(.c) void = null,

    gtk_widget_get_allocated_width: *const fn (*common.GtkWidget) callconv(.c) c_int,
    gtk_widget_get_allocated_height: *const fn (*common.GtkWidget) callconv(.c) c_int,
    gtk_widget_set_size_request: ?*const fn (*common.GtkWidget, c_int, c_int) callconv(.c) void = null,
    gtk_widget_get_style_context: ?*const fn (*common.GtkWidget) callconv(.c) ?*common.GtkStyleContext = null,
    gtk_style_context_add_class: ?*const fn (*common.GtkStyleContext, [*:0]const u8) callconv(.c) void = null,
    gtk_style_context_remove_class: ?*const fn (*common.GtkStyleContext, [*:0]const u8) callconv(.c) void = null,
    gtk_widget_add_css_class: ?*const fn (*common.GtkWidget, [*:0]const u8) callconv(.c) void = null,
    gtk_widget_remove_css_class: ?*const fn (*common.GtkWidget, [*:0]const u8) callconv(.c) void = null,
    gtk_container_add: ?*const fn (*common.GtkContainer, *common.GtkWidget) callconv(.c) void = null,
    gtk_css_provider_new: ?*const fn () callconv(.c) ?*common.GtkCssProvider = null,
    gtk_css_provider_load_from_data: ?*const fn (*common.GtkCssProvider, [*:0]const u8, isize) callconv(.c) void = null,
    gtk_style_context_add_provider_for_display: ?*const fn (*common.GdkDisplay, *anyopaque, c_uint) callconv(.c) void = null,
    gdk_display_get_default: ?*const fn () callconv(.c) ?*common.GdkDisplay = null,
    gtk_widget_shape_combine_region: ?*const fn (*common.GtkWidget, ?*common.cairo_region_t) callconv(.c) void = null,
    gtk_widget_input_shape_combine_region: ?*const fn (*common.GtkWidget, ?*common.cairo_region_t) callconv(.c) void = null,
    gtk_widget_show: *const fn (*common.GtkWidget) callconv(.c) void,
    gtk_widget_hide: *const fn (*common.GtkWidget) callconv(.c) void,
    gtk_widget_destroy: ?*const fn (*common.GtkWidget) callconv(.c) void = null,
    gtk_window_destroy: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_window_close: ?*const fn (*common.GtkWindow) callconv(.c) void = null,
    gtk_widget_set_overflow: ?*const fn (*common.GtkWidget, c_int) callconv(.c) void = null,
    gtk_widget_set_opacity: ?*const fn (*common.GtkWidget, f64) callconv(.c) void = null,
    gtk_widget_get_native: ?*const fn (*common.GtkWidget) callconv(.c) ?*common.GtkNative = null,
    gtk_native_get_surface: ?*const fn (*common.GtkNative) callconv(.c) ?*common.GdkSurface = null,
    gdk_surface_set_input_region: ?*const fn (*common.GdkSurface, ?*common.cairo_region_t) callconv(.c) void = null,
    gdk_surface_set_opaque_region: ?*const fn (*common.GdkSurface, ?*common.cairo_region_t) callconv(.c) void = null,
    gdk_texture_new_from_filename: ?*const fn ([*:0]const u8, *?*common.GError) callconv(.c) ?*common.GdkTexture = null,
    gdk_toplevel_set_icon_list: ?*const fn (*common.GdkToplevel, ?*anyopaque) callconv(.c) void = null,

    webkit_web_view_new: *const fn () callconv(.c) ?*common.GtkWidget,
    webkit_web_view_load_uri: *const fn (*common.WebKitWebView, [*:0]const u8) callconv(.c) void,
    webkit_web_view_set_background_color: *const fn (*common.WebKitWebView, *const anyopaque) callconv(.c) void,

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
    g_error_free: ?*const fn (?*common.GError) callconv(.c) void = null,
    g_list_append: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = null,
    g_list_free: ?*const fn (?*anyopaque) callconv(.c) void = null,
    g_object_unref: ?*const fn (?*anyopaque) callconv(.c) void = null,

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

    pub fn addWindowChild(self: *const Symbols, window_widget: *common.GtkWidget, child_widget: *common.GtkWidget) ?*common.GtkWidget {
        switch (self.gtk_api) {
            .gtk3 => {
                if (self.gtk_container_add) |add| add(@ptrCast(window_widget), child_widget);
                return child_widget;
            },
            .gtk4 => {
                if (self.gtk_frame_new) |frame_new| {
                    if (frame_new(null)) |frame_widget| {
                        if (self.gtk_widget_set_hexpand) |set_hexpand| {
                            set_hexpand(frame_widget, 1);
                            set_hexpand(child_widget, 1);
                        }
                        if (self.gtk_widget_set_vexpand) |set_vexpand| {
                            set_vexpand(frame_widget, 1);
                            set_vexpand(child_widget, 1);
                        }
                        if (self.gtk_frame_set_child) |set_frame_child| {
                            set_frame_child(@ptrCast(frame_widget), child_widget);
                        }
                        if (self.gtk_window_set_child) |set_child| set_child(@ptrCast(window_widget), frame_widget);
                        return frame_widget;
                    }
                }
                if (self.gtk_window_set_child) |set_child| set_child(@ptrCast(window_widget), child_widget);
                return child_widget;
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
        switch (self.gtk_api) {
            .gtk3 => {
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
            },
            .gtk4 => {
                if (self.gtk_widget_set_opacity) |set_opacity| set_opacity(window_widget, 1.0);
                if (self.gtk_widget_get_native) |get_native| {
                    if (get_native(window_widget)) |native| {
                        if (self.gtk_native_get_surface) |native_surface| {
                            if (native_surface(native)) |surface| {
                                if (self.gdk_surface_set_opaque_region) |set_opaque_region| {
                                    // Null region => compositor treats the surface as potentially translucent.
                                    set_opaque_region(surface, null);
                                }
                            }
                        }
                    }
                }
            },
        }
    }

    pub fn applyGtk4WindowStyle(
        self: *const Symbols,
        window_widget: *common.GtkWidget,
        webview_widget: ?*common.GtkWidget,
        style: common.WindowStyle,
    ) void {
        if (self.gtk_api != .gtk4) return;

        const radius: u16 = style.corner_radius orelse 0;
        const overflow_value: c_int = if (radius > 0) common.GTK_OVERFLOW_HIDDEN else common.GTK_OVERFLOW_VISIBLE;

        if (self.gtk_widget_set_overflow) |set_overflow| set_overflow(window_widget, overflow_value);
        if (self.gtk_widget_set_overflow) |set_overflow| {
            if (webview_widget) |webview| set_overflow(webview, overflow_value);
        }

        if (self.gtk_css_provider_new) |provider_new| {
            if (self.gtk_css_provider_load_from_data) |load_from_data| {
                if (self.gtk_style_context_add_provider_for_display) |add_provider| {
                    if (self.gdk_display_get_default) |get_default| {
                        if (self.gtk_widget_add_css_class) |add_class| {
                            add_class(window_widget, "webui-window");
                            
                            var css_buf: [256]u8 = undefined;
                            var css_str: [:0]const u8 = "";
                            if (style.transparent and radius > 0) {
                                css_str = std.fmt.bufPrintZ(&css_buf, "window.webui-window, window.webui-window > decoration {{ background-color: transparent; border-radius: {d}px; box-shadow: none; }}\nwebview {{ border-radius: {d}px; background-color: transparent; }}", .{radius, radius}) catch "window.webui-window { background-color: transparent; }";
                            } else if (style.transparent) {
                                css_str = "window.webui-window, window.webui-window > decoration { background-color: transparent; box-shadow: none; }\nwebview { background-color: transparent; }";
                            } else if (radius > 0) {
                                css_str = std.fmt.bufPrintZ(&css_buf, "window.webui-window, window.webui-window > decoration {{ border-radius: {d}px; box-shadow: none; }}\nwebview {{ border-radius: {d}px; }}", .{radius, radius}) catch "";
                            }

                            if (css_str.len > 0) {
                                if (provider_new()) |provider| {
                                    load_from_data(provider, css_str.ptr, -1);
                                    if (get_default()) |display| {
                                        add_provider(display, provider, common.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
                                    }
                                    if (self.g_object_unref) |unref| unref(provider);
                                }
                            }
                        }
                    }
                }
            }
        }

        self.applyGtk4RoundedSurface(window_widget, style.corner_radius, style.transparent);
    }

    pub fn applyGtk4RoundedSurface(
        self: *const Symbols,
        window_widget: *common.GtkWidget,
        corner_radius: ?u16,
        transparent: bool,
    ) void {
        if (self.gtk_api != .gtk4) return;
        const get_native = self.gtk_widget_get_native orelse return;
        const get_surface = self.gtk_native_get_surface orelse return;
        const native = get_native(window_widget) orelse return;
        const surface = get_surface(native) orelse return;

        const width = self.gtk_widget_get_allocated_width(window_widget);
        const height = self.gtk_widget_get_allocated_height(window_widget);
        if (width <= 0 or height <= 0) return;

        const radius_raw: u16 = corner_radius orelse 0;
        const radius_i: c_int = @as(c_int, @intCast(radius_raw));
        if (radius_i <= 0) {
            if (self.gdk_surface_set_input_region) |set_input| set_input(surface, null);
            if (self.gdk_surface_set_opaque_region) |set_opaque| {
                if (transparent) set_opaque(surface, null);
            }
            return;
        }

        if (self.gdk_cairo_region_create_from_surface == null or
            self.cairo_image_surface_create == null or
            self.cairo_surface_destroy == null or
            self.cairo_create == null or
            self.cairo_destroy == null or
            self.cairo_set_source_rgba == null or
            self.cairo_paint == null or
            self.cairo_new_path == null or
            self.cairo_arc == null or
            self.cairo_close_path == null or
            self.cairo_rectangle == null or
            self.cairo_fill == null or
            self.cairo_region_destroy == null)
        {
            return;
        }

        const max_radius = @min(@divTrunc(width, 2), @divTrunc(height, 2));
        const radius = @min(radius_i, max_radius);
        if (radius <= 0) return;

        const surface_img = self.cairo_image_surface_create.?(common.CAIRO_FORMAT_A8, width, height) orelse return;
        defer self.cairo_surface_destroy.?(surface_img);
        const cr = self.cairo_create.?(surface_img) orelse return;
        defer self.cairo_destroy.?(cr);

        self.cairo_set_source_rgba.?(cr, 0.0, 0.0, 0.0, 0.0);
        self.cairo_paint.?(cr);
        self.cairo_set_source_rgba.?(cr, 1.0, 1.0, 1.0, 1.0);

        const w = @as(f64, @floatFromInt(width));
        const h = @as(f64, @floatFromInt(height));
        const r = @as(f64, @floatFromInt(radius));
        const pi = std.math.pi;

        self.cairo_new_path.?(cr);
        self.cairo_arc.?(cr, w - r, r, r, -pi / 2.0, 0.0);
        self.cairo_arc.?(cr, w - r, h - r, r, 0.0, pi / 2.0);
        self.cairo_arc.?(cr, r, h - r, r, pi / 2.0, pi);
        self.cairo_arc.?(cr, r, r, r, pi, pi * 1.5);
        self.cairo_close_path.?(cr);
        self.cairo_fill.?(cr);

        const region = self.gdk_cairo_region_create_from_surface.?(surface_img) orelse return;
        defer self.cairo_region_destroy.?(region);

        if (self.gdk_surface_set_input_region) |set_input| set_input(surface, region);
        if (self.gdk_surface_set_opaque_region) |set_opaque| {
            if (transparent) set_opaque(surface, null) else set_opaque(surface, region);
        }
    }

    pub fn minimizeWindow(self: *const Symbols, window: *common.GtkWindow) void {
        if (self.gtk_window_iconify) |iconify| {
            iconify(window);
            return;
        }
        if (self.gtk_window_minimize) |minimize| minimize(window);
    }

    pub fn setWindowMinSize(self: *const Symbols, window_widget: *common.GtkWidget, min_size: ?common.Size) void {
        const set_size = self.gtk_widget_set_size_request orelse return;
        if (min_size) |size| {
            set_size(window_widget, @as(c_int, @intCast(size.width)), @as(c_int, @intCast(size.height)));
        } else {
            set_size(window_widget, -1, -1);
        }
    }

    pub fn setWindowKiosk(self: *const Symbols, window: *common.GtkWindow, enabled: bool) void {
        if (enabled) {
            if (self.gtk_window_fullscreen) |fullscreen| fullscreen(window);
        } else {
            if (self.gtk_window_unfullscreen) |unfullscreen| unfullscreen(window);
        }
    }

    pub fn setWindowHighContrast(
        self: *const Symbols,
        window_widget: *common.GtkWidget,
        content_widget: ?*common.GtkWidget,
        enabled: ?bool,
    ) void {
        const set_css_class = struct {
            fn apply(syms: *const Symbols, widget: *common.GtkWidget, on: bool) void {
                if (syms.gtk_widget_add_css_class != null and syms.gtk_widget_remove_css_class != null) {
                    if (on) {
                        syms.gtk_widget_add_css_class.?(widget, "high-contrast");
                    } else {
                        syms.gtk_widget_remove_css_class.?(widget, "high-contrast");
                    }
                    return;
                }
                if (syms.gtk_widget_get_style_context) |get_ctx| {
                    if (get_ctx(widget)) |ctx| {
                        if (on) {
                            if (syms.gtk_style_context_add_class) |add| add(ctx, "high-contrast");
                        } else {
                            if (syms.gtk_style_context_remove_class) |remove| remove(ctx, "high-contrast");
                        }
                    }
                }
            }
        }.apply;

        if (enabled) |on| {
            set_css_class(self, window_widget, on);
            if (content_widget) |content| set_css_class(self, content, on);
        } else {
            set_css_class(self, window_widget, false);
            if (content_widget) |content| set_css_class(self, content, false);
        }
    }

    pub fn setWindowIconFromPath(self: *const Symbols, window_widget: *common.GtkWidget, path_z: [*:0]const u8) void {
        const window: *common.GtkWindow = @ptrCast(window_widget);

        if (self.gtk_api == .gtk3) {
            if (self.gtk_window_set_icon_from_file) |set_icon_file| {
                var err_ptr: ?*common.GError = null;
                _ = set_icon_file(window, path_z, &err_ptr);
                if (err_ptr) |err| {
                    if (self.g_error_free) |free_err| free_err(err);
                }
                return;
            }
            if (self.gtk_window_set_icon_name) |set_icon_name| {
                set_icon_name(window, "applications-internet");
            }
            return;
        }

        const new_texture = self.gdk_texture_new_from_filename orelse return;
        const get_native = self.gtk_widget_get_native orelse return;
        const get_surface = self.gtk_native_get_surface orelse return;
        const set_icon_list = self.gdk_toplevel_set_icon_list orelse return;
        const list_append = self.g_list_append orelse return;
        const list_free = self.g_list_free orelse return;

        var err_ptr: ?*common.GError = null;
        const texture = new_texture(path_z, &err_ptr) orelse {
            if (err_ptr) |err| if (self.g_error_free) |free_err| free_err(err);
            return;
        };
        defer if (self.g_object_unref) |unref| unref(texture);
        if (err_ptr) |err| if (self.g_error_free) |free_err| free_err(err);

        const native = get_native(window_widget) orelse return;
        const surface = get_surface(native) orelse return;
        const list = list_append(null, texture) orelse return;
        defer list_free(list);

        set_icon_list(@ptrCast(surface), list);
    }

    pub fn clearWindowIcon(self: *const Symbols, window_widget: *common.GtkWidget) void {
        const window: *common.GtkWindow = @ptrCast(window_widget);

        if (self.gtk_api == .gtk3) {
            if (self.gtk_window_set_icon_name) |set_icon_name| {
                set_icon_name(window, null);
            }
            return;
        }

        const get_native = self.gtk_widget_get_native orelse return;
        const get_surface = self.gtk_native_get_surface orelse return;
        const set_icon_list = self.gdk_toplevel_set_icon_list orelse return;

        const native = get_native(window_widget) orelse return;
        const surface = get_surface(native) orelse return;
        set_icon_list(@ptrCast(surface), null);
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
        self.gtk_frame_new = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_frame_new), "gtk_frame_new");
        self.gtk_frame_set_child = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_frame_set_child), "gtk_frame_set_child");
        self.gtk_widget_set_hexpand = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_hexpand), "gtk_widget_set_hexpand");
        self.gtk_widget_set_vexpand = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_vexpand), "gtk_widget_set_vexpand");

        self.gtk_window_set_title = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_title), "gtk_window_set_title");
        self.gtk_window_set_default_size = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_default_size), "gtk_window_set_default_size");
        self.gtk_window_set_decorated = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_decorated), "gtk_window_set_decorated");
        self.gtk_window_set_resizable = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_resizable), "gtk_window_set_resizable");
        self.gtk_window_set_position = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_set_position), "gtk_window_set_position");
        self.gtk_window_move = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_move), "gtk_window_move");
        self.gtk_window_iconify = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_iconify), "gtk_window_iconify");
        self.gtk_window_minimize = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_minimize), "gtk_window_minimize");
        self.gtk_window_fullscreen = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_fullscreen), "gtk_window_fullscreen");
        self.gtk_window_unfullscreen = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_unfullscreen), "gtk_window_unfullscreen");
        self.gtk_window_set_icon_from_file = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_set_icon_from_file), "gtk_window_set_icon_from_file");
        self.gtk_window_set_icon_name = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_set_icon_name), "gtk_window_set_icon_name");
        self.gtk_window_maximize = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_maximize), "gtk_window_maximize");
        self.gtk_window_unmaximize = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_unmaximize), "gtk_window_unmaximize");

        self.gtk_widget_set_app_paintable = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_app_paintable), "gtk_widget_set_app_paintable");
        self.gtk_widget_get_screen = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_get_screen), "gtk_widget_get_screen");
        self.gdk_screen_get_rgba_visual = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_screen_get_rgba_visual), "gdk_screen_get_rgba_visual");
        self.gtk_widget_set_visual = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_visual), "gtk_widget_set_visual");

        self.gtk_widget_get_allocated_width = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_get_allocated_width), "gtk_widget_get_allocated_width");
        self.gtk_widget_get_allocated_height = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_get_allocated_height), "gtk_widget_get_allocated_height");
        self.gtk_widget_set_size_request = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_size_request), "gtk_widget_set_size_request");
        self.gtk_widget_get_style_context = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_get_style_context), "gtk_widget_get_style_context");
        self.gtk_style_context_add_class = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_style_context_add_class), "gtk_style_context_add_class");
        self.gtk_style_context_remove_class = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_style_context_remove_class), "gtk_style_context_remove_class");
        self.gtk_widget_add_css_class = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_add_css_class), "gtk_widget_add_css_class");
        self.gtk_widget_remove_css_class = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_remove_css_class), "gtk_widget_remove_css_class");
        self.gtk_css_provider_new = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_css_provider_new), "gtk_css_provider_new");
        self.gtk_css_provider_load_from_data = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_css_provider_load_from_data), "gtk_css_provider_load_from_data");
        self.gtk_style_context_add_provider_for_display = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_style_context_add_provider_for_display), "gtk_style_context_add_provider_for_display");
        self.gdk_display_get_default = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_display_get_default), "gdk_display_get_default");
        self.gtk_container_add = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_container_add), "gtk_container_add");
        self.gtk_widget_shape_combine_region = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_shape_combine_region), "gtk_widget_shape_combine_region");
        self.gtk_widget_input_shape_combine_region = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_input_shape_combine_region), "gtk_widget_input_shape_combine_region");
        self.gtk_widget_show = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_show), "gtk_widget_show");
        self.gtk_widget_hide = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_hide), "gtk_widget_hide");
        self.gtk_widget_destroy = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_destroy), "gtk_widget_destroy");
        self.gtk_window_destroy = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_destroy), "gtk_window_destroy");
        self.gtk_window_close = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_window_close), "gtk_window_close");
        self.gtk_widget_set_overflow = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_overflow), "gtk_widget_set_overflow");
        self.gtk_widget_set_opacity = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_set_opacity), "gtk_widget_set_opacity");
        self.gtk_widget_get_native = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_widget_get_native), "gtk_widget_get_native");
        self.gtk_native_get_surface = lookupOptionalSym(&self.gtk, @TypeOf(self.gtk_native_get_surface), "gtk_native_get_surface");
        self.gdk_surface_set_input_region = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_surface_set_input_region), "gdk_surface_set_input_region");
        self.gdk_surface_set_opaque_region = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_surface_set_opaque_region), "gdk_surface_set_opaque_region");
        self.gdk_texture_new_from_filename = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_texture_new_from_filename), "gdk_texture_new_from_filename");
        self.gdk_toplevel_set_icon_list = lookupOptionalSym(&self.gdk, @TypeOf(self.gdk_toplevel_set_icon_list), "gdk_toplevel_set_icon_list");

        self.webkit_web_view_new = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_new), "webkit_web_view_new");
        self.webkit_web_view_load_uri = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_load_uri), "webkit_web_view_load_uri");
        self.webkit_web_view_set_background_color = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_set_background_color), "webkit_web_view_set_background_color");

        self.g_signal_connect_data = try lookupSym(&self.gobject, @TypeOf(self.g_signal_connect_data), "g_signal_connect_data");
        self.g_object_unref = lookupOptionalSym(&self.gobject, @TypeOf(self.g_object_unref), "g_object_unref");
        self.g_idle_add = try lookupSym(&self.glib, @TypeOf(self.g_idle_add), "g_idle_add");
        self.g_main_loop_new = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_new), "g_main_loop_new");
        self.g_main_loop_run = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_run), "g_main_loop_run");
        self.g_main_loop_quit = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_quit), "g_main_loop_quit");
        self.g_main_loop_unref = try lookupSym(&self.glib, @TypeOf(self.g_main_loop_unref), "g_main_loop_unref");
        self.g_error_free = lookupOptionalSym(&self.glib, @TypeOf(self.g_error_free), "g_error_free");
        self.g_list_append = lookupOptionalSym(&self.glib, @TypeOf(self.g_list_append), "g_list_append");
        self.g_list_free = lookupOptionalSym(&self.glib, @TypeOf(self.g_list_free), "g_list_free");

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
