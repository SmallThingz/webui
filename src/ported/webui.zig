const std = @import("std");
const builtin = @import("builtin");
const browser_discovery = @import("browser_discovery.zig");
const window_style_types = @import("../window_style.zig");

const linux_webview_host_name = "webui_linux_webview_host";
const linux_browser_host_name = "webui_linux_browser_host";

pub const BrowserLaunch = struct {
    pid: ?i64 = null,
    is_child_process: bool = false,
    lifecycle_linked: bool = false,
    kind: ?browser_discovery.BrowserKind = null,
    used_system_fallback: bool = false,
    profile_dir: ?[]u8 = null,
    profile_ownership: BrowserLaunchProfileOwnership = .none,
};

pub const BrowserLaunchProfileOwnership = enum {
    none,
    ephemeral_owned,
    persistent_user,
};

pub const BrowserPromptPreset = enum {
    quiet_default,
    browser_default,
};

pub const BrowserPromptPolicy = struct {
    preset: BrowserPromptPreset = .quiet_default,
    no_first_run: ?bool = null,
    no_default_browser_check: ?bool = null,
    disable_notifications: ?bool = null,
    disable_save_password_bubble: ?bool = null,
    disable_autofill_keyboard_accessor: ?bool = null,
    disable_infobars: ?bool = null,
    exclude_enable_automation: ?bool = null,
    edge_hide_first_run_experience: ?bool = null,
    brave_make_default_false: ?bool = null,
    brave_disable_product_analytics_prompt: ?bool = null,
};

pub const BrowserSurfaceMode = enum {
    tab,
    app_window,
    native_webview_host,
};

pub const BrowserFallbackMode = enum {
    allow_system,
    strict,
};

pub const ProfilePathSpec = union(enum) {
    default,
    ephemeral,
    custom: []const u8,
};

pub const ProfileRuleTarget = union(enum) {
    webview,
    browser_any,
    browser_kind: browser_discovery.BrowserKind,
};

pub const ProfileRule = struct {
    target: ProfileRuleTarget,
    path: ProfilePathSpec,
};

pub const BrowserLaunchOptions = struct {
    prompt_policy: BrowserPromptPolicy = .{},
    extra_args: []const []const u8 = &.{},
    proxy_server: ?[]const u8 = null,
    surface_mode: BrowserSurfaceMode = .tab,
    fallback_mode: BrowserFallbackMode = .allow_system,
    profile_rules: []const ProfileRule = &.{},
};

pub const browser_default_profile_path: []const u8 = "";

pub const profile_base_prefix_hint: []const u8 = switch (builtin.os.tag) {
    .windows => "%LOCALAPPDATA%\\",
    .macos => "$HOME/Library/Application Support/",
    else => "$XDG_CONFIG_HOME/",
};

pub fn initializeRuntime(enable_tls: bool, enable_log: bool) void {
    _ = enable_tls;
    _ = enable_log;
}

pub fn openInBrowser(
    allocator: std.mem.Allocator,
    url: []const u8,
    style: window_style_types.WindowStyle,
    launch_options: BrowserLaunchOptions,
) !BrowserLaunch {
    const installs = browser_discovery.discoverInstalledBrowsers(allocator) catch &[_]browser_discovery.BrowserInstall{};
    defer if (installs.len > 0) browser_discovery.freeInstalls(allocator, installs);

    if (launch_options.surface_mode == .native_webview_host) {
        if (builtin.os.tag == .linux) {
            if (try launchLinuxNativeWebviewHost(allocator, url, style, launch_options.profile_rules)) |launch| {
                return launch;
            }
        }

        // Best-effort fallback to browser app-window launch.
        for (installs) |install| {
            if (!supportsChromiumAppMode(install.kind)) continue;
            if (try launchBrowserCandidate(allocator, install.kind, install.path, url, style, launch_options)) |launch| {
                return launch;
            }
        }

        if (launch_options.fallback_mode == .strict) return error.AppModeBrowserUnavailable;
    } else if (launch_options.surface_mode == .app_window) {
        for (installs) |install| {
            if (!supportsChromiumAppMode(install.kind)) continue;
            if (try launchBrowserCandidate(allocator, install.kind, install.path, url, style, launch_options)) |launch| {
                return launch;
            }
        }

        if (launch_options.fallback_mode == .strict) return error.AppModeBrowserUnavailable;
    }

    if (needsNativeStyleAwareBrowser(style)) {
        for (installs) |install| {
            if (!supportsRequestedStyleInBrowser(install.kind, style)) continue;
            if (try launchBrowserCandidate(allocator, install.kind, install.path, url, style, launch_options)) |launch| {
                return launch;
            }
        }
    }

    for (installs) |install| {
        if (try launchBrowserCandidate(allocator, install.kind, install.path, url, style, launch_options)) |launch| {
            return launch;
        }
    }

    if (launch_options.fallback_mode == .allow_system) {
        if (try launchSystemFallback(allocator, url)) |launch| return launch;
    }
    return error.BrowserLaunchFailed;
}

pub fn terminateBrowserProcess(allocator: std.mem.Allocator, pid: i64) void {
    if (pid <= 0) return;

    switch (builtin.os.tag) {
        .windows => terminateBrowserProcessWindows(allocator, pid),
        .wasi => {},
        else => terminateBrowserProcessPosix(pid),
    }
}

pub fn cleanupBrowserProfileDir(
    allocator: std.mem.Allocator,
    profile_dir: []const u8,
    ownership: BrowserLaunchProfileOwnership,
) void {
    if (ownership == .ephemeral_owned) {
        std.fs.deleteTreeAbsolute(profile_dir) catch {};
    }
    allocator.free(profile_dir);
}

pub fn isProcessAlive(pid: i64) bool {
    if (pid <= 0) return false;
    return switch (builtin.os.tag) {
        .windows => isProcessAliveWindows(std.heap.page_allocator, pid),
        .wasi => false,
        else => isProcessAlivePosix(pid),
    };
}

pub fn linkedChildExited(pid: i64) bool {
    if (pid <= 0) return true;
    return switch (builtin.os.tag) {
        .windows, .wasi => false,
        else => linkedChildExitedPosix(pid),
    };
}

pub fn controlBrowserWindow(allocator: std.mem.Allocator, pid: i64, cmd: window_style_types.WindowControl) bool {
    if (pid <= 0) return false;

    return switch (builtin.os.tag) {
        .windows => controlBrowserWindowWindows(allocator, pid, cmd),
        .macos => controlBrowserWindowMacos(allocator, pid, cmd),
        .linux => controlBrowserWindowLinux(allocator, pid, cmd),
        else => false,
    };
}

pub fn openUrlInExistingBrowserKind(
    allocator: std.mem.Allocator,
    kind: browser_discovery.BrowserKind,
    url: []const u8,
) bool {
    const installs = browser_discovery.discoverInstalledBrowsers(allocator) catch return false;
    defer if (installs.len > 0) browser_discovery.freeInstalls(allocator, installs);

    for (installs) |install| {
        if (install.kind != kind) continue;

        switch (builtin.os.tag) {
            .windows => {
                // Navigate with direct URL argument to avoid relaunching in app-mode.
                const launch = launchWindowsTracked(allocator, install.path, &.{url}) catch null;
                return launch != null;
            },
            .wasi => return false,
            else => {
                const launch = launchPosixTracked(allocator, install.path, &.{url}) catch null;
                return launch != null;
            },
        }
    }

    return false;
}

const LaunchSpec = struct {
    args: [24][]const u8 = .{""} ** 24,
    len: usize = 0,
    owned_args: [12]?[]u8 = .{null} ** 12,
    owned_len: usize = 0,
    profile_dir: ?[]u8 = null,
    profile_ownership: BrowserLaunchProfileOwnership = .none,

    fn deinit(self: *LaunchSpec, allocator: std.mem.Allocator) void {
        if (self.profile_dir) |dir| allocator.free(dir);
        for (self.owned_args[0..self.owned_len]) |maybe_arg| {
            if (maybe_arg) |arg| allocator.free(arg);
        }
    }

    fn append(self: *LaunchSpec, arg: []const u8) !void {
        if (self.len >= self.args.len) return error.TooManyLaunchArgs;
        self.args[self.len] = arg;
        self.len += 1;
    }

    fn appendOwned(self: *LaunchSpec, allocator: std.mem.Allocator, arg: []const u8) !void {
        if (self.owned_len >= self.owned_args.len) return error.TooManyLaunchArgs;
        const duped = try allocator.dupe(u8, arg);
        self.owned_args[self.owned_len] = duped;
        self.owned_len += 1;
        try self.append(duped);
    }

    fn appendOwnedFmt(self: *LaunchSpec, allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
        if (self.owned_len >= self.owned_args.len) return error.TooManyLaunchArgs;
        const text = try std.fmt.allocPrint(allocator, fmt, args);
        self.owned_args[self.owned_len] = text;
        self.owned_len += 1;
        try self.append(text);
    }
};

fn launchBrowserCandidate(
    allocator: std.mem.Allocator,
    kind: browser_discovery.BrowserKind,
    browser_path: []const u8,
    url: []const u8,
    style: window_style_types.WindowStyle,
    launch_options: BrowserLaunchOptions,
) !?BrowserLaunch {
    var spec = try launchSpecForKind(allocator, kind, url, style, launch_options);
    defer spec.deinit(allocator);

    const launch = switch (builtin.os.tag) {
        .windows => try launchWindowsTracked(allocator, browser_path, spec.args[0..spec.len]),
        .linux => try launchLinuxTracked(allocator, browser_path, spec.args[0..spec.len]),
        .wasi => null,
        else => try launchPosixTracked(allocator, browser_path, spec.args[0..spec.len]),
    };

    if (launch) |result| {
        var tagged = result;
        tagged.kind = kind;
        if (spec.profile_dir) |profile_dir| {
            tagged.profile_dir = try allocator.dupe(u8, profile_dir);
            tagged.profile_ownership = spec.profile_ownership;
        }
        return tagged;
    }
    return null;
}

fn launchSpecForKind(
    allocator: std.mem.Allocator,
    kind: browser_discovery.BrowserKind,
    url: []const u8,
    style: window_style_types.WindowStyle,
    launch_options: BrowserLaunchOptions,
) !LaunchSpec {
    var spec: LaunchSpec = .{};

    if (supportsChromiumAppMode(kind)) {
        try appendPromptPolicyArgs(&spec, kind, launch_options.prompt_policy);

        const app_window_mode = launch_options.surface_mode == .app_window or
            launch_options.surface_mode == .native_webview_host;
        if (app_window_mode) {
            try spec.append("--new-window");
            try spec.appendOwnedFmt(allocator, "--app={s}", .{url});
        } else {
            // Web tab mode: open a normal browser tab/session URL.
            try spec.append(url);
        }

        if (launch_options.proxy_server) |proxy_server| {
            try spec.appendOwnedFmt(allocator, "--proxy-server={s}", .{proxy_server});
        }
        const resolved_profile = try resolveBrowserProfile(allocator, kind, launch_options.profile_rules);
        defer if (resolved_profile.user_data_dir) |path| allocator.free(path);
        if (resolved_profile.user_data_dir) |profile_dir| {
            spec.profile_dir = try allocator.dupe(u8, profile_dir);
            spec.profile_ownership = resolved_profile.ownership;
            try spec.appendOwnedFmt(allocator, "--user-data-dir={s}", .{profile_dir});
        }
        if (app_window_mode) {
            try appendChromiumStyleArgs(allocator, &spec, style);
        }
        for (launch_options.extra_args) |arg| try spec.appendOwned(allocator, arg);
        return spec;
    }

    if (supportsNewWindowFlag(kind)) {
        try spec.append("--new-window");
        try spec.append(url);
        if (style.kiosk) try spec.append("--kiosk");
        for (launch_options.extra_args) |arg| try spec.appendOwned(allocator, arg);
        return spec;
    }

    try spec.append(url);
    for (launch_options.extra_args) |arg| try spec.appendOwned(allocator, arg);
    return spec;
}

fn promptFlagEnabled(policy: BrowserPromptPolicy, value: ?bool, quiet_default: bool) bool {
    if (value) |explicit| return explicit;
    return policy.preset == .quiet_default and quiet_default;
}

fn appendPromptPolicyArgs(spec: *LaunchSpec, kind: browser_discovery.BrowserKind, policy: BrowserPromptPolicy) !void {
    if (!supportsChromiumAppMode(kind)) return;

    if (promptFlagEnabled(policy, policy.no_first_run, true)) {
        try spec.append("--no-first-run");
    }
    if (promptFlagEnabled(policy, policy.no_default_browser_check, true)) {
        try spec.append("--no-default-browser-check");
    }
    if (promptFlagEnabled(policy, policy.disable_notifications, true)) {
        try spec.append("--disable-notifications");
    }
    if (promptFlagEnabled(policy, policy.disable_save_password_bubble, true)) {
        try spec.append("--disable-save-password-bubble");
    }
    if (promptFlagEnabled(policy, policy.disable_autofill_keyboard_accessor, true)) {
        try spec.append("--disable-autofill-keyboard-accessor");
    }
    if (promptFlagEnabled(policy, policy.disable_infobars, true)) {
        try spec.append("--disable-infobars");
    }
    if (promptFlagEnabled(policy, policy.exclude_enable_automation, true)) {
        try spec.append("--excludeSwitches=enable-automation");
    }
    if (kind == .edge and promptFlagEnabled(policy, policy.edge_hide_first_run_experience, true)) {
        try spec.append("--hide-first-run-experience");
    }
    if (kind == .brave and promptFlagEnabled(policy, policy.brave_make_default_false, true)) {
        try spec.append("--brave-utils-make-default=false");
    }
    if (kind == .brave and promptFlagEnabled(policy, policy.brave_disable_product_analytics_prompt, true)) {
        // Best-effort suppression for Brave P3A onboarding overlays in fresh profiles.
        try spec.append("--disable-features=BraveP3A,BraveP3AConstellation,BraveStatsPing");
    }
}

fn appendChromiumStyleArgs(
    allocator: std.mem.Allocator,
    spec: *LaunchSpec,
    style: window_style_types.WindowStyle,
) !void {
    if (style.kiosk) try spec.append("--kiosk");
    if (style.hidden) try spec.append("--start-minimized");
    if (style.transparent) try spec.append("--enable-transparent-visuals");

    if (style.size) |size| {
        try spec.appendOwnedFmt(allocator, "--window-size={d},{d}", .{ size.width, size.height });
    }
    if (style.position) |position| {
        try spec.appendOwnedFmt(allocator, "--window-position={d},{d}", .{ position.x, position.y });
    }
}

fn needsNativeStyleAwareBrowser(style: window_style_types.WindowStyle) bool {
    return style.transparent or
        style.frameless or
        style.corner_radius != null or
        style.position != null or
        style.size != null or
        style.kiosk;
}

pub fn supportsRequestedStyleInBrowser(kind: browser_discovery.BrowserKind, style: window_style_types.WindowStyle) bool {
    const is_chromium = supportsChromiumAppMode(kind);
    if ((style.transparent or style.frameless or style.corner_radius != null or style.position != null or style.size != null) and !is_chromium) {
        return false;
    }
    if (style.kiosk) {
        if (is_chromium) return true;
        if (supportsNewWindowFlag(kind)) return true;
        return switch (kind) {
            .safari => true,
            else => false,
        };
    }
    return true;
}

fn supportsChromiumAppMode(kind: browser_discovery.BrowserKind) bool {
    return switch (kind) {
        .chrome,
        .edge,
        .chromium,
        .opera,
        .brave,
        .vivaldi,
        .epic,
        .yandex,
        .duckduckgo,
        .arc,
        .sidekick,
        .shift,
        .operagx,
        => true,
        else => false,
    };
}

fn supportsNewWindowFlag(kind: browser_discovery.BrowserKind) bool {
    return switch (kind) {
        .firefox,
        .tor,
        .librewolf,
        .mullvad,
        .palemoon,
        => true,
        else => false,
    };
}

fn launchWindowsTracked(allocator: std.mem.Allocator, browser_path: []const u8, args: []const []const u8) !?BrowserLaunch {
    const script = try buildPowershellLaunchScript(allocator, browser_path, args);
    defer allocator.free(script);

    if (try launchWindowsPowershell(allocator, "powershell", script)) |launch| return launch;
    return try launchWindowsPowershell(allocator, "pwsh", script);
}

fn launchWindowsPowershell(allocator: std.mem.Allocator, shell_exe: []const u8, script: []const u8) !?BrowserLaunch {
    const out = runCommandCaptureStdout(allocator, &.{ shell_exe, "-NoProfile", "-NonInteractive", "-Command", script }) catch return null;
    defer allocator.free(out);

    const pid = parsePidFromOutput(out) orelse return null;
    return .{ .pid = pid, .is_child_process = true };
}

fn launchLinuxTracked(allocator: std.mem.Allocator, browser_path: []const u8, args: []const []const u8) !?BrowserLaunch {
    if (try launchLinuxBrowserHost(allocator, browser_path, args)) |launch| return launch;
    return launchPosixTracked(allocator, browser_path, args);
}

fn launchPosixTracked(allocator: std.mem.Allocator, browser_path: []const u8, args: []const []const u8) !?BrowserLaunch {
    var argv = std.array_list.Managed([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append(browser_path);
    if (args.len > 0) try argv.appendSlice(args);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return null;
    return .{ .pid = @as(i64, @intCast(child.id)), .is_child_process = true };
}

fn launchLinuxBrowserHost(
    allocator: std.mem.Allocator,
    browser_path: []const u8,
    args: []const []const u8,
) !?BrowserLaunch {
    if (builtin.os.tag != .linux) return null;

    const exe_dir = std.fs.selfExeDirPathAlloc(allocator) catch return null;
    defer allocator.free(exe_dir);

    const helper_path = std.fs.path.join(allocator, &.{ exe_dir, linux_browser_host_name }) catch return null;
    defer allocator.free(helper_path);

    std.fs.cwd().access(helper_path, .{}) catch return null;

    const parent_pid_arg = try std.fmt.allocPrint(allocator, "{d}", .{std.os.linux.getpid()});
    defer allocator.free(parent_pid_arg);

    var argv = std.array_list.Managed([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append(helper_path);
    try argv.append(parent_pid_arg);
    try argv.append(browser_path);
    if (args.len > 0) try argv.appendSlice(args);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    child.pgid = 0;

    child.spawn() catch return null;
    defer if (child.stdout) |*stdout_file| {
        stdout_file.close();
        child.stdout = null;
    };

    const line = if (child.stdout) |*stdout_file|
        try stdout_file.readToEndAlloc(allocator, 128)
    else
        return null;
    defer allocator.free(line);

    const pid = parsePidFromOutput(line) orelse return null;
    return .{ .pid = pid, .is_child_process = true };
}

fn launchSystemFallback(allocator: std.mem.Allocator, url: []const u8) !?BrowserLaunch {
    return switch (builtin.os.tag) {
        .windows => if (try runCommandNoCapture(allocator, &.{ "cmd", "/C", "start", "", url })) BrowserLaunch{ .used_system_fallback = true } else null,
        .macos => if (try runCommandNoCapture(allocator, &.{ "open", url })) BrowserLaunch{ .used_system_fallback = true } else null,
        else => blk: {
            if (try runCommandNoCapture(allocator, &.{ "xdg-open", url })) break :blk BrowserLaunch{ .used_system_fallback = true };
            if (try runCommandNoCapture(allocator, &.{ "gio", "open", url })) break :blk BrowserLaunch{ .used_system_fallback = true };
            if (try runCommandNoCapture(allocator, &.{ "sensible-browser", url })) break :blk BrowserLaunch{ .used_system_fallback = true };
            if (try runCommandNoCapture(allocator, &.{ "x-www-browser", url })) break :blk BrowserLaunch{ .used_system_fallback = true };
            break :blk null;
        },
    };
}

fn launchLinuxNativeWebviewHost(
    allocator: std.mem.Allocator,
    url: []const u8,
    style: window_style_types.WindowStyle,
    profile_rules: []const ProfileRule,
) !?BrowserLaunch {
    if (builtin.os.tag != .linux) return null;

    const exe_dir = std.fs.selfExeDirPathAlloc(allocator) catch return null;
    defer allocator.free(exe_dir);

    const helper_path = std.fs.path.join(allocator, &.{ exe_dir, linux_webview_host_name }) catch return null;
    defer allocator.free(helper_path);

    std.fs.cwd().access(helper_path, .{}) catch return null;

    const width: u32 = if (style.size) |size| size.width else 980;
    const height: u32 = if (style.size) |size| size.height else 660;
    const width_arg = try std.fmt.allocPrint(allocator, "{d}", .{width});
    defer allocator.free(width_arg);
    const height_arg = try std.fmt.allocPrint(allocator, "{d}", .{height});
    defer allocator.free(height_arg);
    const frameless_arg: []const u8 = if (style.frameless) "1" else "0";
    const transparent_arg: []const u8 = if (style.transparent) "1" else "0";
    const corner_radius: u16 = style.corner_radius orelse 0;
    const corner_radius_arg = try std.fmt.allocPrint(allocator, "{d}", .{corner_radius});
    defer allocator.free(corner_radius_arg);
    const resizable_arg: []const u8 = if (style.resizable) "1" else "0";
    const center_arg: []const u8 = if (style.center or style.position == null) "1" else "0";
    const pos_x: i32 = if (style.position) |p| p.x else 0;
    const pos_y: i32 = if (style.position) |p| p.y else 0;
    const pos_x_arg = try std.fmt.allocPrint(allocator, "{d}", .{pos_x});
    defer allocator.free(pos_x_arg);
    const pos_y_arg = try std.fmt.allocPrint(allocator, "{d}", .{pos_y});
    defer allocator.free(pos_y_arg);

    const resolved_profile = try resolveWebviewProfile(allocator, profile_rules);
    defer if (resolved_profile.user_data_dir) |path| allocator.free(path);
    const profile_arg = if (resolved_profile.user_data_dir) |path| path else "";

    var child = std.process.Child.init(&.{
        helper_path,
        url,
        width_arg,
        height_arg,
        frameless_arg,
        transparent_arg,
        corner_radius_arg,
        resizable_arg,
        center_arg,
        pos_x_arg,
        pos_y_arg,
        profile_arg,
    }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return null;
    var launch: BrowserLaunch = .{
        .pid = @as(i64, @intCast(child.id)),
        .is_child_process = true,
        .lifecycle_linked = true,
        .kind = null,
        .used_system_fallback = false,
        .profile_dir = null,
        .profile_ownership = .none,
    };
    if (resolved_profile.user_data_dir) |path| {
        launch.profile_dir = try allocator.dupe(u8, path);
        launch.profile_ownership = resolved_profile.ownership;
    }
    return launch;
}

const ProfileResolutionTarget = union(enum) {
    webview,
    browser_kind: browser_discovery.BrowserKind,
};

const ResolvedProfile = struct {
    user_data_dir: ?[]u8 = null,
    ownership: BrowserLaunchProfileOwnership = .none,
};

pub fn resolveProfileBasePrefix(allocator: std.mem.Allocator) ![]u8 {
    const base = switch (builtin.os.tag) {
        .windows => std.process.getEnvVarOwned(allocator, "LOCALAPPDATA") catch
            std.process.getEnvVarOwned(allocator, "APPDATA") catch
            try allocator.dupe(u8, "C:\\"),
        .macos => blk: {
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch try allocator.dupe(u8, "/tmp");
            defer allocator.free(home);
            break :blk try std.fs.path.join(allocator, &.{ home, "Library", "Application Support" });
        },
        else => std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch blk: {
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch try allocator.dupe(u8, "/tmp");
            defer allocator.free(home);
            break :blk try std.fs.path.join(allocator, &.{ home, ".config" });
        },
    };
    defer allocator.free(base);
    return ensureTrailingSeparatorOwned(allocator, base);
}

pub fn defaultWebviewProfilePath(allocator: std.mem.Allocator) ![]u8 {
    const prefix = try resolveProfileBasePrefix(allocator);
    defer allocator.free(prefix);
    const prefix_trimmed = trimTrailingPathSeparators(prefix);
    if (prefix_trimmed.len == 0) return allocator.dupe(u8, "webui");
    return std.fs.path.join(allocator, &.{ prefix_trimmed, "webui" });
}

fn maybeCreateIsolatedProfileDir(allocator: std.mem.Allocator) !?[]u8 {
    const temp_base = switch (builtin.os.tag) {
        .windows => std.process.getEnvVarOwned(allocator, "TEMP") catch
            std.process.getEnvVarOwned(allocator, "TMP") catch
            try allocator.dupe(u8, "C:\\Temp"),
        else => std.process.getEnvVarOwned(allocator, "TMPDIR") catch try allocator.dupe(u8, "/tmp"),
    };
    defer allocator.free(temp_base);

    const stamp: u64 = @intCast(@abs(std.time.nanoTimestamp()));

    var attempt: u8 = 0;
    while (attempt < 8) : (attempt += 1) {
        const dir = try std.fmt.allocPrint(allocator, "{s}{c}webui-profile-{d}-{d}", .{
            trimTrailingPathSeparators(temp_base),
            std.fs.path.sep,
            stamp,
            attempt,
        });
        std.fs.makeDirAbsolute(dir) catch |err| {
            if (err == error.PathAlreadyExists) {
                allocator.free(dir);
                continue;
            }
            allocator.free(dir);
            return err;
        };
        return dir;
    }

    return null;
}

fn ensureProfileDirExists(path: []const u8) !bool {
    if (path.len == 0) return false;
    if (std.fs.path.isAbsolute(path)) {
        std.fs.makeDirAbsolute(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return false,
        };
        return true;
    }
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return false,
    };
    return true;
}

fn resolveBrowserProfile(
    allocator: std.mem.Allocator,
    kind: browser_discovery.BrowserKind,
    rules: []const ProfileRule,
) !ResolvedProfile {
    const selected = resolveProfileRule(rules, .{ .browser_kind = kind }) orelse ProfilePathSpec.default;
    return resolveProfilePathSpec(allocator, selected, .{ .browser_kind = kind });
}

fn resolveWebviewProfile(
    allocator: std.mem.Allocator,
    rules: []const ProfileRule,
) !ResolvedProfile {
    const selected = resolveProfileRule(rules, .webview) orelse ProfilePathSpec.default;
    return resolveProfilePathSpec(allocator, selected, .webview);
}

fn resolveProfileRule(rules: []const ProfileRule, target: ProfileResolutionTarget) ?ProfilePathSpec {
    for (rules) |rule| {
        if (!profileRuleMatches(rule.target, target)) continue;
        return rule.path;
    }
    return null;
}

fn profileRuleMatches(rule_target: ProfileRuleTarget, target: ProfileResolutionTarget) bool {
    return switch (target) {
        .webview => switch (rule_target) {
            .webview => true,
            .browser_any, .browser_kind => false,
        },
        .browser_kind => |kind| switch (rule_target) {
            .browser_any => true,
            .browser_kind => |rule_kind| rule_kind == kind,
            .webview => false,
        },
    };
}

fn resolveProfilePathSpec(
    allocator: std.mem.Allocator,
    spec: ProfilePathSpec,
    target: ProfileResolutionTarget,
) !ResolvedProfile {
    return switch (spec) {
        .default => switch (target) {
            .webview => blk: {
                const webview_default = try defaultWebviewProfilePath(allocator);
                if (!try ensureProfileDirExists(webview_default)) {
                    allocator.free(webview_default);
                    break :blk .{};
                }
                break :blk .{
                    .user_data_dir = webview_default,
                    .ownership = .persistent_user,
                };
            },
            .browser_kind => .{},
        },
        .ephemeral => switch (target) {
            .webview => blk: {
                const dir = (try maybeCreateIsolatedProfileDir(allocator)) orelse break :blk .{};
                break :blk .{
                    .user_data_dir = dir,
                    .ownership = .ephemeral_owned,
                };
            },
            .browser_kind => |kind| blk: {
                const base = (try maybeCreateIsolatedProfileDir(allocator)) orelse break :blk .{};
                defer allocator.free(base);
                const suffixed = try ensureBrowserKindProfileSuffix(allocator, base, kind);
                if (!try ensureProfileDirExists(suffixed)) {
                    allocator.free(suffixed);
                    break :blk .{};
                }
                break :blk .{
                    .user_data_dir = suffixed,
                    .ownership = .ephemeral_owned,
                };
            },
        },
        .custom => |configured| switch (target) {
            .webview => blk: {
                const path = if (configured.len == 0)
                    try defaultWebviewProfilePath(allocator)
                else
                    try allocator.dupe(u8, configured);
                if (!try ensureProfileDirExists(path)) {
                    allocator.free(path);
                    break :blk .{};
                }
                break :blk .{
                    .user_data_dir = path,
                    .ownership = .persistent_user,
                };
            },
            .browser_kind => |kind| blk: {
                if (configured.len == 0) break :blk .{};
                const suffixed = try ensureBrowserKindProfileSuffix(allocator, configured, kind);
                if (!try ensureProfileDirExists(suffixed)) {
                    allocator.free(suffixed);
                    break :blk .{};
                }
                break :blk .{
                    .user_data_dir = suffixed,
                    .ownership = .persistent_user,
                };
            },
        },
    };
}

fn ensureBrowserKindProfileSuffix(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    kind: browser_discovery.BrowserKind,
) ![]u8 {
    const suffix = @tagName(kind);
    const trimmed = trimTrailingPathSeparators(base_path);
    if (trimmed.len == 0) return allocator.dupe(u8, suffix);

    const leaf = std.fs.path.basename(trimmed);
    if (std.ascii.eqlIgnoreCase(leaf, suffix)) {
        return allocator.dupe(u8, trimmed);
    }
    return std.fs.path.join(allocator, &.{ trimmed, suffix });
}

fn trimTrailingPathSeparators(path: []const u8) []const u8 {
    return std.mem.trimRight(u8, path, "/\\");
}

fn ensureTrailingSeparatorOwned(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, "");
    if (path[path.len - 1] == '/' or path[path.len - 1] == '\\') {
        return allocator.dupe(u8, path);
    }
    return std.fmt.allocPrint(allocator, "{s}{c}", .{ path, std.fs.path.sep });
}

fn runCommandCaptureStdout(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    defer {
        _ = child.wait() catch {};
    }

    const out = if (child.stdout) |*stdout_file|
        try stdout_file.readToEndAlloc(allocator, 32 * 1024)
    else
        try allocator.dupe(u8, "");
    return out;
}

fn runCommandNoCapture(allocator: std.mem.Allocator, argv: []const []const u8) !bool {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = child.spawnAndWait() catch return false;
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn controlBrowserWindowWindows(allocator: std.mem.Allocator, pid: i64, cmd: window_style_types.WindowControl) bool {
    if (cmd == .close) {
        terminateBrowserProcessWindows(allocator, pid);
        return true;
    }

    const show_code = windowsShowWindowCode(cmd) orelse return false;
    const script = std.fmt.allocPrint(
        allocator,
        "$ErrorActionPreference='Stop';" ++
            "Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class WebuiUser32{{[DllImport(\"user32.dll\")] public static extern bool ShowWindowAsync(IntPtr hWnd,int nCmdShow);}}' -ErrorAction SilentlyContinue | Out-Null;" ++
            "$p=Get-Process -Id {d} -ErrorAction Stop;" ++
            "if($p.MainWindowHandle -eq 0){{exit 2}};" ++
            "[WebuiUser32]::ShowWindowAsync($p.MainWindowHandle,{d}) | Out-Null;" ++
            "exit 0;",
        .{ pid, show_code },
    ) catch return false;
    defer allocator.free(script);

    if (runCommandNoCapture(allocator, &.{ "powershell", "-NoProfile", "-NonInteractive", "-Command", script }) catch false) return true;
    return runCommandNoCapture(allocator, &.{ "pwsh", "-NoProfile", "-NonInteractive", "-Command", script }) catch false;
}

fn windowsShowWindowCode(cmd: window_style_types.WindowControl) ?i32 {
    return switch (cmd) {
        .hide => 0, // SW_HIDE
        .show => 5, // SW_SHOW
        .maximize => 3, // SW_MAXIMIZE
        .minimize => 6, // SW_MINIMIZE
        .restore => 9, // SW_RESTORE
        .close => null,
    };
}

fn controlBrowserWindowMacos(allocator: std.mem.Allocator, pid: i64, cmd: window_style_types.WindowControl) bool {
    if (cmd == .close) {
        terminateBrowserProcessPosix(pid);
        return true;
    }

    const script = switch (cmd) {
        .hide => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first process whose unix id is {d}) to set visible to false",
            .{pid},
        ) catch return false,
        .show => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first process whose unix id is {d}) to set visible to true",
            .{pid},
        ) catch return false,
        .minimize => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXMinimized\" to true",
            .{pid},
        ) catch return false,
        .restore => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXMinimized\" to false",
            .{pid},
        ) catch return false,
        .maximize => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXFullScreen\" to true",
            .{pid},
        ) catch return false,
        .close => unreachable,
    };
    defer allocator.free(script);

    if (runCommandNoCapture(allocator, &.{ "osascript", "-e", script }) catch false) return true;
    if (cmd == .maximize) {
        const alt = std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXZoomed\" to true",
            .{pid},
        ) catch return false;
        defer allocator.free(alt);
        return runCommandNoCapture(allocator, &.{ "osascript", "-e", alt }) catch false;
    }
    return false;
}

fn controlBrowserWindowLinux(allocator: std.mem.Allocator, pid: i64, cmd: window_style_types.WindowControl) bool {
    if (cmd == .close) {
        terminateBrowserProcessPosix(pid);
        return true;
    }

    const win_id = firstLinuxWindowIdForPid(allocator, pid) orelse return false;
    const win_id_hex = std.fmt.allocPrint(allocator, "0x{x}", .{win_id}) catch return false;
    defer allocator.free(win_id_hex);

    return switch (cmd) {
        .minimize => (runCommandNoCapture(allocator, &.{ "xdotool", "windowminimize", win_id_hex }) catch false) or
            (runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "add,hidden" }) catch false),
        .maximize => runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "add,maximized_vert,maximized_horz" }) catch false,
        .restore => runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "remove,maximized_vert,maximized_horz" }) catch false,
        .hide => runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "add,hidden" }) catch false,
        .show => (runCommandNoCapture(allocator, &.{ "wmctrl", "-ia", win_id_hex }) catch false) or
            (runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "remove,hidden" }) catch false),
        .close => unreachable,
    };
}

fn firstLinuxWindowIdForPid(allocator: std.mem.Allocator, pid: i64) ?u64 {
    const pid_txt = std.fmt.allocPrint(allocator, "{d}", .{pid}) catch return null;
    defer allocator.free(pid_txt);

    const output = runCommandCaptureStdout(allocator, &.{ "xdotool", "search", "--pid", pid_txt }) catch return null;
    defer allocator.free(output);

    var it = std.mem.splitScalar(u8, output, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        if (std.fmt.parseInt(u64, line, 10)) |id| return id else |_| {}
    }
    return null;
}

fn parsePidFromOutput(output: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(i64, trimmed, 10) catch null;
}

fn buildPowershellLaunchScript(
    allocator: std.mem.Allocator,
    browser_path: []const u8,
    args: []const []const u8,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    const w = out.writer();
    try w.writeAll("$ErrorActionPreference='Stop';$p=Start-Process -FilePath '");
    try appendPowershellSingleQuoted(allocator, &out, browser_path);
    try w.writeAll("' -ArgumentList @(");

    for (args, 0..) |arg, i| {
        if (i != 0) try w.writeAll(",");
        try w.writeAll("'");
        try appendPowershellSingleQuoted(allocator, &out, arg);
        try w.writeAll("'");
    }

    try w.writeAll(") -PassThru -WindowStyle Hidden;[Console]::Out.Write($p.Id)");
    return out.toOwnedSlice();
}

fn appendPowershellSingleQuoted(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    value: []const u8,
) !void {
    _ = allocator;
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice("''");
        } else {
            try out.append(ch);
        }
    }
}

fn terminateBrowserProcessPosix(pid_value: i64) void {
    const pid: std.posix.pid_t = @intCast(pid_value);
    std.posix.kill(pid, std.posix.SIG.TERM) catch {};
    std.posix.kill(pid, std.posix.SIG.KILL) catch {};
}

fn isProcessAlivePosix(pid_value: i64) bool {
    const pid: std.posix.pid_t = @intCast(pid_value);
    std.posix.kill(pid, 0) catch |err| {
        return switch (err) {
            error.PermissionDenied => true,
            else => false,
        };
    };

    if (builtin.os.tag == .linux and isZombieProcessLinux(pid)) return false;
    return true;
}

fn isZombieProcessLinux(pid: std.posix.pid_t) bool {
    if (builtin.os.tag != .linux) return false;

    var path_buf: [64]u8 = undefined;
    const stat_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid}) catch return false;

    var stat_file = std.fs.openFileAbsolute(stat_path, .{}) catch return false;
    defer stat_file.close();

    var stat_buf: [1024]u8 = undefined;
    const stat_len = stat_file.readAll(&stat_buf) catch return false;
    const stat = stat_buf[0..stat_len];

    const close_paren = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return false;
    if (close_paren + 2 >= stat.len) return false;
    return stat[close_paren + 2] == 'Z';
}

fn linkedChildExitedPosix(pid_value: i64) bool {
    const pid: std.posix.pid_t = @intCast(pid_value);
    const result = std.posix.waitpid(pid, std.posix.W.NOHANG);
    return result.pid == pid;
}

fn isProcessAliveWindows(allocator: std.mem.Allocator, pid_value: i64) bool {
    const pid_text = std.fmt.allocPrint(allocator, "{d}", .{pid_value}) catch return false;
    defer allocator.free(pid_text);
    const filter = std.fmt.allocPrint(allocator, "PID eq {s}", .{pid_text}) catch return false;
    defer allocator.free(filter);
    const out = runCommandCaptureStdout(allocator, &.{ "tasklist", "/FI", filter, "/FO", "CSV", "/NH" }) catch return false;
    defer allocator.free(out);

    if (std.mem.indexOf(u8, out, "No tasks are running") != null) return false;
    return std.mem.indexOf(u8, out, pid_text) != null;
}

fn terminateBrowserProcessWindows(allocator: std.mem.Allocator, pid_value: i64) void {
    const pid_text = std.fmt.allocPrint(allocator, "{d}", .{pid_value}) catch return;
    defer allocator.free(pid_text);

    _ = runCommandNoCapture(allocator, &.{ "taskkill", "/PID", pid_text, "/T", "/F" }) catch {};
}

test "parse pid from output" {
    try std.testing.expectEqual(@as(?i64, 1234), parsePidFromOutput("1234\n"));
    try std.testing.expectEqual(@as(?i64, 987), parsePidFromOutput("  987  \r\n"));
    try std.testing.expectEqual(@as(?i64, null), parsePidFromOutput(""));
    try std.testing.expectEqual(@as(?i64, null), parsePidFromOutput("not-a-pid"));
}

test "windows show window command mapping is stable" {
    try std.testing.expectEqual(@as(?i32, 0), windowsShowWindowCode(.hide));
    try std.testing.expectEqual(@as(?i32, 5), windowsShowWindowCode(.show));
    try std.testing.expectEqual(@as(?i32, 6), windowsShowWindowCode(.minimize));
    try std.testing.expectEqual(@as(?i32, 3), windowsShowWindowCode(.maximize));
    try std.testing.expectEqual(@as(?i32, 9), windowsShowWindowCode(.restore));
    try std.testing.expectEqual(@as(?i32, null), windowsShowWindowCode(.close));
}

test "quiet prompt policy injects suppression flags for chromium family" {
    var spec = try launchSpecForKind(std.testing.allocator, .chrome, "http://127.0.0.1:3030/", .{}, .{
        .prompt_policy = .{ .preset = .quiet_default },
    });
    defer spec.deinit(std.testing.allocator);

    try std.testing.expect(containsArg(spec.args[0..spec.len], "--no-first-run"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--no-default-browser-check"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--disable-notifications"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--disable-save-password-bubble"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--disable-autofill-keyboard-accessor"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--disable-infobars"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--excludeSwitches=enable-automation"));
}

test "edge and brave receive browser-specific quiet flags" {
    var edge_spec = try launchSpecForKind(std.testing.allocator, .edge, "http://127.0.0.1:3031/", .{}, .{
        .prompt_policy = .{ .preset = .quiet_default },
    });
    defer edge_spec.deinit(std.testing.allocator);

    var brave_spec = try launchSpecForKind(std.testing.allocator, .brave, "http://127.0.0.1:3032/", .{}, .{
        .prompt_policy = .{ .preset = .quiet_default },
    });
    defer brave_spec.deinit(std.testing.allocator);

    try std.testing.expect(containsArg(edge_spec.args[0..edge_spec.len], "--hide-first-run-experience"));
    try std.testing.expect(containsArg(brave_spec.args[0..brave_spec.len], "--brave-utils-make-default=false"));
    try std.testing.expect(containsArg(brave_spec.args[0..brave_spec.len], "--disable-features=BraveP3A,BraveP3AConstellation,BraveStatsPing"));
}

test "chromium isolated launch adds dedicated user-data-dir argument" {
    const rules = [_]ProfileRule{
        .{ .target = .browser_any, .path = .ephemeral },
    };
    var spec = try launchSpecForKind(std.testing.allocator, .chrome, "http://127.0.0.1:3035/", .{}, .{
        .profile_rules = rules[0..],
    });
    defer spec.deinit(std.testing.allocator);

    try std.testing.expect(spec.profile_dir != null);
    const profile_dir = spec.profile_dir.?;
    const expected_arg = try std.fmt.allocPrint(std.testing.allocator, "--user-data-dir={s}", .{profile_dir});
    defer std.testing.allocator.free(expected_arg);
    try std.testing.expect(containsArg(spec.args[0..spec.len], expected_arg));

    var dir = try std.fs.openDirAbsolute(profile_dir, .{});
    dir.close();
}

test "chromium default launch uses browser default profile" {
    const url = "http://127.0.0.1:3036/";
    const rules = [_]ProfileRule{
        .{ .target = .browser_any, .path = .default },
    };
    var spec = try launchSpecForKind(std.testing.allocator, .chrome, url, .{}, .{
        .profile_rules = rules[0..],
    });
    defer spec.deinit(std.testing.allocator);

    try std.testing.expect(!containsArgWithPrefix(spec.args[0..spec.len], "--user-data-dir="));
    try std.testing.expect(spec.profile_dir == null);
}

test "browser default preset disables quiet flags unless explicitly re-enabled" {
    var base_spec = try launchSpecForKind(std.testing.allocator, .chrome, "http://127.0.0.1:3033/", .{}, .{
        .prompt_policy = .{ .preset = .browser_default },
    });
    defer base_spec.deinit(std.testing.allocator);

    try std.testing.expect(!containsArg(base_spec.args[0..base_spec.len], "--no-first-run"));
    try std.testing.expect(!containsArg(base_spec.args[0..base_spec.len], "--disable-notifications"));

    var override_spec = try launchSpecForKind(std.testing.allocator, .chrome, "http://127.0.0.1:3034/", .{}, .{
        .prompt_policy = .{
            .preset = .browser_default,
            .no_first_run = true,
        },
    });
    defer override_spec.deinit(std.testing.allocator);

    try std.testing.expect(containsArg(override_spec.args[0..override_spec.len], "--no-first-run"));
}

test "proxy server launch option maps to chromium proxy flag" {
    var spec = try launchSpecForKind(std.testing.allocator, .chrome, "http://127.0.0.1:3040/", .{}, .{
        .proxy_server = "http://127.0.0.1:8080",
    });
    defer spec.deinit(std.testing.allocator);

    try std.testing.expect(containsArg(spec.args[0..spec.len], "--proxy-server=http://127.0.0.1:8080"));
}

test "chromium launch uses tab mode when app mode is not required" {
    const url = "http://127.0.0.1:3041/";
    var spec = try launchSpecForKind(std.testing.allocator, .chrome, url, .{
        .frameless = true,
        .transparent = true,
    }, .{
        .surface_mode = .tab,
    });
    defer spec.deinit(std.testing.allocator);

    try std.testing.expect(containsArg(spec.args[0..spec.len], url));
    try std.testing.expect(!containsArgWithPrefix(spec.args[0..spec.len], "--app="));
    try std.testing.expect(!containsArg(spec.args[0..spec.len], "--new-window"));
}

test "chromium launch keeps app mode arguments when required" {
    var spec = try launchSpecForKind(std.testing.allocator, .chrome, "http://127.0.0.1:3042/", .{
        .size = .{ .width = 900, .height = 700 },
    }, .{
        .surface_mode = .app_window,
    });
    defer spec.deinit(std.testing.allocator);

    try std.testing.expect(containsArgWithPrefix(spec.args[0..spec.len], "--app=http://127.0.0.1:3042/"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--new-window"));
    try std.testing.expect(containsArg(spec.args[0..spec.len], "--window-size=900,700"));
}

test "profile rule resolution uses first matching browser rule" {
    const rules = [_]ProfileRule{
        .{ .target = .browser_any, .path = .{ .custom = "any-first" } },
        .{ .target = .{ .browser_kind = .chrome }, .path = .{ .custom = "chrome-second" } },
    };
    const picked = resolveProfileRule(rules[0..], .{ .browser_kind = .chrome }) orelse return error.TestUnexpectedResult;
    switch (picked) {
        .custom => |value| try std.testing.expectEqualStrings("any-first", value),
        else => return error.TestUnexpectedResult,
    }
}

test "profile rule resolution keeps webview matching separate from browser_any" {
    const rules = [_]ProfileRule{
        .{ .target = .browser_any, .path = .{ .custom = "browser" } },
        .{ .target = .webview, .path = .{ .custom = "webview" } },
    };
    const picked = resolveProfileRule(rules[0..], .webview) orelse return error.TestUnexpectedResult;
    switch (picked) {
        .custom => |value| try std.testing.expectEqualStrings("webview", value),
        else => return error.TestUnexpectedResult,
    }
}

test "browser custom empty path keeps browser default profile semantics" {
    const resolved = try resolveProfilePathSpec(
        std.testing.allocator,
        .{ .custom = browser_default_profile_path },
        .{ .browser_kind = .chrome },
    );
    try std.testing.expectEqual(@as(?[]u8, null), resolved.user_data_dir);
    try std.testing.expectEqual(@as(BrowserLaunchProfileOwnership, .none), resolved.ownership);
}

fn containsArg(args: []const []const u8, needle: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, needle)) return true;
    }
    return false;
}

fn containsArgWithPrefix(args: []const []const u8, prefix: []const u8) bool {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, prefix)) return true;
    }
    return false;
}
