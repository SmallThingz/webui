# Manual GUI Smoke Validation

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
