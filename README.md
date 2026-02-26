# WebUI Zig Manual Port

This repository now uses a Zig-only active runtime and build graph.

## What changed

- No `@cImport`
- No active C/C++/ObjC compilation in runtime/library build paths
  - JS helper asset processing/minification is pure Zig (no `zig cc` path)
- Idiomatic Zig API surface:
  - `App`
  - `Window`
  - `Event`
  - `RpcRegistry`
  - `DispatcherMode`
  - `BridgeOptions`
  - `TransportMode`

Legacy native and script sources are archived in:

- `upstream_snapshot/webui-2.5.0-beta.4/`

## Build

```bash
zig build
zig build test
zig build examples
zig build parity-report
zig build parity-local
zig build os-matrix
zig build bridge
zig build run
zig build run -Dexample=fancy_window
```

`zig build run` runs all examples by default (`-Dexample=all`) with a native-webview-first configuration and browser fallback enabled.

Available `-Dexample=` values:
- `minimal`
- `call_js_from_zig`
- `call_zig_from_js`
- `serve_folder`
- `vfs`
- `public_network`
- `multi_client`
- `chatgpt_api`
- `custom_web_server`
- `react`
- `frameless`
- `fancy_window`
- `translucent_rounded`
- `text_editor`
- `minimal_oop`
- `call_js_oop`
- `call_oop_from_js`
- `serve_folder_oop`
- `vfs_oop`
- `all` (batch mode with short auto-timeout per example)

`zig build os-matrix` compiles the library and examples across Linux/macOS/Windows targets with static and dynamic linkage combinations.

### Build Flags

- `-Ddynamic=true`
  - Builds `webui` as a shared library (`.so`/`.dylib`/`.dll`) instead of a static archive.
  - This changes artifact linkage format only; it does not enable/disable runtime features by itself.
- `-Denable-tls=true`
  - Sets TLS-enabled default at compile time for runtime options.
- `-Denable-webui-log=true`
  - Sets WebUI logging-enabled default at compile time for runtime options.
- `-Dminify-embedded-js=true` (default: `true`)
  - Processes embedded runtime helper JS (used by runtime-generated bridge strings) using pure Zig tooling.
- `-Dminify-written-js=true` (default: `false`)
  - Processes written runtime helper JS assets (used by file-writing bridge generation paths) using pure Zig tooling.

These compile-time values are exported by the module as:
- `webui.BuildFlags.dynamic`
- `webui.BuildFlags.enable_tls`
- `webui.BuildFlags.enable_webui_log`

## Usage

```zig
const std = @import("std");
const webui = @import("webui");

pub const rpc_methods = struct {
    pub fn ping() []const u8 {
        return "pong";
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try webui.Service.init(gpa.allocator(), rpc_methods, .{
        .app = .{
            .transport_mode = .native_webview,
            .browser_fallback_on_native_failure = true,
            .auto_open_browser = true,
        },
        .window = .{
            .title = "Demo",
            .style = .{
                .frameless = true,
                .transparent = true,
                .corner_radius = 12,
            },
        },
    });
    defer service.deinit();

    const bridge_js = webui.Service.generatedClientScriptComptime(rpc_methods, .{});
    const bridge_dts = webui.Service.generatedTypeScriptDeclarationsComptime(rpc_methods, .{});
    _ = bridge_js;
    _ = bridge_dts;

    try service.show(.{ .html = "<html><body>Hello</body></html>" });
    try service.run();
    _ = try service.control(.maximize);
}
```

## Notes

- `zig build bridge` generates `zig-out/share/webui/webui_bridge.js`.
- `zig build bridge` also generates `zig-out/share/webui/webui_bridge.d.ts`.
- `zig build runtime-helpers` prepares helper assets:
  - `zig-out/share/webui/runtime_helpers.embed.js` (default minified)
  - `zig-out/share/webui/runtime_helpers.written.js` (default non-minified)
- Declare RPC methods in app entrypoints as `pub const rpc_methods = struct { ... };`.
- The same `rpc_methods` constant should be used for:
  - service initialization: `webui.Service.init(allocator, rpc_methods, ...)`
  - compile-time JS generation: `webui.Service.generatedClientScriptComptime(rpc_methods, ...)`
  - compile-time TS generation: `webui.Service.generatedTypeScriptDeclarationsComptime(rpc_methods, ...)`
- The typed RPC bridge can also be emitted at runtime from `Service.rpcClientScript()` / `RpcRegistry.generatedClientScript()`.
- Runtime helper JS strings are exported as:
  - `webui.runtime_helpers_js` (embedded/default variant)
  - `webui.runtime_helpers_js_written` (written-file variant)
- Friendly shortcuts:
  - `App.initDefault(allocator)`
  - `App.window()` / `App.windowWithTitle(title)`
  - `Window.show(.{ .html = ... | .file = ... | .url = ... })`
  - `Window.applyStyle(WindowStyle)`
  - `Window.currentStyle()`
  - `Window.lastWarning()` / `Window.clearWarning()`
  - `Window.control(WindowControl)`
  - `Window.setCloseHandler(handler, context)`
  - `Window.capabilities()`
  - `Window.bindRpc(RpcStruct, RpcOptions)`
  - `Window.rpcClientScript(BridgeOptions)`
  - `Window.rpcTypeDeclarations(BridgeOptions)`
  - `Service.init(allocator, rpc_methods, options)`
  - `Service.generatedClientScriptComptime(rpc_methods, options)`
  - `Service.generatedTypeScriptDeclarationsComptime(rpc_methods, options)`
  - `Service.lastWarning()` / `Service.clearWarning()`
  - `webui.process_signals.install()` / `webui.process_signals.stopRequested()` for immediate `Ctrl+C` shutdown handling
- Comptime bridge generation is available via `RpcRegistry.generatedClientScriptComptime(RpcStruct, options)`.
- TypeScript declarations are available via:
  - `RpcRegistry.generatedTypeScriptDeclarations(options)`
  - `RpcRegistry.generatedTypeScriptDeclarationsComptime(RpcStruct, options)`
  - `RpcRegistry.writeGeneratedTypeScriptDeclarations(path, options)`
- Third-party browser-side JS libraries are preserved as static assets.
- Manual desktop smoke checklist: `docs/manual_gui_checklist.md`.

## Runtime Transport

- Browser fallback runtime now serves:
  - bridge script route (default `/webui_bridge.js`)
  - RPC route (default `/webui/rpc`)
  - local content (`showHtml` / `showFile`) over `http://127.0.0.1:<port>/`
- Browser control APIs:
  - `Window.browserUrl()` returns the local browser-render URL.
  - `Window.openInBrowser()` explicitly opens the window content in a discovered browser.
  - `Window.openInBrowserWithOptions(webui.BrowserLaunchOptions)` overrides default browser launch policy per call.
  - `AppOptions.browser_launch.prompt_policy` supports `quiet_default` and `browser_default` presets.
- Window parity routes (used by generated bridge helpers):
  - `POST /webui/window/control` (`minimize|maximize|restore|close|hide|show`)
  - `GET|POST /webui/window/style`
- If `transport_mode = .native_webview`, `browser_fallback_on_native_failure=true` (default) keeps browser rendering available.
- Window style/control calls are routed through backend abstractions first, then browser emulation when native behavior is unavailable.
- When a native backend cannot satisfy a requested style/control on the current target/runtime, WebUI emits warning events/logs, sets `lastWarning()`, and falls back to emulation when enabled.
- Browser fallback launch tracks spawned browser PID when available and terminates it on `shutdown()`.
- On POSIX, browser fallback is launched as a direct child process and assigned its own process group; shutdown kills the full browser process group.
- If PID tracking is unavailable on a platform/launcher path, frontend lifecycle heartbeat remains the fallback close mechanism.
- Browser catalog includes at least:
  - Firefox, Chrome, Edge, Chromium, Yandex, Brave, Vivaldi (Windows/macOS/Linux)
  - Epic (Windows/macOS/Linux catalog entry)
  - Safari (Windows/macOS/Linux catalog entry; active availability varies by OS)
  - Opera (Windows/macOS/Linux catalog entry)
- Dispatcher modes:
  - `sync`: invoke RPC on request thread
  - `threaded`: request thread submits RPC to worker thread queue (poll-driven condition waits)
  - `custom`: user callback receives function name + invoker + parsed args
- Bridge/rpc routes and namespace are configurable via `BridgeOptions`.
- Network transport model:
  - one listener thread accepts and handles HTTP requests
  - threaded RPC dispatch hands off execution to a worker thread queue
  - listener thread uses condition-variable polling waits for worker completion and then writes the response
