# Migration Guide: Launch Policy + Async RPC Jobs

This guide covers the hard API replacement in `AppOptions` and the new async RPC job APIs.

## AppOptions Launch Fields (Hard Replace)

Removed fields:
- `transport_mode`
- `auto_open_browser`
- `browser_fallback_on_native_failure`

Replacement:
- `launch_policy: LaunchPolicy`

```zig
pub const LaunchPolicy = struct {
    preferred_transport: enum { native_webview, browser } = .native_webview,
    fallback_transport: enum { none, browser } = .browser,
    browser_open_mode: enum { never, on_browser_transport, always } = .on_browser_transport,
    allow_dual_surface: bool = false,
    app_mode_required: bool = false,
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
        .preferred_transport = .native_webview,
        .fallback_transport = .browser,
        .browser_open_mode = .on_browser_transport,
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
        .preferred_transport = .browser,
        .fallback_transport = .browser,
        .browser_open_mode = .on_browser_transport,
    },
}
```

### Native-only required mode (no browser fallback)

```zig
.app = .{
    .launch_policy = .{
        .preferred_transport = .native_webview,
        .fallback_transport = .none,
        .browser_open_mode = .never,
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
- If push is unavailable, bridge falls back to bounded polling:
  - `GET /rpc/job?id=<job_id>`
  - `POST /rpc/job/cancel`

Typed control APIs:
- `Window.rpcPollJob(allocator, job_id) !RpcJobStatus`
- `Window.rpcCancelJob(job_id) !bool`
- `Service.rpcPollJob(...)` / `Service.rpcCancelJob(...)`

## Notes

- Existing warning log strings may still appear, but typed diagnostics are the authoritative integration surface.
- For Linux packaging, validate helper/runtime presence through `listRuntimeRequirements`.
