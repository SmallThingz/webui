# Contributing

Thanks for contributing to WebUI Zig.

## Development Setup

- Zig `0.15.2+` (see `build.zig.zon`)
- Linux, macOS, or Windows

Core commands:

```bash
zig build
zig build test
zig build examples
zig build parity-local
```

## Branching and PRs

- Create focused PRs with one clear goal.
- Include tests for behavior changes.
- Keep public API changes documented in `MIGRATION.md` and `DOCUMENTATION.md`.
- Do not commit binaries or cache outputs.

## Code Quality Rules

- Run `zig fmt` on changed Zig files.
- Keep active runtime pure Zig.
- Do not add `@cImport`, `translate-c`, or active C/C++ runtime source paths.
- Prefer explicit, deterministic behavior over implicit fallbacks.

Static guards are enforced by build steps; keep them green.

## Testing Expectations

Before opening a PR, run:

```bash
zig build test
zig build examples
zig build parity-local
```

If your change affects launch/runtime behavior, also test at least one real GUI run:

```bash
zig build run -Dexample=minimal -Drun-mode=webview,browser,web-url
```

## Commit Guidance

- Use clear commit messages describing behavior changes.
- Mention platform-specific impact (Linux/macOS/Windows) when relevant.
- If a breaking API change is intentional, call it out explicitly.

## Reporting Regressions

Include:

- exact command used
- OS + Zig version
- expected behavior vs actual behavior
- logs or stack trace
