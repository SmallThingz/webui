# Upstream WebUI File-By-File Capability Audit

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
- `src/window_style.zig`
- `src/ported/browser_discovery.zig`

Implemented capability groups:
- Window lifecycle/show/navigation/shutdown.
- Window style/control and fallback semantics.
- Browser discovery + aggressive search paths + launch policy.
- RPC bridge generation/runtime + threaded dispatcher pipeline.
- Raw channel send/receive.
- Public/private bind policy equivalent (`AppOptions.public_network`).
- Proxy launch option equivalent (`BrowserLaunchOptions.proxy_server`).
- Script command queue + push dispatch (`/webui/ws`) with response routing (`/webui/script/response`) for modern `runScript`/`evalScript`.
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
