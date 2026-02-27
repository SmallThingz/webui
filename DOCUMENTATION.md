# 📚 DOCUMENTATION

This is the single consolidated documentation file for the library.
It combines content that previously lived under `docs/`.

## Table of Contents

1. [Migration Guide](#migration-guide)
2. [Manual GUI Checklist](#manual-gui-checklist)
3. [Upstream File Parity](#upstream-file-parity)

---

## Migration Guide


This guide covers the hard API replacement in `AppOptions` and current runtime API behavior.

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

---

## Manual GUI Checklist


Run this checklist on real desktops for Linux, macOS, and Windows.
Do this after `zig build`, `zig build test`, and `zig build examples`.

## 1. Build variants to validate

- `zig build`
- `zig build -Ddynamic=true`
- `zig build -Denable-tls=true`
- `zig build -Denable-webui-log=true`
- `zig build -Dtarget=x86_64-windows`
- `zig build -Ddynamic=true -Dtarget=x86_64-windows`
- `zig build -Dtarget=aarch64-macos`
- `zig build -Ddynamic=true -Dtarget=aarch64-macos`

## 2. Browser launch validation (third-party support)

For each OS, validate at least:
- Chromium family browser (Chrome/Edge/Brave/Chromium/Vivaldi/Opera)
- Gecko family browser (Firefox/Tor/LibreWolf/Mullvad/Pale Moon)
- Additional installed third-party browsers where available (Arc, Sidekick, Shift, DuckDuckGo, SigmaOS, Lightpanda)

For each browser:
- Launch example app and confirm browser opens when `launch_policy.browser_open_mode` allows browser transport.
- Confirm app opens with explicit env override:
  - `WEBUI_BROWSER_PATH`
  - `WEBUI_BROWSER`
  - `BROWSER`
- Confirm both absolute executable path and command-name override work.
- Confirm URL opens and app remains responsive after launch.

## 3. Messaging path validation

For every OS and at least one browser per engine family:
- Verify event callback sequence includes `connected`, navigation events, and `disconnected`.
- Verify generated bridge is reachable and executable (`/webui_bridge.js` or runtime-generated script).
- Verify RPC request/response works for:
  - `int`, `float`, `bool`, `string`
  - binary/raw payload path
- Verify custom dispatcher mode path (if configured) executes correctly.
- Verify raw channel callbacks (`sendRaw` and `onRaw`) fire with expected payload.

## 4. Transport-mode validation

- `browser_fallback`:
  - Confirm initial connect.
  - Confirm send/receive roundtrip.
  - Confirm reconnect after browser refresh.
- `native_webview`:
  - Confirm platform webview opens.
  - Confirm native messaging callback and payload roundtrip.

## 5. Window/visual parity validation

Run this on real Linux/macOS/Windows desktops:
- Frameless mode:
  - Drag region behaves like a native title bar.
  - Top bar spans full width during resize.
- Transparency:
  - Semi-transparent backgrounds are visible where supported.
- Rounded corners:
  - Window corner radius is visible.
- Window control buttons:
  - Minimize, maximize, restore, close, hide, show all work from the top bar.
- Window sizing and placement:
  - `size`, `min_size`, `position`, and `center` behavior works.
- Kiosk and icon:
  - Kiosk/fullscreen behavior and icon updates work.
- Close handler:
  - Veto path prevents close.
  - Allow path closes window and terminates app loop.
- Process lifecycle:
  - Closing the window exits the app.
  - `Ctrl+C` exits the app and closes the window/session cleanly.

## 6. TLS validation

When built with `-Denable-tls=true`:
- Confirm secure endpoint starts.
- Confirm handshake succeeds from browser.
- Confirm bridge/RPC still works over TLS.
- Confirm reconnect still works after refresh.

## 7. Pass/fail criteria

Pass when all of the following are true on Linux, macOS, and Windows:
- No crash on startup, navigation, RPC calls, raw messaging, or shutdown.
- Browser discovery opens installed third-party browsers with and without env override.
- Messaging and reconnection are stable in both transport modes used by the test app.
- Window controls and style behaviors pass the parity checklist above.
- TLS flow (when enabled) is functional end-to-end.

---

## Upstream File Parity


This audit compares active Zig runtime coverage against upstream `webui/` sources, skipping bundled libraries and system headers as requested.

## Scope

Compared upstream files:
- `webui/include/webui.h`
- `webui/src/webui.c`
- `webui/src/webview/win32_wv2.cpp`
- `webui/src/webview/win32_wv2.hpp`
- `webui/src/webview/wkwebview.m`
- `webui/bridge/webui.ts`
- `webui/bridge/utils.ts`
- `webui/bridge/js2c.js`
- `webui/build.zig`

Skipped by request:
- `webui/src/civetweb/*` (third-party CivetWeb)
- `webui/src/webview/WebView2.h` (system header mirror)
- `webui/src/webview/EventToken.h` (system/interop header mirror)

## Capability Status By File

### `webui/include/webui.h`
Status: **Partial**

What is covered:
- Core capabilities represented in idiomatic Zig API (`App`, `Window`, `Service`, typed RPC, style/control, lifecycle).
- Browser launch, process lifecycle, style/capability reporting, raw messaging.

What is not fully mirrored:
- Full C ABI surface (all `webui_*` and `webui_interface_*` symbols) is deferred in active API.
- C-style buffer semantics are exposed through modern Zig APIs (`Window.runScript`, `Window.evalScript`) rather than 1:1 C ABI wrappers.

### `webui/src/webui.c`
Status: **Partial**

Mapped runtime:
- `src/root.zig`
- `src/ported/webui.zig`
- `src/root/window_style.zig`
- `src/ported/browser_discovery.zig`

Implemented capability groups:
- Window lifecycle/show/navigation/shutdown.
- Window style/control and fallback semantics.
- Browser discovery + aggressive search paths + launch policy.
- RPC bridge generation/runtime + threaded dispatcher pipeline.
- Raw channel send/receive.
- Public/private bind policy equivalent (`AppOptions.public_network`).
- Proxy launch option equivalent (`BrowserLaunchOptions.proxy_server`).
- Script command queue + push dispatch (`/webui/ws`) with WS `script_response` routing for modern `runScript`/`evalScript`.
- TLS runtime state API (`TlsOptions`, `App.setTlsCertificate`, `App.tlsInfo`) with certificate ingest and generated fallback material.

Remaining gaps versus full `webui.c` behavior:
- Real encrypted HTTPS transport path is not complete (TLS state exists, transport still HTTP in active server loop).
- Full native host completeness on Windows/macOS remains partial.
- `webui_interface_*` compatibility layer remains deferred by milestone decision.

### `webui/src/webview/win32_wv2.cpp`
Status: **Partial**

Mapped runtime:
- `src/ported/webview/win32_wv2.zig`
- `src/ported/webview/backend.zig`

Coverage:
- Unified backend contract integration done.
- Full native WebView2 host parity from upstream C++ is not complete yet (some operations still route through browser-process control path).

### `webui/src/webview/win32_wv2.hpp`
Status: **Partial**

Coverage:
- Replaced by idiomatic Zig backend contract.
- Header-level C++ host types are intentionally not mirrored as C++ ABI.
- Remaining gap is the same as `win32_wv2.cpp`: full native host parity completeness.

### `webui/src/webview/wkwebview.m`
Status: **Partial**

Mapped runtime:
- `src/ported/webview/wkwebview.zig`
- `src/ported/webview/backend.zig`

Coverage:
- Native backend contract integration exists.
- Full Objective-C WKWebView host parity is not complete yet (some controls still browser-process mediated).

### `webui/bridge/webui.ts`
Status: **Implemented**

Mapped runtime:
- `src/bridge/template.zig`
- `src/root.zig` RPC registry and generation APIs

Coverage:
- Typed RPC surface generation and runtime bridge serving.

### `webui/bridge/utils.ts`
Status: **Implemented**

Mapped runtime:
- `src/bridge/runtime_helpers.source.js`
- `src/bridge/generated/runtime_helpers.embed.js`
- `src/bridge/generated/runtime_helpers.written.js`

Coverage:
- Runtime helper behavior, lifecycle hooks, control/style route helpers.

### `webui/bridge/js2c.js`
Status: **Implemented**

Mapped runtime:
- `tools/bridge_gen.zig`
- `tools/js_asset_gen.zig`

Coverage:
- Build-time bridge generation with embedded and written assets.

### `webui/build.zig`
Status: **Implemented**

Mapped runtime:
- `/home/a/projects/zig/webui/build.zig`

Coverage:
- Zig-only runtime build graph for active code.
- Matrix/build gates, parity-local/parity-report, examples, static guards.

## Current Net Parity Summary

Latest parity report:
- `total=40`
- `implemented=35`
- `partial=5`
- `missing=0`

Partial buckets correspond to:
- Native visual parity completeness on all native backends.
- TLS transport encryption depth.
- Deferred C-ABI compatibility layer.

## Recommendation

Current codebase has no `missing` tracked features in local parity gates, but it is not yet strict 1:1 parity with every upstream capability detail. For full parity, prioritize:
1. Native backend completion on Windows/macOS.
2. HTTPS transport activation for TLS-enabled runtime.
3. Optional compatibility module for `webui_interface_*` if C-wrapper parity is needed.
