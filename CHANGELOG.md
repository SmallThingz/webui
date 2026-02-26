# Changelog

## 2026-02-26

- Added debug-time pinned-struct move guards for callback binding invariants (`App`/`Service`).
- Added typed lifecycle diagnostics for detected move violations:
  - `lifecycle.pinned_struct_moved.app`
  - `lifecycle.pinned_struct_moved.service`
- Added deterministic invariant regression tests for stable path, moved path detection, diagnostic emission, and no-false-positive flow.
- Added move/pinning safety guidance in `README.md`, `docs/migration.md`, and `MIGRATION.md`.
- Preserved runtime architecture (no allocation-based pinning rewrite).

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
