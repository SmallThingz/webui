const std = @import("std");
const webui = @import("webui");

pub const rpc_methods = struct {
    pub fn add(a: i64, b: i64) i64 {
        return a + b;
    }

    pub fn version() []const u8 {
        return "webui-zig-manual-port";
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const demo_url = if (args.len > 1) args[1] else null;

    var service = try webui.Service.init(allocator, rpc_methods, .{
        .app = .{
            .launch_policy = webui.LaunchPolicy.webviewFirst(),
            .window_fallback_emulation = true,
        },
        .window = .{
            .title = "WebUI Zig",
            .style = .{
                .frameless = false,
                .resizable = true,
            },
        },
        .process_signals = true,
    });
    defer service.deinit();

    const script = service.rpcClientScript();
    const script_comptime = webui.Service.generatedClientScriptComptime(rpc_methods, .{});
    const dts = webui.Service.generatedTypeScriptDeclarationsComptime(rpc_methods, .{});
    std.debug.print("Generated bridge size: {d} bytes\n", .{script.len});
    std.debug.print("Generated bridge size (comptime): {d} bytes\n", .{script_comptime.len});
    std.debug.print("Generated d.ts size: {d} bytes\n", .{dts.len});

    if (demo_url) |url| {
        try service.show(.{ .url = url });
        std.debug.print("Opened URL: {s}\n", .{url});
    } else {
        try service.show(.{
            .html = "<!doctype html><html><head><meta charset=\"utf-8\" />" ++
                "<title>WebUI Zig</title><script type=\"module\" src=\"/webui_bridge.js\"></script></head>" ++
                "<body><h1>WebUI Zig Runtime</h1><button id=\"btn\">Call RPC add(7, 9)</button>" ++
                "<pre id=\"out\">ready</pre><script>" ++
                "document.getElementById('btn').addEventListener('click', async () => {" ++
                "const n = await globalThis.webuiRpc.add(7, 9);" ++
                "const v = await globalThis.webuiRpc.version();" ++
                "document.getElementById('out').textContent = 'add=' + n + ', version=' + v;" ++
                "});</script></body></html>",
        });
        std.debug.print("Opened local WebUI page with generated RPC bridge.\n", .{});
    }

    try service.run();
    std.debug.print("WebUI running. Press Ctrl+C to exit.\n", .{});

    while (!service.shouldExit()) {
        std.Thread.sleep(20 * std.time.ns_per_ms);
    }
    service.shutdown();
}
