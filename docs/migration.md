# Migration Guide: Launch Order + Async RPC Jobs

This guide covers the hard API replacement in `AppOptions` and the new async RPC job APIs.

## AppOptions Launch Fields (Hard Replace)

Removed fields:
- `transport_mode`
- `auto_open_browser`
- `browser_fallback_on_native_failure`

Replacement:
- `launch_policy: LaunchPolicy`

```zig
pub const LaunchSurface = enum {
    native_webview,
    browser_window,
    web_url,
};

pub const LaunchPolicy = struct {
    first: LaunchSurface = .native_webview,
    second: ?LaunchSurface = .browser_window,
    third: ?LaunchSurface = .web_url,
    allow_dual_surface: bool = false,
    app_mode_required: bool = true,
};
```

## Service Signals + App Logging (New)

New `ServiceOptions` field:
- `process_signals: bool = true`

When `true`, `Service.init(...)` installs and checks signal handlers automatically in `shouldExit()`.
Set `process_signals = false` if your host runtime owns signal handling.

New `AppOptions` field:
- `log_sink: webui.LogSink = .{}`

All runtime `[webui.*]` logs route through this sink when `enable_webui_log=true`.  
Use `webui.logSink(MyLogger.sink, ctx)` to pass a comptime function object.

## Browser/Profile Launch Options (Hard Replace)

Removed `BrowserLaunchOptions` fields:
- `force_isolated_chromium_instance`
- `isolated_profile_global`
- `isolated_profile_dir`
- `native_webview_global_profile`
- `prefer_native_webview_host`
- `require_app_mode_window`
- `allow_system_fallback`

Replacement:
- `surface_mode: BrowserSurfaceMode`
- `fallback_mode: BrowserFallbackMode`
- `profile_rules: []const ProfileRule`

```zig
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
    browser_kind: BrowserKind,
};

pub const ProfileRule = struct {
    target: ProfileRuleTarget,
    path: ProfilePathSpec,
};
```

Rule behavior:
- First matching rule wins.
- Browser default profile uses empty-string semantics (`webui.browser_default_profile_path`).
- Browser `custom: ""` means default browser profile (no `--user-data-dir`).
- Webview `default` resolves to OS-standard app config path.

Example:

```zig
const rules = [_]webui.ProfileRule{
    .{ .target = .webview, .path = .default },
    .{ .target = .browser_any, .path = .{ .custom = webui.browser_default_profile_path } },
};

.app = .{
    .launch_policy = webui.LaunchPolicy.webviewFirst(),
    .browser_launch = .{
        .surface_mode = .native_webview_host,
        .fallback_mode = .allow_system,
        .profile_rules = rules[0..],
    },
}
```

## Old -> New Mapping

### Native-first with browser fallback

Before:

```zig
.app = .{
    .transport_mode = .native_webview,
    .browser_fallback_on_native_failure = true,
    .auto_open_browser = true,
}
```

After:

```zig
.app = .{
    .launch_policy = .{
        .first = .native_webview,
        .second = .browser_window,
        .third = .web_url,
    },
}
```

### Browser-only mode

Before:

```zig
.app = .{
    .transport_mode = .browser_fallback,
    .auto_open_browser = true,
}
```

After:

```zig
.app = .{
    .launch_policy = .{
        .first = .browser_window,
        .second = null,
        .third = null,
        .app_mode_required = false,
    },
}
```

### URL-only mode (no auto browser launch)

```zig
.app = .{
    .launch_policy = .{
        .first = .web_url,
        .second = null,
        .third = null,
        .app_mode_required = false,
    },
}
```

### Native-only required mode

```zig
.app = .{
    .launch_policy = .{
        .first = .native_webview,
        .second = null,
        .third = null,
        .app_mode_required = true,
    },
}
```

## New Introspection APIs

Use these to avoid warning-string parsing:
- `Window.runtimeRenderState()` / `Service.runtimeRenderState()`
- `Window.probeCapabilities()` / `Service.probeCapabilities()`
- `Service.listRuntimeRequirements(allocator)`
- `App.onDiagnostic(...)` / `Service.onDiagnostic(...)`

## RPC Dispatch Defaults

RPC dispatch is async by default via threaded backend execution:

```zig
try window.bindRpc(rpc_methods, .{
    .dispatcher_mode = .threaded, // default
});
```

Runtime behavior:
- `POST <rpc_route>` returns the RPC result directly.
- JS remains async (`Promise`), but there is no job-id layer.
- For strict same-thread execution, opt into `dispatcher_mode = .sync`.

## Notes

- Existing warning log strings may still appear, but typed diagnostics are the authoritative integration surface.
- For Linux packaging, validate helper/runtime presence through `listRuntimeRequirements`.
- Active examples are tracked under `examples/` and built from those paths directly.
- JS asset generation is strict and deterministic in the active build path.

## Pinned Struct Move Safety

This release keeps the current architecture (no forced allocation pinning), so move-safety is explicit:

- Do not move/copy an initialized `App` after it owns windows.
- Do not move/copy an initialized `Service` after `Service.init`.

Avoid:
- By-value hops of initialized values between helper return values/temporaries.
- Relocating containers that move initialized `Service`/`App` values.

Prefer:
- Initialize in final storage.
- Pass pointers (`*Service`, `*App`) across function boundaries.

Debug guard behavior:
- With diagnostics enabled via `onDiagnostic(...)`, `Debug` and `ReleaseSafe` emit typed diagnostics then fail fast:
  - `lifecycle.pinned_struct_moved.app`
  - `lifecycle.pinned_struct_moved.service`
- `ReleaseFast` and `ReleaseSmall` compile these checks out.
