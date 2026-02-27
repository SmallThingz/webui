const std = @import("std");
const common = @import("common.zig");
const symbols_mod = @import("symbols.zig");

pub fn applyRoundedWindowShape(
    symbols: *const symbols_mod.Symbols,
    corner_radius: ?u16,
    window_widget: *common.GtkWidget,
    width: c_int,
    height: c_int,
) void {
    if (width <= 0 or height <= 0) return;

    const radius_raw: u16 = corner_radius orelse 0;
    const radius_i: c_int = @as(c_int, @intCast(radius_raw));
    if (radius_i <= 0) {
        symbols.gtk_widget_shape_combine_region(window_widget, null);
        symbols.gtk_widget_input_shape_combine_region(window_widget, null);
        return;
    }

    const max_radius = @min(@divTrunc(width, 2), @divTrunc(height, 2));
    const radius = @min(radius_i, max_radius);
    if (radius <= 0) return;

    const region = buildRoundedRegion(symbols, width, height, radius) orelse return;
    defer symbols.cairo_region_destroy(region);

    symbols.gtk_widget_shape_combine_region(window_widget, region);
    symbols.gtk_widget_input_shape_combine_region(window_widget, region);
}

fn buildRoundedRegion(
    symbols: *const symbols_mod.Symbols,
    width: c_int,
    height: c_int,
    radius: c_int,
) ?*common.cairo_region_t {
    if (width <= 0 or height <= 0) return null;

    const surface = symbols.cairo_image_surface_create(common.CAIRO_FORMAT_A8, width, height) orelse return null;
    defer symbols.cairo_surface_destroy(surface);

    const cr = symbols.cairo_create(surface) orelse return null;
    defer symbols.cairo_destroy(cr);

    symbols.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    symbols.cairo_paint(cr);
    symbols.cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0);

    const w = @as(f64, @floatFromInt(width));
    const h = @as(f64, @floatFromInt(height));
    const r = @as(f64, @floatFromInt(radius));

    if (radius <= 0) {
        symbols.cairo_rectangle(cr, 0.0, 0.0, w, h);
        symbols.cairo_fill(cr);
        return symbols.gdk_cairo_region_create_from_surface(surface);
    }

    const pi = std.math.pi;
    symbols.cairo_new_path(cr);
    symbols.cairo_arc(cr, w - r, r, r, -pi / 2.0, 0.0);
    symbols.cairo_arc(cr, w - r, h - r, r, 0.0, pi / 2.0);
    symbols.cairo_arc(cr, r, h - r, r, pi / 2.0, pi);
    symbols.cairo_arc(cr, r, r, r, pi, pi * 1.5);
    symbols.cairo_close_path(cr);
    symbols.cairo_fill(cr);

    return symbols.gdk_cairo_region_create_from_surface(surface);
}

