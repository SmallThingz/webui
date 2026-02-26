# Migration Guide: Launch Order + Async RPC Jobs

This guide covers the hard API replacement in `AppOptions` and the new async RPC job APIs.

## AppOptions Launch Fields (Hard Replace)

Removed fields:
- `transport_mode`
- `auto_open_browser`
- `browser_fallback_on_native_failure`

Replacement:
- `launch_policy: LaunchPolicy`

```zig
pub const LaunchSurface = enum {
    native_webview,
    browser_window,
    web_url,
};

pub const LaunchPolicy = struct {
    first: LaunchSurface = .native_webview,
    second: ?LaunchSurface = .browser_window,
    third: ?LaunchSurface = .web_url,
    allow_dual_surface: bool = false,
    app_mode_required: bool = true,
};
```

## Old -> New Mapping

### Native-first with browser fallback

Before:

```zig
.app = .{
    .transport_mode = .native_webview,
    .browser_fallback_on_native_failure = true,
    .auto_open_browser = true,
}
```

After:

```zig
.app = .{
    .launch_policy = .{
        .first = .native_webview,
        .second = .browser_window,
        .third = .web_url,
    },
}
```

### Browser-only mode

Before:

```zig
.app = .{
    .transport_mode = .browser_fallback,
    .auto_open_browser = true,
}
```

After:

```zig
.app = .{
    .launch_policy = .{
        .first = .browser_window,
        .second = null,
        .third = null,
        .app_mode_required = false,
    },
}
```

### URL-only mode (no auto browser launch)

```zig
.app = .{
    .launch_policy = .{
        .first = .web_url,
        .second = null,
        .third = null,
        .app_mode_required = false,
    },
}
```

### Native-only required mode

```zig
.app = .{
    .launch_policy = .{
        .first = .native_webview,
        .second = null,
        .third = null,
        .app_mode_required = true,
    },
}
```

## New Introspection APIs

Use these to avoid warning-string parsing:
- `Window.runtimeRenderState()` / `Service.runtimeRenderState()`
- `Window.probeCapabilities()` / `Service.probeCapabilities()`
- `Service.listRuntimeRequirements(allocator)`
- `App.onDiagnostic(...)` / `Service.onDiagnostic(...)`

## Async RPC Jobs (Push-First + Poll Fallback)

Enable async jobs:

```zig
try window.bindRpc(rpc_methods, .{
    .execution_mode = .queued_async,
    .job_queue_capacity = 1024,
    .job_poll_min_ms = 200,
    .job_poll_max_ms = 1000,
    .push_job_updates = true,
});
```

Runtime behavior:
- `POST <rpc_route>` returns `job_id` immediately.
- Completion updates are pushed over `/webui/ws` as `rpc_job_update`.
- If push is unavailable (or delayed), bridge falls back to bounded polling:
  - `GET /rpc/job?id=<job_id>`
  - `POST /rpc/job/cancel`

Typed control APIs:
- `Window.rpcPollJob(allocator, job_id) !RpcJobStatus`
- `Window.rpcCancelJob(job_id) !bool`
- `Service.rpcPollJob(...)` / `Service.rpcCancelJob(...)`

## Notes

- Existing warning log strings may still appear, but typed diagnostics are the authoritative integration surface.
- For Linux packaging, validate helper/runtime presence through `listRuntimeRequirements`.
- Active examples are tracked under `examples/` and built from those paths directly.
- Legacy JS asset generator compatibility arguments were removed; the build path is now strict and deterministic.

## Pinned Struct Move Safety

This release keeps the current architecture (no forced allocation pinning), so move-safety is explicit:

- Do not move/copy an initialized `App` after it owns windows.
- Do not move/copy an initialized `Service` after `Service.init`.

Avoid:
- By-value hops of initialized values between helper return values/temporaries.
- Relocating containers that move initialized `Service`/`App` values.

Prefer:
- Initialize in final storage.
- Pass pointers (`*Service`, `*App`) across function boundaries.

Debug guard behavior:
- With diagnostics enabled via `onDiagnostic(...)`, `Debug` and `ReleaseSafe` emit typed diagnostics then fail fast:
  - `lifecycle.pinned_struct_moved.app`
  - `lifecycle.pinned_struct_moved.service`
- `ReleaseFast` and `ReleaseSmall` compile these checks out.
