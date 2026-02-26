# WebUI Zig (Manual Port)

A Zig-first WebUI runtime with typed RPC, generated JS/TS bridge code, native-webview-first execution, and browser fallback.

## Status

This project is actively usable, but it is not yet full behavioral parity with upstream `webui.c`.

Current parity snapshot (`zig build parity-local`):
- `total=40`
- `implemented=36`
- `partial=4`
- `missing=0`

Current partial areas:
- `window.visual.transparency`
- `window.visual.frameless`
- `window.visual.corner_radius`
- `server.tls_toggle`

See `parity/status.json` and `docs/upstream_file_parity.md` for details.

## Highlights

- Zig-only active runtime/library build path (`@cImport` and runtime C/C++/ObjC compilation removed).
- Idiomatic API (`App`, `Window`, `Service`, `RpcRegistry`, `WindowStyle`, typed events).
- Comptime RPC registration via `pub const rpc_methods = struct { ... }`.
- Generated JS client + TypeScript declarations.
- `sync`, `threaded`, and `custom` RPC dispatch modes.
- Native-webview-first runtime with browser fallback.
- Extensive third-party browser discovery/search paths across Linux/macOS/Windows.

## Quick Start

```bash
zig build
zig build test
zig build examples
zig build run
```

Run one example:

```bash
zig build run -Dexample=translucent_rounded
```

Force runtime mode:

```bash
zig build run -Dexample=fancy_window -Drun-mode=webview
zig build run -Dexample=fancy_window -Drun-mode=browser
```

List all build steps/options:

```bash
zig build -l
zig build -h
```

## Build Flags

| Flag | Default | Effect |
|---|---:|---|
| `-Ddynamic=true` | `false` | Build/install `webui` as a shared library (`.so`/`.dylib`/`.dll`) instead of static archive. |
| `-Denable-tls=true` | `false` | Enables TLS defaults in runtime options/API state. |
| `-Denable-webui-log=true` | `false` | Enables runtime log defaults. |
| `-Dminify-embedded-js=true` | `true` | Minifies embedded runtime helper JS asset at build time. |
| `-Dminify-written-js=true` | `false` | Minifies written runtime helper JS output artifact. |
| `-Dexample=<name>` | `all` | Selects example used by `zig build run`. |
| `-Drun-mode=webview|browser` | `webview` | Chooses native-webview path or browser-mode path in examples. |
| `-Dtarget=<triple>` | host | Cross-compiles the library/examples for another target. |

Exported compile-time values:
- `webui.BuildFlags.dynamic`
- `webui.BuildFlags.enable_tls`
- `webui.BuildFlags.enable_webui_log`
- `webui.BuildFlags.run_mode`

## Build Steps

- `zig build` (default install)
- `zig build test`
- `zig build examples`
- `zig build run`
- `zig build bridge`
- `zig build runtime-helpers`
- `zig build vfs-gen`
- `zig build parity-report`
- `zig build parity-local`
- `zig build os-matrix`

## API Overview

Top-level exports (`src/root.zig`):
- `App`, `Window`, `Service`
- `Event`, `EventKind`
- `RpcRegistry`, `RpcOptions`, `DispatcherMode`
- `WindowStyle`, `WindowControl`, `WindowCapability`
- `BridgeOptions`, `TransportMode`
- `ScriptOptions`, `ScriptEvalResult`
- `TlsOptions`, `TlsInfo`

Core flow:
1. Declare `pub const rpc_methods` as a comptime struct of functions.
2. Initialize `Service` or `App + Window`.
3. Show `html`, `file`, or `url` content.
4. Run app loop and exchange RPC/raw messages.

### Minimal Service Example

```zig
const std = @import("std");
const webui = @import("webui");

pub const rpc_methods = struct {
    pub fn ping() []const u8 {
        return "pong";
    }

    pub fn add(a: i64, b: i64) i64 {
        return a + b;
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
        .window = .{ .title = "WebUI Zig Demo" },
        .rpc = .{ .dispatcher_mode = .threaded },
    });
    defer service.deinit();

    try service.show(.{
        .html =
            "<!doctype html><html><head><meta charset=\"utf-8\"/>" ++
            "<script type=\"module\" src=\"/webui_bridge.js\"></script></head>" ++
            "<body><button id=\"b\">Ping</button><pre id=\"out\"></pre>" ++
            "<script>document.getElementById('b').onclick=async()=>{" ++
            "const p=await webuiRpc.ping();const s=await webuiRpc.add(20,22);" ++
            "document.getElementById('out').textContent=`${p} ${s}`;};</script></body></html>",
    });

    try service.run();
}
```

## Typed RPC + Bridge Generation

All RPC methods are declared once at comptime:

```zig
pub const rpc_methods = struct {
    pub fn ping() []const u8 { return "pong"; }
    pub fn add(a: i64, b: i64) i64 { return a + b; }
};
```

Then you can:
- Serve runtime-generated client script: `service.rpcClientScript(.{})`
- Generate compile-time client script: `webui.Service.generatedClientScriptComptime(rpc_methods, .{})`
- Generate compile-time TypeScript declarations: `webui.Service.generatedTypeScriptDeclarationsComptime(rpc_methods, .{})`

Script execution APIs:
- `Window.runScript(script, options)`
- `Window.evalScript(allocator, script, options)`

## Browser Support (Discovery Catalog)

The discovery catalog includes at least these families:
- Firefox, Chrome, Edge, Chromium, Yandex, Brave, Vivaldi
- Epic, Safari, Opera
- Plus: Arc, DuckDuckGo, Tor, LibreWolf, Mullvad, Sidekick, Shift, Opera GX, Pale Moon, SigmaOS, Lightpanda

Notes:
- Discovery means executable/path support in the catalog and search paths.
- Actual availability still depends on what is installable on each OS.
- Env overrides are supported: `WEBUI_BROWSER_PATH`, `WEBUI_BROWSER`, `BROWSER`.

## Runtime Helper JS Assets

Runtime helper JS is maintained as a source file and exposed in two variants:
- `webui.runtime_helpers_js` (embedded variant)
- `webui.runtime_helpers_js_written` (written-file variant)

Build outputs:
- `zig-out/share/webui/runtime_helpers.embed.js`
- `zig-out/share/webui/runtime_helpers.written.js`

## Examples

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
- `all` (default for `zig build run`)

## Production Notes

What is strong now:
- Typed RPC and generated bridge tooling.
- Browser discovery breadth and fallback policy controls.
- Build/test/parity automation (`parity-local`, `os-matrix`, static guards).

What still needs completion for strict full parity:
- TLS-enabled transport should be true HTTPS end-to-end (currently TLS state exists but transport path is still partial).
- Visual parity for transparency/frameless/corner radius is still marked partial and relies on manual GUI validation.

Use `docs/manual_gui_checklist.md` for required Linux/macOS/Windows smoke validation.

## Repository Layout

- `src/` - active Zig runtime and API.
- `tools/` - build-time generators (`bridge_gen.zig`, `vfs_gen.zig`, asset tooling).
- `webui/examples/` - Zig example entrypoints and example assets.
- `docs/` - parity and manual validation docs.
- `parity/` - parity status + report definitions.

## Migration Docs

- `MIGRATION.md`
- `CHANGELOG.md`
- `docs/upstream_file_parity.md`
