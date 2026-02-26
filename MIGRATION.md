# Migration: `webui_*` to Idiomatic Zig API

## High-level mapping

- `webui_new_window*` -> `App.newWindow()`
- `webui_show`, `webui_show_browser`, `webui_show_wv` -> `Window.show(.{ .html | .url | .file })` (or `showHtml/showUrl/showFile`)
- explicit browser launch/URL handling -> `Window.browserUrl()`, `Window.openInBrowser()`
- `webui_navigate` -> `Window.navigate()`
- `webui_bind` -> define `pub const rpc_methods = struct { ... };` then `Service.init(..., rpc_methods, ...)`
- `webui_run*`, `webui_script*` -> typed RPC client calls from generated bridge
- `webui_send_raw*` -> `Window.sendRaw()` + `Window.onRaw()`
- window chrome/style APIs -> `Window.applyStyle(WindowStyle)` + `Window.control(WindowControl)` + `Window.capabilities()`
- close veto hooks -> `Window.setCloseHandler(handler, context)`
- `webui_wait` -> `App.run()`
- `webui_exit` -> `App.shutdown()`

## Example

Old style:

```c
size_t w = webui_new_window();
webui_bind(w, "Exit", on_exit);
webui_show(w, html);
webui_wait();
```

New Zig style:

```zig
pub const rpc_methods = struct {
    pub fn ping() []const u8 {
        return "pong";
    }
};

var service = try webui.Service.init(allocator, rpc_methods, .{
    .window = .{ .title = "App" },
});
defer service.deinit();

const bridge_js = webui.Service.generatedClientScriptComptime(rpc_methods, .{});
const bridge_dts = webui.Service.generatedTypeScriptDeclarationsComptime(rpc_methods, .{});
_ = bridge_js;
_ = bridge_dts;

try service.show(.{ .html = html });
try service.run();
```

Browser fallback controls:

```zig
var app = try webui.App.init(allocator, .{
    .launch_policy = .{
        .preferred_transport = .native_webview,
        .fallback_transport = .browser,
        .browser_open_mode = .on_browser_transport,
    },
});
```

Repository cleanup notes:
- Active example sources are under `examples/` (used directly by `zig build run`/`zig build examples`).
- Legacy bridge asset compatibility arguments were removed from the build-time JS asset generator.

## Pinned Struct Move Safety

The runtime currently enforces move safety by contract (not by forced heap pinning):

- Do not move/copy an initialized `App` after it owns windows.
- Do not move/copy an initialized `Service` after `Service.init`.

Unsafe examples:
- Extra by-value copies of initialized structs.
- Relocating containers that move initialized `Service`/`App` entries.

Safe examples:
- Initialize in final storage.
- Pass pointers (`*Service`, `*App`) across helpers.

Debug guard behavior:
- With diagnostics enabled via `onDiagnostic(...)`, `Debug`/`ReleaseSafe` emit typed diagnostics and fail fast:
  - `lifecycle.pinned_struct_moved.app`
  - `lifecycle.pinned_struct_moved.service`
- `ReleaseFast`/`ReleaseSmall` compile these checks out.

This is intentionally documented and guarded behavior, not an allocation-based pinning redesign.
