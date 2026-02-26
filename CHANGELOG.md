# Changelog

## 2026-02-24

- Replaced active C-backed build/runtime path with Zig-only modules.
- Added idiomatic Zig API (`App`, `Window`, `Event`, `RpcRegistry`, enums/options).
- Added typed RPC reflection registration and generated JS bridge rendering.
- Added Zig tools: `tools/bridge_gen.zig`, `tools/vfs_gen.zig`.
- Added Zig example entrypoints (`main.zig`) for all legacy C/C++ example directories.
- Rewrote project-authored example JS/TS assets to bridge-first RPC usage.
- Added static guards via `zig build parity-local`.
- Added CI matrix for Linux/macOS/Windows.
- Archived legacy native/script sources under `upstream_snapshot/webui-2.5.0-beta.4`.
