# 🚀 WebUI Zig

A Zig-first WebUI runtime with typed RPC, deterministic launch policy, native host launch paths, and browser/web fallbacks.

![Zig](https://img.shields.io/badge/Zig-0.15.2%2B-f7a41d)
![Platforms](https://img.shields.io/badge/Platforms-Linux%20%7C%20macOS%20%7C%20Windows-2ea44f)
![Mode](https://img.shields.io/badge/Transport-WebView%20%2B%20Browser%20%2B%20Web-0366d6)

## ⚡ Features

- 🧠 **Comptime RPC surface**: declare `pub const rpc_methods` once and generate JS/TS bridge clients.
- 🎯 **Deterministic launch policy**: explicit, ordered surface selection via `LaunchPolicy`.
- 🪟 **Window controls + style API**: `WindowStyle`, `WindowControl`, capability probing, close handlers.
- 🔌 **WS-first runtime signaling**: reconnecting WebSocket channel for push events and script tasks.
- 🌐 **Broad browser support**: aggressive browser discovery and cross-platform search paths.
- 🧪 **Strong build gates**: tests, examples, parity checks, and OS matrix steps in `build.zig`.
- 🧱 **Pure Zig active graph**: no `@cImport`, no `translate-c`, no active C runtime compilation path.

## 🚀 Quick Start

```bash
zig build
zig build test
zig build examples
zig build run
```

Run one example:

```bash
zig build run -Dexample=fancy_window
```

List all build steps/options:

```bash
zig build -l
zig build -h
```

## 🧭 Launch Modes (Clear Behavior)

For example runs (`zig build run -Drun-mode=...`):

- `webview`: native webview first
- `browser`: external browser app-window
- `web-tab` (or `web`): browser tab
- `web-url`: serve URL only; do not auto-open browser
- Ordered combinations are supported, e.g. `webview,browser,web-url`

Examples:

```bash
zig build run -Dexample=minimal -Drun-mode=webview
zig build run -Dexample=minimal -Drun-mode=browser
zig build run -Dexample=minimal -Drun-mode=web-tab
zig build run -Dexample=minimal -Drun-mode=web
zig build run -Dexample=minimal -Drun-mode=webview,browser,web-url
```

### Close/Refresh semantics

- `browser_window`: closing the browser window should close backend.
- `browser_window`: refreshing should not kill backend (grace + reconnect handling).
- `web_url` / web-tab style workflows: closing tab should not kill backend by default.

## 🧩 Library API (At a Glance)

```zig
const std = @import("std");
const webui = @import("webui");

pub const rpc_methods = struct {
    pub fn ping() []const u8 { return "pong"; }
    pub fn add(a: i64, b: i64) i64 { return a + b; }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try webui.Service.init(gpa.allocator(), rpc_methods, .{
        .app = .{
            .launch_policy = .{
                .first = .native_webview,
                .second = .browser_window,
                .third = .web_url,
            },
        },
        .window = .{ .title = "WebUI Zig" },
        .rpc = .{ .dispatcher_mode = .threaded },
    });
    defer service.deinit();

    try service.showHtml(
        "<!doctype html><html><head><meta charset=\"utf-8\"/>" ++
        "<script type=\"module\" src=\"/webui_bridge.js\"></script></head>" ++
        "<body><button id=\"b\">Ping</button><pre id=\"out\"></pre>" ++
        "<script>document.getElementById('b').onclick=async()=>{" ++
        "document.getElementById('out').textContent=" ++
        "`ping=${await webuiRpc.ping()} add=${await webuiRpc.add(20,22)}`;};</script>" ++
        "</body></html>",
    );

    while (!service.shouldExit()) {
        try service.run();
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
}
```

## 🔐 Launch Policy + Profile Rules

`AppOptions` uses deterministic `LaunchPolicy` ordering.

`BrowserLaunchOptions` uses explicit `profile_rules`:

- `ProfilePathSpec`: `default | ephemeral | custom`
- `ProfileRuleTarget`: `webview | browser_any | browser_kind`
- Rule order is authoritative (first match wins).
- Browser default profile semantics are empty path (`""`) and no forced `--user-data-dir`.
- Webview default profile path uses OS-standard app-data/config locations.

Helpers:

- `webui.browser_default_profile_path`
- `webui.profile_base_prefix_hint`
- `webui.resolveProfileBasePrefix(allocator)`
- `webui.defaultWebviewProfilePath(allocator)`

## 🛠 Build Flags

| Flag | Default | Effect |
|---|---:|---|
| `-Ddynamic=true` | `false` | Build shared library (`.so`/`.dylib`/`.dll`) instead of static archive. |
| `-Denable-tls=true` | `false` | Enable HTTPS/WSS runtime defaults (TLS certificate + secure local transport). |
| `-Denable-webui-log=true` | `false` | Enable runtime logging defaults. |
| `-Dminify-embedded-js=true` | `true` | Minify embedded runtime helper JS at build time. |
| `-Dminify-written-js=true` | `false` | Minify written runtime helper JS artifact. |
| `-Dexample=<name>` | `all` | Select which demo `zig build run` executes. |
| `-Drun-mode=<tokens>` | `webview,browser,web-url` | Example launch order/preset tokens. |
| `-Dtarget=<triple>` | host | Cross-compile target. |

## 📦 Installation

Add as dependency:

```bash
zig fetch --save <git-or-tarball-url>
```

`build.zig`:

```zig
const webui_dep = b.dependency("webui", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("webui", webui_dep.module("webui"));
```

## 🧪 Testing and Validation

```bash
zig build test
zig build examples
zig build parity-local
zig build os-matrix
```

Useful additional steps:

```bash
zig build dispatcher-stress
zig build bridge
zig build runtime-helpers
```

## 🖼 Examples

Run all:

```bash
zig build run
```

Run one:

```bash
zig build run -Dexample=translucent_rounded -Drun-mode=webview,browser,web-url
```

Available `-Dexample` values include:

- `minimal`, `call_js_from_zig`, `call_zig_from_js`
- `bidirectional_rpc`
- `serve_folder`, `vfs`, `public_network`, `multi_client`
- `chatgpt_api`, `custom_web_server`, `react`
- `frameless`, `fancy_window`, `translucent_rounded`, `text_editor`
- `minimal_oop`, `call_js_oop`, `call_oop_from_js`, `serve_folder_oop`, `vfs_oop`

## 📌 Production Notes

Current strengths:

- Typed RPC + generated bridge tooling
- Deterministic launch behavior and runtime introspection
- WS-first signaling and fallback surface control
- Multi-OS build/test/parity gates

Still tracked for strict upstream behavioral parity:

- Full in-process native host completion on Windows/macOS
- Visual/window parity items requiring manual GUI verification on real desktops

See:

- `parity/status.json`
- `DOCUMENTATION.md`

## ⚠️ Move Safety (Important)

`App` and `Service` are move-sensitive after window initialization.

- Do not copy/move initialized `App`/`Service` values by value.
- Keep them in final storage and pass pointers (`*App`, `*Service`).

In debug-safe builds, move-invariant diagnostics are emitted and fail fast to avoid latent crashes.

## 📚 Documentation

- `DOCUMENTATION.md`
- `MIGRATION.md`
- `CHANGELOG.md`

## 📄 License

See `LICENSE`.
