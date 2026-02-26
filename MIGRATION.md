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
    .transport_mode = .native_webview,
    .browser_fallback_on_native_failure = true,
    .auto_open_browser = true,
});
```
