const std = @import("std");

const Feature = struct {
    id: []const u8,
    domain: []const u8,
    description: []const u8,
};

const StatusEntry = struct {
    id: []const u8,
    status: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("usage: parity_report <features.json> <status.json>\n", .{});
        return error.InvalidArguments;
    }

    const feature_entries = try loadFeatures(allocator, args[1]);
    defer freeFeatures(allocator, feature_entries);

    const status_entries = try loadStatus(allocator, args[2]);
    defer freeStatus(allocator, status_entries);

    var feature_set = std.StringHashMap(void).init(allocator);
    defer feature_set.deinit();

    var duplicate_features: usize = 0;
    for (feature_entries) |entry| {
        if (entry.id.len == 0 or entry.domain.len == 0 or entry.description.len == 0) {
            return error.InvalidFeatureEntry;
        }
        if (feature_set.contains(entry.id)) {
            duplicate_features += 1;
            continue;
        }
        try feature_set.put(entry.id, {});
    }
    if (duplicate_features > 0) return error.DuplicateFeatureId;

    var status_map = std.StringHashMap([]const u8).init(allocator);
    defer status_map.deinit();

    var duplicate_status: usize = 0;
    var implemented: usize = 0;
    var partial: usize = 0;
    var missing: usize = 0;

    for (status_entries) |entry| {
        if (status_map.contains(entry.id)) {
            duplicate_status += 1;
            continue;
        }
        if (!isValidStatus(entry.status)) return error.InvalidParityStatus;
        try status_map.put(entry.id, entry.status);
    }
    if (duplicate_status > 0) return error.DuplicateStatusId;

    var uncovered: usize = 0;
    var it = feature_set.iterator();
    while (it.next()) |kv| {
        const id = kv.key_ptr.*;
        const status = status_map.get(id) orelse {
            uncovered += 1;
            continue;
        };
        if (std.mem.eql(u8, status, "implemented")) {
            implemented += 1;
        } else if (std.mem.eql(u8, status, "partial")) {
            partial += 1;
        } else {
            missing += 1;
        }
    }

    var unknown_status_ids: usize = 0;
    var sit = status_map.iterator();
    while (sit.next()) |kv| {
        if (!feature_set.contains(kv.key_ptr.*)) {
            unknown_status_ids += 1;
        }
    }

    if (unknown_status_ids > 0) return error.UnknownStatusIds;
    if (uncovered > 0) return error.UncoveredFeatureIds;
    if (missing > 0) return error.MissingFeaturesDetected;

    const total = feature_set.count();
    std.debug.print(
        "[parity] baseline={s}\n[parity] total={d} implemented={d} partial={d} missing={d}\n",
        .{ "local-webui-folder", total, implemented, partial, missing },
    );
}

fn isValidStatus(status: []const u8) bool {
    return std.mem.eql(u8, status, "implemented") or
        std.mem.eql(u8, status, "partial") or
        std.mem.eql(u8, status, "missing");
}

fn loadFeatures(allocator: std.mem.Allocator, path: []const u8) ![]Feature {
    const bytes = try readFile(allocator, path);
    defer allocator.free(bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidFeatureFile;
    const arr_val = root.object.get("features") orelse return error.InvalidFeatureFile;
    if (arr_val != .array) return error.InvalidFeatureFile;

    const out = try allocator.alloc(Feature, arr_val.array.items.len);
    for (arr_val.array.items, 0..) |item, idx| {
        if (item != .object) return error.InvalidFeatureFile;
        const id = item.object.get("id") orelse return error.InvalidFeatureFile;
        const domain = item.object.get("domain") orelse return error.InvalidFeatureFile;
        const description = item.object.get("description") orelse return error.InvalidFeatureFile;
        if (id != .string or domain != .string or description != .string) return error.InvalidFeatureFile;
        out[idx] = .{
            .id = try allocator.dupe(u8, id.string),
            .domain = try allocator.dupe(u8, domain.string),
            .description = try allocator.dupe(u8, description.string),
        };
    }
    return out;
}

fn freeFeatures(allocator: std.mem.Allocator, entries: []Feature) void {
    for (entries) |entry| {
        allocator.free(entry.id);
        allocator.free(entry.domain);
        allocator.free(entry.description);
    }
    allocator.free(entries);
}

fn loadStatus(allocator: std.mem.Allocator, path: []const u8) ![]StatusEntry {
    const bytes = try readFile(allocator, path);
    defer allocator.free(bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidStatusFile;
    const arr_val = root.object.get("features") orelse return error.InvalidStatusFile;
    if (arr_val != .array) return error.InvalidStatusFile;

    const out = try allocator.alloc(StatusEntry, arr_val.array.items.len);
    for (arr_val.array.items, 0..) |item, idx| {
        if (item != .object) return error.InvalidStatusFile;
        const id = item.object.get("id") orelse return error.InvalidStatusFile;
        const status = item.object.get("status") orelse return error.InvalidStatusFile;
        if (id != .string or status != .string) return error.InvalidStatusFile;
        out[idx] = .{
            .id = try allocator.dupe(u8, id.string),
            .status = try allocator.dupe(u8, status.string),
        };
    }
    return out;
}

fn freeStatus(allocator: std.mem.Allocator, entries: []StatusEntry) void {
    for (entries) |entry| {
        allocator.free(entry.id);
        allocator.free(entry.status);
    }
    allocator.free(entries);
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}
