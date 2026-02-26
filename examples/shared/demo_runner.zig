const std = @import("std");
const webui = @import("webui");

pub const ExampleKind = enum {
    minimal,
    call_js_from_zig,
    call_zig_from_js,
    serve_folder,
    vfs,
    public_network,
    multi_client,
    chatgpt_api,
    custom_web_server,
    react,
    frameless,
    fancy_window,
    translucent_rounded,
    text_editor,
    minimal_oop,
    call_js_oop,
    call_oop_from_js,
    serve_folder_oop,
    vfs_oop,
};

pub const rpc_methods = struct {
    pub fn ping() []const u8 {
        return "pong";
    }

    pub fn add(a: i64, b: i64) i64 {
        return a + b;
    }

    pub fn word_count(text: []const u8) i64 {
        var count: i64 = 0;
        var in_word = false;
        for (text) |ch| {
            const ws = ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
            if (ws) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                count += 1;
            }
        }
        return count;
    }

    pub fn echo(text: []const u8) []const u8 {
        return text;
    }

    pub fn save_note(_: []const u8) []const u8 {
        return "saved";
    }
};

pub fn runExample(comptime kind: ExampleKind, comptime RpcMethods: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const app_options = appOptionsFor(kind);

    var service = try webui.Service.init(allocator, RpcMethods, .{
        .app = app_options,
        .window = .{
            .title = titleFor(kind),
            .style = styleFor(kind),
        },
        .rpc = .{
            .dispatcher_mode = .threaded,
            .threaded_poll_interval_ns = 500 * std.time.ns_per_us,
        },
    });
    defer service.deinit();

    webui.process_signals.install();

    service.onEvent(onEventLog, null);
    service.onRaw(onRawLog, null);

    const html = try htmlFor(allocator, kind);
    defer allocator.free(html);

    const bridge = service.rpcClientScript(.{});
    std.debug.print("[{s}] bridge bytes: {d}\n", .{ tagFor(kind), bridge.len });

    try service.showHtml(html);
    try service.run();

    if (kind == .call_js_from_zig or kind == .call_js_oop) {
        try service.runScript(
            \\const status = document.getElementById("status");
            \\if (status) status.textContent = "Updated by Zig runScript()";
        ,
            .{},
        );
    }

    const browser_mode = std.mem.eql(u8, webui.BuildFlags.run_mode, "browser");
    std.debug.print("[{s}] {s} mode active\n", .{ tagFor(kind), if (browser_mode) "browser" else "native webview" });

    const exit_ms = parseExitMs();
    if (exit_ms) |_| {
        // In CI/local automation we auto-exit after N ms.
    } else {
        std.debug.print("[{s}] running. Press Ctrl+C to stop.\n", .{tagFor(kind)});
    }

    const start_ms = std.time.milliTimestamp();
    while (!service.shouldExit()) {
        if (webui.process_signals.stopRequested()) {
            const sig = webui.process_signals.caughtSignal();
            std.debug.print("[{s}] signal received ({d}), shutting down\n", .{ tagFor(kind), sig });
            service.shutdown();
            webui.process_signals.terminateProcess();
        }

        if (exit_ms) |ms| {
            const now_ms = std.time.milliTimestamp();
            if (now_ms - start_ms >= @as(i64, @intCast(ms))) {
                service.shutdown();
                break;
            }
        }

        std.Thread.sleep(20 * std.time.ns_per_ms);
    }

    service.shutdown();
}

fn onEventLog(_: ?*anyopaque, event: *const webui.Event) void {
    std.debug.print("[event][window={d}] kind={s} name={s} payload={s}\n", .{ event.window_id, @tagName(event.kind), event.name, event.payload });
}

fn onRawLog(_: ?*anyopaque, bytes: []const u8) void {
    std.debug.print("[raw] {d} bytes\n", .{bytes.len});
}

fn parseExitMs() ?u64 {
    const raw = std.process.getEnvVarOwned(std.heap.page_allocator, "WEBUI_EXAMPLE_EXIT_MS") catch return null;
    defer std.heap.page_allocator.free(raw);
    return std.fmt.parseInt(u64, raw, 10) catch null;
}

fn titleFor(comptime kind: ExampleKind) []const u8 {
    return switch (kind) {
        .minimal => "minimal",
        .call_js_from_zig => "call_js_from_zig",
        .call_zig_from_js => "call_zig_from_js",
        .serve_folder => "serve_folder",
        .vfs => "virtual_file_system",
        .public_network => "public_network_access",
        .multi_client => "web_app_multi_client",
        .chatgpt_api => "chatgpt_api",
        .custom_web_server => "custom_web_server",
        .react => "react",
        .frameless => "frameless",
        .fancy_window => "fancy_window",
        .translucent_rounded => "translucent_rounded",
        .text_editor => "text_editor",
        .minimal_oop => "minimal_oop",
        .call_js_oop => "call_js_oop",
        .call_oop_from_js => "call_oop_from_js",
        .serve_folder_oop => "serve_folder_oop",
        .vfs_oop => "vfs_oop",
    };
}

fn tagFor(comptime kind: ExampleKind) []const u8 {
    return titleFor(kind);
}

fn appOptionsFor(comptime kind: ExampleKind) webui.AppOptions {
    const browser_mode = std.mem.eql(u8, webui.BuildFlags.run_mode, "browser");
    return .{
        .launch_policy = if (browser_mode)
            .{
                .preferred_transport = .browser,
                .fallback_transport = .browser,
                .browser_open_mode = .on_browser_transport,
                .allow_dual_surface = false,
                .app_mode_required = false,
            }
        else
            .{
                .preferred_transport = .native_webview,
                .fallback_transport = .none,
                .browser_open_mode = .on_browser_transport,
                .allow_dual_surface = false,
                .app_mode_required = true,
            },
        .enable_tls = webui.BuildFlags.enable_tls,
        .enable_webui_log = true,
        .public_network = kind == .public_network,
        .browser_launch = .{
            .require_app_mode_window = !browser_mode,
            .allow_system_fallback = browser_mode,
        },
        .window_fallback_emulation = browser_mode,
    };
}

fn styleFor(comptime kind: ExampleKind) webui.WindowStyle {
    return switch (kind) {
        .frameless => .{
            .frameless = true,
            .transparent = true,
            .corner_radius = 10,
            .resizable = true,
        },
        .fancy_window => .{
            .frameless = true,
            .transparent = true,
            .corner_radius = 12,
            .resizable = true,
            .center = true,
        },
        .translucent_rounded => .{
            .frameless = true,
            .transparent = true,
            .corner_radius = 20,
            .resizable = true,
            .center = true,
            .size = .{ .width = 980, .height = 660 },
            .min_size = .{ .width = 720, .height = 500 },
        },
        else => .{ .resizable = true, .center = true },
    };
}

fn htmlFor(allocator: std.mem.Allocator, comptime kind: ExampleKind) ![]u8 {
    return switch (kind) {
        .frameless => allocator.dupe(u8, HTML_FRAMELESS),
        .fancy_window => allocator.dupe(u8, HTML_FANCY_WINDOW),
        .translucent_rounded => allocator.dupe(u8, HTML_TRANSLUCENT_ROUNDED),
        .text_editor => allocator.dupe(u8, HTML_TEXT_EDITOR),
        else => genericHtml(allocator, kind, titleFor(kind), subtitleFor(kind)),
    };
}

fn subtitleFor(comptime kind: ExampleKind) []const u8 {
    return switch (kind) {
        .minimal, .minimal_oop => "Hello from Zig WebUI runtime",
        .call_js_from_zig, .call_js_oop => "JS bridge is loaded and ready",
        .call_zig_from_js, .call_oop_from_js => "Call Zig functions from browser JS",
        .serve_folder, .serve_folder_oop => "Folder-serving semantics with RPC bridge",
        .vfs, .vfs_oop => "Virtual file system style app",
        .public_network => "Public network access mode enabled",
        .multi_client => "Multi-client semantics demo",
        .chatgpt_api => "Chat-style RPC demo",
        .custom_web_server => "Custom web server interop demo",
        .react => "React-like component interaction",
        else => "Window style and control demo",
    };
}

fn genericHtml(allocator: std.mem.Allocator, comptime kind: ExampleKind, title: []const u8, subtitle: []const u8) ![]u8 {
    return std.mem.concat(allocator, u8, &.{
        "<!doctype html><html><head><meta charset=\"utf-8\"/><title>",
        title,
        "</title><script type=\"module\" src=\"/webui_bridge.js\"></script><style>",
        "*{box-sizing:border-box}html,body{height:100%;margin:0;overflow:hidden}",
        "body{font-family:'Segoe UI',Tahoma,sans-serif;background:#0c1220;color:#e9eef8}",
        ".shell{height:100%;display:flex;flex-direction:column}",
        ".bar{height:44px;display:flex;align-items:center;justify-content:space-between;padding:0 14px;background:#121a2d;-webkit-app-region:drag;--webui-app-region:drag}",
        ".controls{display:flex;gap:8px;-webkit-app-region:no-drag;--webui-app-region:no-drag}",
        ".dot{width:12px;height:12px;border:0;cursor:pointer}.r{background:#ff5f57}.y{background:#febc2e}.g{background:#28c840}",
        ".content{padding:20px;overflow:auto;flex:1}",
        ".hint{opacity:.82;margin:0 0 12px}",
        "button,input,textarea,pre{font:inherit}button{padding:10px 14px;border:0;background:#3fb2ff;color:#081421;font-weight:700;cursor:pointer}",
        "textarea{width:100%;min-height:120px;padding:10px;background:#111b30;color:#e9eef8;border:0}",
        "pre{margin:12px 0 0;min-height:92px;max-height:220px;overflow:auto;padding:12px;background:#10182b}",
        "</style></head><body><div class=\"shell\"><div class=\"bar\"><strong>",
        title,
        "</strong><div class=\"controls\"><button class=\"dot y\" id=\"min\" title=\"Minimize\"></button><button class=\"dot g\" id=\"max\" title=\"Maximize\"></button><button class=\"dot r\" id=\"close\" title=\"Close\"></button></div></div><div class=\"content\"><h2>",
        title,
        "</h2><p id=\"status\">",
        subtitle,
        "</p><p class=\"hint\">",
        hintFor(kind),
        "</p><div style=\"display:flex;gap:10px;flex-wrap:wrap;margin:12px 0\"><button id=\"ping\">Ping</button><button id=\"sum\">Compute 100 + 23</button>",
        extraButtonsFor(kind),
        "</div><textarea id=\"msg\">",
        defaultMessageFor(kind),
        title,
        "</textarea><div style=\"margin-top:10px\"><button id=\"echo\">Echo</button></div><pre id=\"out\"></pre></div></div><script>",
        COMMON_SCRIPT,
        "</script></body></html>",
    });
}

fn hintFor(comptime kind: ExampleKind) []const u8 {
    return switch (kind) {
        .minimal, .minimal_oop => "Minimal startup path with typed RPC ping/add.",
        .call_js_from_zig, .call_js_oop => "Backend will run a post-show script to update the status text.",
        .call_zig_from_js, .call_oop_from_js => "Use JS buttons to invoke Zig methods with typed args.",
        .serve_folder, .serve_folder_oop => "Folder-like flow with save and word-count actions.",
        .vfs, .vfs_oop => "Virtual filesystem-like flow with note save + content analysis.",
        .public_network => "Public listen policy enabled for LAN testing.",
        .multi_client => "Open multiple clients and verify independent RPC sessions.",
        .chatgpt_api => "RPC transport pattern suitable for chat-like workflows.",
        .custom_web_server => "Custom server integration shape with bridge-compatible routes.",
        .react => "Component-style RPC calls using the generated bridge contract.",
        else => "Window style/control and transport demo.",
    };
}

fn extraButtonsFor(comptime kind: ExampleKind) []const u8 {
    return switch (kind) {
        .call_zig_from_js, .call_oop_from_js, .serve_folder, .serve_folder_oop, .vfs, .vfs_oop, .multi_client => "<button id=\"wc\">Word Count</button>",
        .chatgpt_api, .custom_web_server, .react, .public_network => "<button id=\"wc\">Word Count</button><button id=\"save\">Save Note</button>",
        else => "",
    };
}

fn defaultMessageFor(comptime kind: ExampleKind) []const u8 {
    return switch (kind) {
        .minimal, .minimal_oop => "Hello from ",
        .call_js_from_zig, .call_js_oop => "Script update target: ",
        .call_zig_from_js, .call_oop_from_js => "Type text and run word_count on it: ",
        .serve_folder, .serve_folder_oop => "Folder demo content: ",
        .vfs, .vfs_oop => "VFS demo content: ",
        .public_network => "Network-visible demo payload: ",
        .multi_client => "Client-local payload (open in multiple windows): ",
        .chatgpt_api => "Chat-like payload: ",
        .custom_web_server => "Custom-server payload: ",
        .react => "Component state payload: ",
        else => "Hello from ",
    };
}

const COMMON_SCRIPT =
    "const out=document.getElementById('out');const status=document.getElementById('status');" ++
    "async function control(cmd){try{if(globalThis.__webuiWindowControl){const r=await globalThis.__webuiWindowControl(cmd);if(cmd==='close')return;r&&r.warning&&(out.textContent='warning: '+r.warning);return;}}catch(e){out.textContent='control '+cmd+' failed: '+e;}}" ++
    "document.getElementById('min')?.addEventListener('click',()=>control('minimize'));" ++
    "document.getElementById('max')?.addEventListener('click',()=>control(document.fullscreenElement?'restore':'maximize'));" ++
    "document.getElementById('close')?.addEventListener('click',()=>control('close'));" ++
    "document.getElementById('ping')?.addEventListener('click',async()=>{try{out.textContent='ping => '+await webuiRpc.ping();}catch(e){out.textContent='ping failed: '+e;}});" ++
    "document.getElementById('sum')?.addEventListener('click',async()=>{try{out.textContent='add(100,23) => '+await webuiRpc.add(100,23);}catch(e){out.textContent='add failed: '+e;}});" ++
    "document.getElementById('wc')?.addEventListener('click',async()=>{try{const msg=document.getElementById('msg')?.value||'';out.textContent='word_count => '+await webuiRpc.word_count(msg);}catch(e){out.textContent='word_count failed: '+e;}});" ++
    "document.getElementById('save')?.addEventListener('click',async()=>{try{const msg=document.getElementById('msg')?.value||'';out.textContent='save_note => '+await webuiRpc.save_note(msg);}catch(e){out.textContent='save_note failed: '+e;}});" ++
    "document.getElementById('echo')?.addEventListener('click',async()=>{try{const msg=document.getElementById('msg')?.value||'';out.textContent='echo => '+await webuiRpc.echo(msg);}catch(e){out.textContent='echo failed: '+e;}});" ++
    "(async()=>{try{status.textContent='Backend: '+await webuiRpc.ping();}catch(e){status.textContent='Backend unavailable: '+e;}})();";

const HTML_FRAMELESS =
    "<!doctype html><html><head><meta charset=\"utf-8\"/><title>Frameless</title><script type=\"module\" src=\"/webui_bridge.js\"></script>" ++
    "<style>*{box-sizing:border-box}html,body{height:100%;margin:0;overflow:hidden}body{font-family:'Segoe UI',sans-serif;background:transparent;color:#f5f5f5}" ++
    ".shell{height:100%;width:100%;background:rgba(24,24,28,.94);display:flex;flex-direction:column;overflow:hidden;backdrop-filter:blur(20px)}" ++
    ".title{height:44px;display:flex;align-items:center;justify-content:space-between;padding:0 14px;background:rgba(0,0,0,.25);-webkit-app-region:drag;--webui-app-region:drag}" ++
    ".dots{display:flex;gap:8px;-webkit-app-region:no-drag;--webui-app-region:no-drag}.dot{width:12px;height:12px;border:0;cursor:pointer}.min{background:#ffbd2e}.max{background:#28c840}.close{background:#ff5f57}" ++
    ".content{flex:1;padding:18px;overflow:auto}</style></head><body><div class=\"shell\"><div class=\"title\"><strong>Frameless Example</strong><div class=\"dots\"><button class=\"dot min\" id=\"min\"></button><button class=\"dot max\" id=\"max\"></button><button class=\"dot close\" id=\"close\"></button></div></div><div class=\"content\"><h2>Frameless</h2><p id=\"status\">Loading...</p><button id=\"ping\">Ping</button><button id=\"sum\">Compute 100 + 23</button><textarea id=\"msg\">Hello frameless</textarea><button id=\"echo\">Echo</button><pre id=\"out\"></pre></div></div><script>" ++ COMMON_SCRIPT ++ "</script></body></html>";

const HTML_FANCY_WINDOW =
    "<!doctype html><html><head><meta charset=\"utf-8\"/><title>Fancy Window</title><script type=\"module\" src=\"/webui_bridge.js\"></script>" ++
    "<style>*{box-sizing:border-box}html,body{height:100%;margin:0;overflow:hidden}body{font-family:'Segoe UI',Tahoma,sans-serif;background:radial-gradient(circle at top right,#23395f,#0b1220 60%);color:#e7ecf7}" ++
    ".shell{height:100%;display:flex}.window{width:100%;height:100%;display:flex;flex-direction:column;overflow:hidden;box-shadow:0 18px 60px rgba(0,0,0,.45)}" ++
    ".bar{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;background:rgba(7,12,23,.88);backdrop-filter:blur(8px);-webkit-app-region:drag;--webui-app-region:drag}" ++
    ".dots{display:flex;gap:8px;-webkit-app-region:no-drag;--webui-app-region:no-drag}.dot{width:12px;height:12px;border:0;cursor:pointer}.r{background:#ff5f57}.y{background:#febc2e}.g{background:#28c840}" ++
    ".content{padding:22px;overflow:auto;flex:1}button{padding:10px 14px;border:0;background:#53d3ff;color:#041120;font-weight:700;cursor:pointer}textarea{width:100%;min-height:120px;background:#0f1728;color:#e7ecf7;border:0;padding:12px}pre{background:#0f1728;padding:12px;min-height:90px}</style>" ++
    "</head><body><div class=\"shell\"><div class=\"window\"><div class=\"bar\"><div class=\"dots\"><button class=\"dot r\" id=\"close\"></button><button class=\"dot y\" id=\"min\"></button><button class=\"dot g\" id=\"max\"></button></div><strong>Fancy Window Example</strong></div><div class=\"content\"><h2>Polished Window UX</h2><p id=\"status\">Loading...</p><button id=\"ping\">Ping</button> <button id=\"sum\">Compute 100 + 23</button><textarea id=\"msg\">Hello from fancy window</textarea><button id=\"echo\">Echo</button><pre id=\"out\"></pre></div></div></div><script>" ++ COMMON_SCRIPT ++ "</script></body></html>";

const HTML_TRANSLUCENT_ROUNDED =
    "<!doctype html><html><head><meta charset=\"utf-8\"/><title>Translucent Rounded</title><script type=\"module\" src=\"/webui_bridge.js\"></script>" ++
    "<style>*{box-sizing:border-box}html,body{height:100%;margin:0;overflow:hidden}body{font-family:'Segoe UI',Tahoma,sans-serif;background:transparent;color:#edf3ff}" ++
    ".stage{height:100%;width:100%;padding:0}.glass{height:100%;width:100%;overflow:hidden;background:linear-gradient(180deg,rgba(7,12,20,.88),rgba(9,15,25,.78));box-shadow:0 26px 70px rgba(2,7,14,.62);backdrop-filter:blur(14px);display:flex;flex-direction:column}" ++
    ".bar{height:48px;display:flex;align-items:center;justify-content:space-between;padding:0 14px;background:rgba(5,10,18,.72);-webkit-app-region:drag;--webui-app-region:drag}" ++
    ".controls{display:flex;gap:8px;-webkit-app-region:no-drag;--webui-app-region:no-drag}.control{width:12px;height:12px;border:0;padding:0;cursor:pointer}.close{background:#ff5f57}.min{background:#febc2e}.max{background:#28c840}" ++
    ".content{flex:1;min-height:0;padding:22px;overflow:auto;-webkit-app-region:no-drag;--webui-app-region:no-drag}button{padding:10px 14px;background:rgba(28,40,58,.84);color:#f7fbff;border:0;font-weight:700;cursor:pointer}textarea{width:100%;min-height:120px;padding:12px;background:rgba(7,12,22,.74);color:#edf3ff;border:0}pre{min-height:92px;max-height:180px;overflow:auto;padding:12px;background:rgba(7,12,22,.78)}</style>" ++
    "</head><body><div class=\"stage\"><div class=\"glass\"><div class=\"bar\"><div class=\"controls\"><button class=\"control close\" id=\"close\"></button><button class=\"control min\" id=\"min\"></button><button class=\"control max\" id=\"max\"></button></div><div><strong>Translucent Rounded Window</strong></div></div><div class=\"content\"><h2>Cross-platform Glass UI</h2><p id=\"status\">Loading...</p><button id=\"ping\">Ping</button> <button id=\"sum\">Compute 100 + 23</button><textarea id=\"msg\">Semi-transparent and native rounded.</textarea><button id=\"echo\">Echo</button><pre id=\"out\"></pre></div></div></div><script>" ++ COMMON_SCRIPT ++ "</script></body></html>";

const HTML_TEXT_EDITOR =
    "<!doctype html><html><head><meta charset=\"utf-8\"/><title>Text Editor</title><script type=\"module\" src=\"/webui_bridge.js\"></script>" ++
    "<style>*{box-sizing:border-box}body{font-family:Arial;background:#0f141a;color:#eee;padding:20px;margin:0}textarea{width:100%;min-height:260px}button{margin-top:8px;padding:8px 12px;border:0;background:#53d3ff;color:#06213a;font-weight:700;cursor:pointer}pre{min-height:90px;background:#111b2a;padding:10px}</style></head>" ++
    "<body><h3>Text Editor Example</h3><p id=\"status\">Checking backend...</p><textarea id=\"msg\" placeholder=\"Type...\"></textarea><br/><button id=\"stats\">Word Count</button><button id=\"save\">Save</button><pre id=\"out\"></pre><script>const st=document.getElementById('status');const out=document.getElementById('out');(async()=>{try{st.textContent='Backend: '+await webuiRpc.ping();}catch(e){st.textContent='Backend unavailable: '+e;}})();document.getElementById('stats').onclick=async()=>{out.textContent='words => '+await webuiRpc.word_count(document.getElementById('msg').value);};document.getElementById('save').onclick=async()=>{out.textContent='save => '+await webuiRpc.save_note(document.getElementById('msg').value);};</script></body></html>";
