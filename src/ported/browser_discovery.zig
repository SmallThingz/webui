const std = @import("std");
const builtin = @import("builtin");

pub const BrowserKind = enum {
    chrome,
    edge,
    safari,
    firefox,
    chromium,
    opera,
    brave,
    vivaldi,
    epic,
    yandex,
    duckduckgo,
    tor,
    librewolf,
    mullvad,
    arc,
    sidekick,
    shift,
    operagx,
    palemoon,
    sigmaos,
};

pub const BrowserSource = enum {
    explicit_env,
    known_path,
    path_env,
    app_bundle,
    directory_scan,
};

pub const BrowserInstall = struct {
    kind: BrowserKind,
    path: []u8,
    source: BrowserSource,
    score: i32,
};

const BrowserSpec = struct {
    kind: BrowserKind,
    score_weight: i32,
    executable_names: []const []const u8,
    known_paths: []const []const u8,
    mac_bundle_names: []const []const u8 = &.{},
};

pub const all_browser_kinds = [_]BrowserKind{
    .chrome,
    .edge,
    .safari,
    .firefox,
    .chromium,
    .opera,
    .brave,
    .vivaldi,
    .epic,
    .yandex,
    .duckduckgo,
    .tor,
    .librewolf,
    .mullvad,
    .arc,
    .sidekick,
    .shift,
    .operagx,
    .palemoon,
    .sigmaos,
};

const env_browser_keys = [_][]const u8{
    "WEBUI_BROWSER_PATH",
    "WEBUI_BROWSER",
    "BROWSER",
};

pub fn discoverInstalledBrowsers(allocator: std.mem.Allocator) ![]BrowserInstall {
    var installs = std.array_list.Managed(BrowserInstall).init(allocator);
    var dedup = std.StringHashMap(usize).init(allocator);
    var dedup_keys = std.array_list.Managed([]u8).init(allocator);

    errdefer {
        freeInstalls(allocator, installs.items);
        installs.deinit();
        for (dedup_keys.items) |key| allocator.free(key);
        dedup_keys.deinit();
        dedup.deinit();
    }

    try collectExplicitEnv(allocator, &installs, &dedup, &dedup_keys);
    try collectKnownPaths(allocator, &installs, &dedup, &dedup_keys);
    try collectPathEnv(allocator, &installs, &dedup, &dedup_keys);
    try collectDirectoryScans(allocator, &installs, &dedup, &dedup_keys);
    try collectMacBundleScans(allocator, &installs, &dedup, &dedup_keys);

    std.sort.heap(BrowserInstall, installs.items, {}, lessThanInstall);

    const out = try installs.toOwnedSlice();
    installs = std.array_list.Managed(BrowserInstall).init(allocator);

    for (dedup_keys.items) |key| allocator.free(key);
    dedup_keys.deinit();
    dedup.deinit();

    return out;
}

pub fn freeInstalls(allocator: std.mem.Allocator, installs: []const BrowserInstall) void {
    for (installs) |install| allocator.free(install.path);
    allocator.free(installs);
}

fn collectExplicitEnv(
    allocator: std.mem.Allocator,
    installs: *std.array_list.Managed(BrowserInstall),
    dedup: *std.StringHashMap(usize),
    dedup_keys: *std.array_list.Managed([]u8),
) !void {
    for (env_browser_keys, 0..) |key, key_index| {
        const value = std.process.getEnvVarOwned(allocator, key) catch continue;
        defer allocator.free(value);

        const resolved = try resolveCommandOrPath(allocator, value);
        defer if (resolved) |p| allocator.free(p);

        if (resolved) |path| {
            try appendInstall(
                allocator,
                installs,
                dedup,
                dedup_keys,
                .{
                    .kind = inferKindFromPath(path),
                    .path = try allocator.dupe(u8, path),
                    .source = .explicit_env,
                    .score = 1400 - @as(i32, @intCast(key_index)),
                },
            );
        }
    }
}

fn collectKnownPaths(
    allocator: std.mem.Allocator,
    installs: *std.array_list.Managed(BrowserInstall),
    dedup: *std.StringHashMap(usize),
    dedup_keys: *std.array_list.Managed([]u8),
) !void {
    for (activeSpecs()) |spec| {
        for (spec.known_paths) |known| {
            const expanded = expandPathTemplate(allocator, known) catch continue;
            defer allocator.free(expanded);

            if (!pathExists(expanded)) continue;

            try appendInstall(
                allocator,
                installs,
                dedup,
                dedup_keys,
                .{
                    .kind = spec.kind,
                    .path = try allocator.dupe(u8, expanded),
                    .source = .known_path,
                    .score = 850 + spec.score_weight,
                },
            );
        }
    }
}

fn collectPathEnv(
    allocator: std.mem.Allocator,
    installs: *std.array_list.Managed(BrowserInstall),
    dedup: *std.StringHashMap(usize),
    dedup_keys: *std.array_list.Managed([]u8),
) !void {
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch return;
    defer allocator.free(path_env);

    var dir_it = std.mem.splitScalar(u8, path_env, std.fs.path.delimiter);
    while (dir_it.next()) |raw_dir| {
        const dir = std.mem.trim(u8, raw_dir, " \t\r\n\"");
        if (dir.len == 0) continue;

        for (activeSpecs()) |spec| {
            for (spec.executable_names) |exec_name| {
                if (exec_name.len == 0) continue;
                const joined = std.fs.path.join(allocator, &.{ dir, exec_name }) catch continue;
                defer allocator.free(joined);

                if (!pathExists(joined)) continue;

                try appendInstall(
                    allocator,
                    installs,
                    dedup,
                    dedup_keys,
                    .{
                        .kind = spec.kind,
                        .path = try allocator.dupe(u8, joined),
                        .source = .path_env,
                        .score = 700 + spec.score_weight,
                    },
                );
            }
        }
    }
}

fn collectDirectoryScans(
    allocator: std.mem.Allocator,
    installs: *std.array_list.Managed(BrowserInstall),
    dedup: *std.StringHashMap(usize),
    dedup_keys: *std.array_list.Managed([]u8),
) !void {
    const dirs = switch (builtin.os.tag) {
        .windows => windowsSearchDirs,
        .macos => macosSearchDirs,
        else => linuxSearchDirs,
    };

    for (dirs) |dir_template| {
        const dir = expandPathTemplate(allocator, dir_template) catch continue;
        defer allocator.free(dir);

        if (!directoryExists(dir)) continue;

        for (activeSpecs()) |spec| {
            for (spec.executable_names) |exec_name| {
                if (exec_name.len == 0) continue;
                const joined = std.fs.path.join(allocator, &.{ dir, exec_name }) catch continue;
                defer allocator.free(joined);

                if (!pathExists(joined)) continue;

                try appendInstall(
                    allocator,
                    installs,
                    dedup,
                    dedup_keys,
                    .{
                        .kind = spec.kind,
                        .path = try allocator.dupe(u8, joined),
                        .source = .directory_scan,
                        .score = 620 + spec.score_weight,
                    },
                );
            }
        }
    }
}

fn collectMacBundleScans(
    allocator: std.mem.Allocator,
    installs: *std.array_list.Managed(BrowserInstall),
    dedup: *std.StringHashMap(usize),
    dedup_keys: *std.array_list.Managed([]u8),
) !void {
    if (builtin.os.tag != .macos) return;

    for (macosAppRoots) |root_template| {
        const root = expandPathTemplate(allocator, root_template) catch continue;
        defer allocator.free(root);

        if (!directoryExists(root)) continue;

        for (activeSpecs()) |spec| {
            if (spec.mac_bundle_names.len == 0) continue;

            for (spec.mac_bundle_names) |bundle| {
                const app_name = try std.fmt.allocPrint(allocator, "{s}.app", .{bundle});
                defer allocator.free(app_name);

                for (spec.executable_names) |exec_name| {
                    const bundle_path = std.fs.path.join(allocator, &.{ root, app_name, "Contents", "MacOS", exec_name }) catch continue;
                    defer allocator.free(bundle_path);

                    if (!pathExists(bundle_path)) continue;

                    try appendInstall(
                        allocator,
                        installs,
                        dedup,
                        dedup_keys,
                        .{
                            .kind = spec.kind,
                            .path = try allocator.dupe(u8, bundle_path),
                            .source = .app_bundle,
                            .score = 760 + spec.score_weight,
                        },
                    );
                }
            }
        }
    }
}

fn appendInstall(
    allocator: std.mem.Allocator,
    installs: *std.array_list.Managed(BrowserInstall),
    dedup: *std.StringHashMap(usize),
    dedup_keys: *std.array_list.Managed([]u8),
    candidate: BrowserInstall,
) !void {
    const key = try normalizePathKey(allocator, candidate.path);

    if (dedup.get(key)) |idx| {
        allocator.free(key);
        const existing = &installs.items[idx];
        if (candidate.score > existing.score) {
            allocator.free(existing.path);
            existing.* = candidate;
        } else {
            allocator.free(candidate.path);
        }
        return;
    }

    const insert_idx = installs.items.len;
    try installs.append(candidate);
    try dedup.put(key, insert_idx);
    try dedup_keys.append(key);
}

fn lessThanInstall(_: void, lhs: BrowserInstall, rhs: BrowserInstall) bool {
    if (lhs.score != rhs.score) return lhs.score > rhs.score;
    return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
}

fn resolveCommandOrPath(allocator: std.mem.Allocator, raw_value: []const u8) !?[]u8 {
    const command_token = try extractCommandToken(allocator, raw_value);
    defer if (command_token) |token| allocator.free(token);
    if (command_token == null) return null;
    const trimmed = command_token.?;

    const looks_path_like = std.fs.path.isAbsolute(trimmed) or
        std.mem.indexOfScalar(u8, trimmed, '/') != null or
        std.mem.indexOfScalar(u8, trimmed, '\\') != null;

    if (looks_path_like) {
        const expanded = try expandPathTemplate(allocator, trimmed);
        errdefer allocator.free(expanded);
        if (!pathExists(expanded)) return null;
        return expanded;
    }

    return try resolveInPath(allocator, trimmed);
}

fn extractCommandToken(allocator: std.mem.Allocator, raw_value: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, raw_value, " \t\r\n");
    if (trimmed.len == 0) return null;

    if (trimmed[0] == '"') {
        const close = std.mem.indexOfScalarPos(u8, trimmed, 1, '"') orelse return null;
        if (close <= 1) return null;
        return try allocator.dupe(u8, trimmed[1..close]);
    }

    const first_ws = std.mem.indexOfAny(u8, trimmed, " \t\r\n");
    if (first_ws) |idx| {
        if (idx == 0) return null;
        return try allocator.dupe(u8, trimmed[0..idx]);
    }

    return try allocator.dupe(u8, trimmed);
}

fn resolveInPath(allocator: std.mem.Allocator, command: []const u8) !?[]u8 {
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch return null;
    defer allocator.free(path_env);

    var dir_it = std.mem.splitScalar(u8, path_env, std.fs.path.delimiter);
    while (dir_it.next()) |raw_dir| {
        const dir = std.mem.trim(u8, raw_dir, " \t\r\n\"");
        if (dir.len == 0) continue;

        const joined = std.fs.path.join(allocator, &.{ dir, command }) catch continue;
        if (pathExists(joined)) return joined;
        allocator.free(joined);

        if (builtin.os.tag == .windows and !std.mem.endsWith(u8, command, ".exe")) {
            const command_exe = try std.fmt.allocPrint(allocator, "{s}.exe", .{command});
            defer allocator.free(command_exe);

            const joined_exe = std.fs.path.join(allocator, &.{ dir, command_exe }) catch continue;
            if (pathExists(joined_exe)) return joined_exe;
            allocator.free(joined_exe);
        }
    }

    return null;
}

fn containsTokenIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }

    return false;
}

fn inferKindFromPath(path: []const u8) BrowserKind {
    if (containsTokenIgnoreCase(path, "msedge") or containsTokenIgnoreCase(path, "edge")) return .edge;
    if (containsTokenIgnoreCase(path, "chrome") and !containsTokenIgnoreCase(path, "chromium")) return .chrome;
    if (containsTokenIgnoreCase(path, "chromium") or containsTokenIgnoreCase(path, "ungoogled")) return .chromium;
    if (containsTokenIgnoreCase(path, "firefox")) return .firefox;
    if (containsTokenIgnoreCase(path, "safari")) return .safari;
    if (containsTokenIgnoreCase(path, "brave")) return .brave;
    if (containsTokenIgnoreCase(path, "vivaldi")) return .vivaldi;
    if (containsTokenIgnoreCase(path, "opera gx") or containsTokenIgnoreCase(path, "operagx") or containsTokenIgnoreCase(path, "opera-gx")) return .operagx;
    if (containsTokenIgnoreCase(path, "opera")) return .opera;
    if (containsTokenIgnoreCase(path, "epic")) return .epic;
    if (containsTokenIgnoreCase(path, "yandex")) return .yandex;
    if (containsTokenIgnoreCase(path, "duckduckgo")) return .duckduckgo;
    if (containsTokenIgnoreCase(path, "librewolf")) return .librewolf;
    if (containsTokenIgnoreCase(path, "mullvad")) return .mullvad;
    if (containsTokenIgnoreCase(path, "tor")) return .tor;
    if (containsTokenIgnoreCase(path, "arc")) return .arc;
    if (containsTokenIgnoreCase(path, "sidekick")) return .sidekick;
    if (containsTokenIgnoreCase(path, "shift")) return .shift;
    if (containsTokenIgnoreCase(path, "palemoon") or containsTokenIgnoreCase(path, "pale moon")) return .palemoon;
    if (containsTokenIgnoreCase(path, "sigmaos")) return .sigmaos;
    return .chromium;
}

fn normalizePathKey(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, path, " \t\r\n\"");
    if (builtin.os.tag == .windows) {
        const lowered = try std.ascii.allocLowerString(allocator, trimmed);
        for (lowered) |*c| {
            if (c.* == '/') c.* = '\\';
        }
        return lowered;
    }
    return allocator.dupe(u8, trimmed);
}

fn getHomeDir(allocator: std.mem.Allocator) ?[]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
    if (home) |h| return h;
    if (builtin.os.tag == .windows) {
        return std.process.getEnvVarOwned(allocator, "USERPROFILE") catch null;
    }
    return null;
}

fn expandPathTemplate(allocator: std.mem.Allocator, template: []const u8) ![]u8 {
    const home = getHomeDir(allocator);
    defer if (home) |h| allocator.free(h);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < template.len) {
        const ch = template[i];

        if (i == 0 and ch == '~' and template.len > 1 and (template[1] == '/' or template[1] == '\\')) {
            if (home) |h| {
                try out.appendSlice(h);
                i += 1;
                continue;
            }
        }

        if (ch == '%' and builtin.os.tag == .windows) {
            const end = std.mem.indexOfScalarPos(u8, template, i + 1, '%') orelse {
                try out.append(ch);
                i += 1;
                continue;
            };

            const key = template[i + 1 .. end];
            const value = std.process.getEnvVarOwned(allocator, key) catch null;
            defer if (value) |v| allocator.free(v);

            if (value) |v| {
                try out.appendSlice(v);
            } else {
                try out.appendSlice(template[i .. end + 1]);
            }

            i = end + 1;
            continue;
        }

        if (ch == '$') {
            if (std.mem.startsWith(u8, template[i..], "$HOME")) {
                if (home) |h| try out.appendSlice(h);
                i += "$HOME".len;
                continue;
            }
            if (std.mem.startsWith(u8, template[i..], "${HOME}")) {
                if (home) |h| try out.appendSlice(h);
                i += "${HOME}".len;
                continue;
            }
        }

        try out.append(ch);
        i += 1;
    }

    return out.toOwnedSlice();
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn directoryExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn activeSpecs() []const BrowserSpec {
    return switch (builtin.os.tag) {
        .windows => windows_specs[0..],
        .macos => macos_specs[0..],
        else => linux_specs[0..],
    };
}

fn findSpec(kind: BrowserKind) ?BrowserSpec {
    for (activeSpecs()) |spec| {
        if (spec.kind == kind) return spec;
    }
    return null;
}

fn findSpecIn(specs: []const BrowserSpec, kind: BrowserKind) ?BrowserSpec {
    for (specs) |spec| {
        if (spec.kind == kind) return spec;
    }
    return null;
}

const windows_specs = [_]BrowserSpec{
    .{ .kind = .chrome, .score_weight = 120, .executable_names = &.{ "chrome.exe", "chrome" }, .known_paths = &.{ "%PROGRAMFILES%\\Google\\Chrome\\Application\\chrome.exe", "%PROGRAMFILES(X86)%\\Google\\Chrome\\Application\\chrome.exe", "%LOCALAPPDATA%\\Google\\Chrome\\Application\\chrome.exe", "%PROGRAMFILES%\\Google\\Chrome Beta\\Application\\chrome.exe", "%PROGRAMFILES%\\Google\\Chrome Dev\\Application\\chrome.exe" } },
    .{ .kind = .edge, .score_weight = 120, .executable_names = &.{ "msedge.exe", "msedge" }, .known_paths = &.{ "%PROGRAMFILES%\\Microsoft\\Edge\\Application\\msedge.exe", "%PROGRAMFILES(X86)%\\Microsoft\\Edge\\Application\\msedge.exe", "%PROGRAMFILES%\\Microsoft\\Edge Beta\\Application\\msedge.exe", "%PROGRAMFILES%\\Microsoft\\Edge Dev\\Application\\msedge.exe", "%LOCALAPPDATA%\\Microsoft\\Edge SxS\\Application\\msedge.exe" } },
    .{ .kind = .firefox, .score_weight = 110, .executable_names = &.{ "firefox.exe", "firefox" }, .known_paths = &.{ "%PROGRAMFILES%\\Mozilla Firefox\\firefox.exe", "%PROGRAMFILES(X86)%\\Mozilla Firefox\\firefox.exe", "%PROGRAMFILES%\\Firefox Developer Edition\\firefox.exe", "%PROGRAMFILES%\\Firefox Nightly\\firefox.exe" } },
    .{ .kind = .chromium, .score_weight = 100, .executable_names = &.{ "chromium.exe", "chrome.exe", "chromium", "chrome" }, .known_paths = &.{ "%PROGRAMFILES%\\Chromium\\Application\\chrome.exe", "%PROGRAMFILES(X86)%\\Chromium\\Application\\chrome.exe", "%LOCALAPPDATA%\\Chromium\\Application\\chrome.exe", "%PROGRAMFILES%\\ungoogled-chromium\\Application\\chrome.exe" } },
    .{ .kind = .brave, .score_weight = 100, .executable_names = &.{ "brave.exe", "brave-browser.exe", "brave" }, .known_paths = &.{ "%PROGRAMFILES%\\BraveSoftware\\Brave-Browser\\Application\\brave.exe", "%PROGRAMFILES(X86)%\\BraveSoftware\\Brave-Browser\\Application\\brave.exe", "%LOCALAPPDATA%\\BraveSoftware\\Brave-Browser\\Application\\brave.exe" } },
    .{ .kind = .opera, .score_weight = 90, .executable_names = &.{ "launcher.exe", "opera.exe", "opera" }, .known_paths = &.{ "%LOCALAPPDATA%\\Programs\\Opera\\launcher.exe", "%PROGRAMFILES%\\Opera\\launcher.exe", "%PROGRAMFILES(X86)%\\Opera\\launcher.exe" } },
    .{ .kind = .operagx, .score_weight = 90, .executable_names = &.{ "launcher.exe", "opera.exe", "opera-gx" }, .known_paths = &.{ "%LOCALAPPDATA%\\Programs\\Opera GX\\launcher.exe", "%PROGRAMFILES%\\Opera GX\\launcher.exe", "%PROGRAMFILES(X86)%\\Opera GX\\launcher.exe" } },
    .{ .kind = .vivaldi, .score_weight = 95, .executable_names = &.{ "vivaldi.exe", "vivaldi" }, .known_paths = &.{ "%PROGRAMFILES%\\Vivaldi\\Application\\vivaldi.exe", "%PROGRAMFILES(X86)%\\Vivaldi\\Application\\vivaldi.exe", "%LOCALAPPDATA%\\Vivaldi\\Application\\vivaldi.exe" } },
    .{ .kind = .epic, .score_weight = 80, .executable_names = &.{ "epic.exe", "epicbrowser.exe", "epic" }, .known_paths = &.{ "%PROGRAMFILES%\\Epic Privacy Browser\\epic.exe", "%PROGRAMFILES(X86)%\\Epic Privacy Browser\\epic.exe" } },
    .{ .kind = .yandex, .score_weight = 80, .executable_names = &.{ "browser.exe", "yandex.exe", "yandex-browser.exe" }, .known_paths = &.{ "%LOCALAPPDATA%\\Yandex\\YandexBrowser\\Application\\browser.exe", "%PROGRAMFILES%\\Yandex\\YandexBrowser\\Application\\browser.exe" } },
    .{ .kind = .duckduckgo, .score_weight = 75, .executable_names = &.{ "duckduckgo.exe", "duckduckgo-browser.exe", "duckduckgo" }, .known_paths = &.{ "%PROGRAMFILES%\\DuckDuckGo\\DuckDuckGo.exe", "%LOCALAPPDATA%\\DuckDuckGo\\DuckDuckGo.exe", "%LOCALAPPDATA%\\Programs\\DuckDuckGo\\DuckDuckGo.exe" } },
    .{ .kind = .tor, .score_weight = 70, .executable_names = &.{ "firefox.exe", "tor-browser.exe", "torbrowser-launcher.exe" }, .known_paths = &.{ "%PROGRAMFILES%\\Tor Browser\\Browser\\firefox.exe", "%USERPROFILE%\\Desktop\\Tor Browser\\Browser\\firefox.exe" } },
    .{ .kind = .librewolf, .score_weight = 70, .executable_names = &.{ "librewolf.exe", "librewolf" }, .known_paths = &.{ "%PROGRAMFILES%\\LibreWolf\\librewolf.exe", "%PROGRAMFILES(X86)%\\LibreWolf\\librewolf.exe" } },
    .{ .kind = .mullvad, .score_weight = 70, .executable_names = &.{ "firefox.exe", "mullvad-browser.exe", "mullvadbrowser.exe" }, .known_paths = &.{"%PROGRAMFILES%\\Mullvad Browser\\firefox.exe"} },
    .{ .kind = .arc, .score_weight = 65, .executable_names = &.{ "arc.exe", "arc" }, .known_paths = &.{ "%PROGRAMFILES%\\Arc\\Arc.exe", "%LOCALAPPDATA%\\Programs\\Arc\\Arc.exe" } },
    .{ .kind = .sidekick, .score_weight = 65, .executable_names = &.{ "sidekick.exe", "sidekick" }, .known_paths = &.{ "%PROGRAMFILES%\\Sidekick\\sidekick.exe", "%LOCALAPPDATA%\\Programs\\Sidekick\\sidekick.exe" } },
    .{ .kind = .shift, .score_weight = 65, .executable_names = &.{ "shift.exe", "shift" }, .known_paths = &.{ "%PROGRAMFILES%\\Shift\\Shift.exe", "%LOCALAPPDATA%\\Programs\\Shift\\Shift.exe" } },
    .{ .kind = .palemoon, .score_weight = 60, .executable_names = &.{ "palemoon.exe", "palemoon" }, .known_paths = &.{ "%PROGRAMFILES%\\Pale Moon\\palemoon.exe", "%PROGRAMFILES(X86)%\\Pale Moon\\palemoon.exe" } },
    .{ .kind = .sigmaos, .score_weight = 5, .executable_names = &.{}, .known_paths = &.{} },
    .{ .kind = .safari, .score_weight = 5, .executable_names = &.{ "Safari.exe", "safari.exe", "safari" }, .known_paths = &.{ "%PROGRAMFILES%\\Safari\\Safari.exe", "%PROGRAMFILES(X86)%\\Safari\\Safari.exe", "%LOCALAPPDATA%\\Programs\\Safari\\Safari.exe" } },
};

const macos_specs = [_]BrowserSpec{
    .{ .kind = .chrome, .score_weight = 120, .executable_names = &.{ "Google Chrome", "Google Chrome Beta", "Google Chrome Canary" }, .known_paths = &.{ "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta", "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary", "~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" }, .mac_bundle_names = &.{ "Google Chrome", "Google Chrome Beta", "Google Chrome Canary" } },
    .{ .kind = .edge, .score_weight = 120, .executable_names = &.{ "Microsoft Edge", "Microsoft Edge Beta", "Microsoft Edge Dev", "Microsoft Edge Canary" }, .known_paths = &.{ "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge", "/Applications/Microsoft Edge Beta.app/Contents/MacOS/Microsoft Edge Beta", "/Applications/Microsoft Edge Dev.app/Contents/MacOS/Microsoft Edge Dev", "/Applications/Microsoft Edge Canary.app/Contents/MacOS/Microsoft Edge Canary" }, .mac_bundle_names = &.{ "Microsoft Edge", "Microsoft Edge Beta", "Microsoft Edge Dev", "Microsoft Edge Canary" } },
    .{ .kind = .safari, .score_weight = 130, .executable_names = &.{"Safari"}, .known_paths = &.{ "/Applications/Safari.app/Contents/MacOS/Safari", "/System/Applications/Safari.app/Contents/MacOS/Safari" }, .mac_bundle_names = &.{"Safari"} },
    .{ .kind = .firefox, .score_weight = 110, .executable_names = &.{ "firefox", "Firefox" }, .known_paths = &.{ "/Applications/Firefox.app/Contents/MacOS/firefox", "/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox", "/Applications/Firefox Nightly.app/Contents/MacOS/firefox", "~/Applications/Firefox.app/Contents/MacOS/firefox" }, .mac_bundle_names = &.{ "Firefox", "Firefox Developer Edition", "Firefox Nightly" } },
    .{ .kind = .chromium, .score_weight = 100, .executable_names = &.{ "Chromium", "chromium" }, .known_paths = &.{ "/Applications/Chromium.app/Contents/MacOS/Chromium", "/Applications/Ungoogled Chromium.app/Contents/MacOS/Chromium" }, .mac_bundle_names = &.{ "Chromium", "Ungoogled Chromium" } },
    .{ .kind = .brave, .score_weight = 100, .executable_names = &.{"Brave Browser"}, .known_paths = &.{ "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser", "~/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" }, .mac_bundle_names = &.{"Brave Browser"} },
    .{ .kind = .opera, .score_weight = 90, .executable_names = &.{ "Opera", "Opera Developer" }, .known_paths = &.{ "/Applications/Opera.app/Contents/MacOS/Opera", "/Applications/Opera Developer.app/Contents/MacOS/Opera Developer" }, .mac_bundle_names = &.{ "Opera", "Opera Developer" } },
    .{ .kind = .operagx, .score_weight = 90, .executable_names = &.{"Opera GX"}, .known_paths = &.{"/Applications/Opera GX.app/Contents/MacOS/Opera GX"}, .mac_bundle_names = &.{"Opera GX"} },
    .{ .kind = .vivaldi, .score_weight = 95, .executable_names = &.{ "Vivaldi", "Vivaldi Snapshot" }, .known_paths = &.{ "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi", "/Applications/Vivaldi Snapshot.app/Contents/MacOS/Vivaldi Snapshot" }, .mac_bundle_names = &.{ "Vivaldi", "Vivaldi Snapshot" } },
    .{ .kind = .epic, .score_weight = 80, .executable_names = &.{ "Epic", "Epic Privacy Browser" }, .known_paths = &.{ "/Applications/Epic.app/Contents/MacOS/Epic", "/Applications/Epic Privacy Browser.app/Contents/MacOS/Epic Privacy Browser" }, .mac_bundle_names = &.{ "Epic", "Epic Privacy Browser" } },
    .{ .kind = .yandex, .score_weight = 80, .executable_names = &.{ "Yandex", "Yandex Browser" }, .known_paths = &.{ "/Applications/Yandex.app/Contents/MacOS/Yandex", "/Applications/Yandex Browser.app/Contents/MacOS/Yandex Browser" }, .mac_bundle_names = &.{ "Yandex", "Yandex Browser" } },
    .{ .kind = .duckduckgo, .score_weight = 75, .executable_names = &.{"DuckDuckGo"}, .known_paths = &.{"/Applications/DuckDuckGo.app/Contents/MacOS/DuckDuckGo"}, .mac_bundle_names = &.{"DuckDuckGo"} },
    .{ .kind = .tor, .score_weight = 70, .executable_names = &.{ "firefox", "Tor Browser" }, .known_paths = &.{"/Applications/Tor Browser.app/Contents/MacOS/firefox"}, .mac_bundle_names = &.{"Tor Browser"} },
    .{ .kind = .librewolf, .score_weight = 70, .executable_names = &.{ "LibreWolf", "librewolf" }, .known_paths = &.{"/Applications/LibreWolf.app/Contents/MacOS/librewolf"}, .mac_bundle_names = &.{"LibreWolf"} },
    .{ .kind = .mullvad, .score_weight = 70, .executable_names = &.{ "Mullvad Browser", "firefox" }, .known_paths = &.{"/Applications/Mullvad Browser.app/Contents/MacOS/firefox"}, .mac_bundle_names = &.{"Mullvad Browser"} },
    .{ .kind = .arc, .score_weight = 95, .executable_names = &.{"Arc"}, .known_paths = &.{ "/Applications/Arc.app/Contents/MacOS/Arc", "~/Applications/Arc.app/Contents/MacOS/Arc" }, .mac_bundle_names = &.{"Arc"} },
    .{ .kind = .sidekick, .score_weight = 65, .executable_names = &.{"Sidekick"}, .known_paths = &.{"/Applications/Sidekick.app/Contents/MacOS/Sidekick"}, .mac_bundle_names = &.{"Sidekick"} },
    .{ .kind = .shift, .score_weight = 65, .executable_names = &.{"Shift"}, .known_paths = &.{"/Applications/Shift.app/Contents/MacOS/Shift"}, .mac_bundle_names = &.{"Shift"} },
    .{ .kind = .palemoon, .score_weight = 60, .executable_names = &.{ "Pale Moon", "palemoon" }, .known_paths = &.{"/Applications/Pale Moon.app/Contents/MacOS/palemoon"}, .mac_bundle_names = &.{"Pale Moon"} },
    .{ .kind = .sigmaos, .score_weight = 60, .executable_names = &.{"SigmaOS"}, .known_paths = &.{"/Applications/SigmaOS.app/Contents/MacOS/SigmaOS"}, .mac_bundle_names = &.{"SigmaOS"} },
};

const linux_specs = [_]BrowserSpec{
    .{ .kind = .chrome, .score_weight = 120, .executable_names = &.{ "google-chrome-stable", "google-chrome", "chrome", "chrome-browser" }, .known_paths = &.{ "/usr/bin/google-chrome-stable", "/usr/bin/google-chrome", "/opt/google/chrome/chrome" } },
    .{ .kind = .edge, .score_weight = 120, .executable_names = &.{ "microsoft-edge-stable", "microsoft-edge", "microsoft-edge-beta", "microsoft-edge-dev", "msedge" }, .known_paths = &.{ "/usr/bin/microsoft-edge-stable", "/usr/bin/microsoft-edge", "/usr/bin/microsoft-edge-beta", "/usr/bin/microsoft-edge-dev", "/opt/microsoft/msedge/msedge" } },
    .{ .kind = .firefox, .score_weight = 110, .executable_names = &.{ "firefox", "firefox-esr" }, .known_paths = &.{ "/usr/bin/firefox", "/usr/bin/firefox-esr", "/usr/lib/firefox/firefox", "/opt/firefox/firefox", "/snap/bin/firefox" } },
    .{ .kind = .chromium, .score_weight = 100, .executable_names = &.{ "chromium", "chromium-browser", "ungoogled-chromium" }, .known_paths = &.{ "/usr/bin/chromium", "/usr/bin/chromium-browser", "/snap/bin/chromium", "/usr/bin/ungoogled-chromium" } },
    .{ .kind = .brave, .score_weight = 100, .executable_names = &.{ "brave-browser", "brave" }, .known_paths = &.{ "/opt/brave-bin/brave", "/usr/bin/brave-browser", "/opt/brave.com/brave/brave-browser", "/snap/bin/brave" } },
    .{ .kind = .opera, .score_weight = 90, .executable_names = &.{ "opera", "opera-stable" }, .known_paths = &.{ "/usr/bin/opera", "/usr/lib/x86_64-linux-gnu/opera/opera", "/snap/bin/opera" } },
    .{ .kind = .operagx, .score_weight = 90, .executable_names = &.{ "opera-gx", "opera", "opera-stable" }, .known_paths = &.{ "/usr/bin/opera-gx", "/usr/bin/opera", "/snap/bin/opera" } },
    .{ .kind = .vivaldi, .score_weight = 95, .executable_names = &.{ "vivaldi", "vivaldi-stable", "vivaldi-snapshot" }, .known_paths = &.{ "/usr/bin/vivaldi", "/usr/bin/vivaldi-stable", "/opt/vivaldi/vivaldi" } },
    .{ .kind = .epic, .score_weight = 80, .executable_names = &.{ "epic", "epic-browser" }, .known_paths = &.{ "/usr/bin/epic", "/opt/epic/epic" } },
    .{ .kind = .yandex, .score_weight = 80, .executable_names = &.{ "yandex-browser", "browser" }, .known_paths = &.{ "/usr/bin/yandex-browser", "/opt/yandex/browser/yandex-browser" } },
    .{ .kind = .duckduckgo, .score_weight = 75, .executable_names = &.{ "duckduckgo-browser", "duckduckgo" }, .known_paths = &.{"/usr/bin/duckduckgo-browser"} },
    .{ .kind = .tor, .score_weight = 70, .executable_names = &.{ "tor-browser", "torbrowser-launcher" }, .known_paths = &.{ "/usr/bin/tor-browser", "/usr/bin/torbrowser-launcher", "/opt/tor-browser/Browser/firefox" } },
    .{ .kind = .librewolf, .score_weight = 70, .executable_names = &.{ "librewolf", "librewolf-bin" }, .known_paths = &.{ "/usr/bin/librewolf", "/usr/local/bin/librewolf" } },
    .{ .kind = .mullvad, .score_weight = 70, .executable_names = &.{ "mullvad-browser", "mullvadbrowser" }, .known_paths = &.{ "/usr/bin/mullvad-browser", "/opt/mullvad-browser/firefox" } },
    .{ .kind = .arc, .score_weight = 65, .executable_names = &.{ "arc", "arc-browser" }, .known_paths = &.{ "/usr/bin/arc", "/opt/arc/arc" } },
    .{ .kind = .sidekick, .score_weight = 65, .executable_names = &.{ "sidekick", "sidekick-browser" }, .known_paths = &.{ "/usr/bin/sidekick-browser", "/opt/sidekick/sidekick" } },
    .{ .kind = .shift, .score_weight = 65, .executable_names = &.{ "shift", "shift-browser" }, .known_paths = &.{ "/usr/bin/shift-browser", "/opt/shift/shift" } },
    .{ .kind = .palemoon, .score_weight = 60, .executable_names = &.{ "palemoon", "pale-moon" }, .known_paths = &.{ "/usr/bin/palemoon", "/usr/bin/pale-moon" } },
    .{ .kind = .sigmaos, .score_weight = 5, .executable_names = &.{}, .known_paths = &.{} },
    .{ .kind = .safari, .score_weight = 5, .executable_names = &.{"safari"}, .known_paths = &.{} },
};

const windowsSearchDirs = [_][]const u8{
    "%PROGRAMFILES%\\Google\\Chrome\\Application",
    "%PROGRAMFILES(X86)%\\Google\\Chrome\\Application",
    "%LOCALAPPDATA%\\Google\\Chrome\\Application",
    "%PROGRAMFILES%\\Microsoft\\Edge\\Application",
    "%PROGRAMFILES(X86)%\\Microsoft\\Edge\\Application",
    "%LOCALAPPDATA%\\Microsoft\\Edge SxS\\Application",
    "%PROGRAMFILES%\\Mozilla Firefox",
    "%PROGRAMFILES(X86)%\\Mozilla Firefox",
    "%PROGRAMFILES%\\Chromium\\Application",
    "%PROGRAMFILES(X86)%\\Chromium\\Application",
    "%LOCALAPPDATA%\\Chromium\\Application",
    "%PROGRAMFILES%\\Vivaldi\\Application",
    "%PROGRAMFILES(X86)%\\Vivaldi\\Application",
    "%LOCALAPPDATA%\\Vivaldi\\Application",
    "%PROGRAMFILES%\\BraveSoftware\\Brave-Browser\\Application",
    "%PROGRAMFILES(X86)%\\BraveSoftware\\Brave-Browser\\Application",
    "%LOCALAPPDATA%\\BraveSoftware\\Brave-Browser\\Application",
    "%LOCALAPPDATA%\\Programs\\Opera",
    "%LOCALAPPDATA%\\Programs\\Opera GX",
    "%LOCALAPPDATA%\\Programs\\Arc",
    "%LOCALAPPDATA%\\Programs\\Sidekick",
    "%LOCALAPPDATA%\\Programs\\Shift",
    "%LOCALAPPDATA%\\Yandex\\YandexBrowser\\Application",
    "%PROGRAMFILES%\\Pale Moon",
    "%PROGRAMFILES(X86)%\\Pale Moon",
};

const macosSearchDirs = [_][]const u8{
    "/Applications",
    "/System/Applications",
    "~/Applications",
    "/Applications/Setapp",
};

const linuxSearchDirs = [_][]const u8{
    "/usr/bin",
    "/usr/local/bin",
    "/snap/bin",
    "~/.local/bin",
    "/opt/google/chrome",
    "/opt/microsoft/msedge",
    "/opt/microsoft/msedge-beta",
    "/opt/microsoft/msedge-dev",
    "/opt/brave.com/brave",
    "/opt/vivaldi",
    "/opt/firefox",
    "/opt/tor-browser/Browser",
    "/opt/mullvad-browser",
    "/opt/yandex/browser",
    "/opt/arc",
    "/opt/sidekick",
    "/opt/shift",
    "/var/lib/flatpak/exports/bin",
    "~/.local/share/flatpak/exports/bin",
};

const macosAppRoots = [_][]const u8{
    "/Applications",
    "/System/Applications",
    "~/Applications",
    "/Applications/Setapp",
};

test "catalog includes browser_driver and webui browser families" {
    const required = [_]BrowserKind{
        .chrome,
        .edge,
        .safari,
        .firefox,
        .brave,
        .tor,
        .duckduckgo,
        .mullvad,
        .librewolf,
        .epic,
        .arc,
        .vivaldi,
        .sigmaos,
        .sidekick,
        .shift,
        .operagx,
        .palemoon,
        .chromium,
        .opera,
    };

    for (required) |kind| {
        var found = false;
        for (all_browser_kinds) |supported| {
            if (supported == kind) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "required browser matrix coverage is present across all os specs" {
    const required_all_three = [_]BrowserKind{
        .firefox,
        .chrome,
        .edge,
        .chromium,
        .yandex,
        .brave,
        .vivaldi,
    };

    inline for (required_all_three) |kind| {
        const w = findSpecIn(windows_specs[0..], kind) orelse return error.TestUnexpectedResult;
        const m = findSpecIn(macos_specs[0..], kind) orelse return error.TestUnexpectedResult;
        const l = findSpecIn(linux_specs[0..], kind) orelse return error.TestUnexpectedResult;
        try std.testing.expect(w.executable_names.len > 0);
        try std.testing.expect(m.executable_names.len > 0);
        try std.testing.expect(l.executable_names.len > 0);
    }

    const epic_windows = findSpecIn(windows_specs[0..], .epic) orelse return error.TestUnexpectedResult;
    const epic_macos = findSpecIn(macos_specs[0..], .epic) orelse return error.TestUnexpectedResult;
    const epic_linux = findSpecIn(linux_specs[0..], .epic) orelse return error.TestUnexpectedResult;
    try std.testing.expect(epic_windows.executable_names.len > 0);
    try std.testing.expect(epic_macos.executable_names.len > 0);
    try std.testing.expect(epic_linux.executable_names.len > 0);

    const safari_windows = findSpecIn(windows_specs[0..], .safari) orelse return error.TestUnexpectedResult;
    const safari_macos = findSpecIn(macos_specs[0..], .safari) orelse return error.TestUnexpectedResult;
    const safari_linux = findSpecIn(linux_specs[0..], .safari) orelse return error.TestUnexpectedResult;
    try std.testing.expect(safari_windows.executable_names.len > 0);
    try std.testing.expect(safari_macos.executable_names.len > 0);
    try std.testing.expect(safari_linux.executable_names.len > 0);

    const opera_windows = findSpecIn(windows_specs[0..], .opera) orelse return error.TestUnexpectedResult;
    const opera_macos = findSpecIn(macos_specs[0..], .opera) orelse return error.TestUnexpectedResult;
    const opera_linux = findSpecIn(linux_specs[0..], .opera) orelse return error.TestUnexpectedResult;
    try std.testing.expect(opera_windows.executable_names.len > 0);
    try std.testing.expect(opera_macos.executable_names.len > 0);
    try std.testing.expect(opera_linux.executable_names.len > 0);
}

test "linux duckduckgo paths use duckduckgo-browser naming" {
    const spec = findSpec(.duckduckgo) orelse return error.TestUnexpectedResult;
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    try std.testing.expect(spec.known_paths.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, spec.known_paths[0], "duckduckgo-browser") != null);
}

test "linux brave known paths prefer direct binary over wrapper" {
    const spec = findSpec(.brave) orelse return error.TestUnexpectedResult;
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    try std.testing.expect(spec.known_paths.len > 0);
    try std.testing.expectEqualStrings("/opt/brave-bin/brave", spec.known_paths[0]);
}

test "infer kind from common path tokens" {
    try std.testing.expectEqual(BrowserKind.chrome, inferKindFromPath("/opt/google/chrome/chrome"));
    try std.testing.expectEqual(BrowserKind.edge, inferKindFromPath("C:/Program Files/Microsoft/Edge/Application/msedge.exe"));
    try std.testing.expectEqual(BrowserKind.firefox, inferKindFromPath("/usr/bin/firefox"));
    try std.testing.expectEqual(BrowserKind.yandex, inferKindFromPath("/opt/yandex/browser/yandex-browser"));
    try std.testing.expectEqual(BrowserKind.sigmaos, inferKindFromPath("/Applications/SigmaOS.app/Contents/MacOS/SigmaOS"));
}
