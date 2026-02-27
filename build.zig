const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;

const Example = struct {
    selector: ExampleChoice,
    artifact_name: []const u8,
    source_path: []const u8,
};

const ExampleChoice = enum {
    all,
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

const examples = [_]Example{
    .{
        .selector = .minimal,
        .artifact_name = "minimal_zig",
        .source_path = "examples/C/minimal/main.zig",
    },
    .{
        .selector = .call_js_from_zig,
        .artifact_name = "call_js_from_zig",
        .source_path = "examples/C/call_js_from_c/main.zig",
    },
    .{
        .selector = .call_zig_from_js,
        .artifact_name = "call_zig_from_js",
        .source_path = "examples/C/call_c_from_js/main.zig",
    },
    .{
        .selector = .serve_folder,
        .artifact_name = "serve_folder_zig",
        .source_path = "examples/C/serve_a_folder/main.zig",
    },
    .{
        .selector = .vfs,
        .artifact_name = "vfs_zig",
        .source_path = "examples/C/virtual_file_system/main.zig",
    },
    .{
        .selector = .public_network,
        .artifact_name = "public_network_access_zig",
        .source_path = "examples/C/public_network_access/main.zig",
    },
    .{
        .selector = .multi_client,
        .artifact_name = "multi_client_zig",
        .source_path = "examples/C/web_app_multi_client/main.zig",
    },
    .{
        .selector = .chatgpt_api,
        .artifact_name = "chatgpt_api_zig",
        .source_path = "examples/C/chatgpt_api/main.zig",
    },
    .{
        .selector = .custom_web_server,
        .artifact_name = "custom_web_server_zig",
        .source_path = "examples/C/custom_web_server/main.zig",
    },
    .{
        .selector = .react,
        .artifact_name = "react_zig",
        .source_path = "examples/C/react/main.zig",
    },
    .{
        .selector = .frameless,
        .artifact_name = "frameless_zig",
        .source_path = "examples/C/frameless/main.zig",
    },
    .{
        .selector = .fancy_window,
        .artifact_name = "fancy_window_zig",
        .source_path = "examples/C/fancy_window/main.zig",
    },
    .{
        .selector = .translucent_rounded,
        .artifact_name = "translucent_rounded_zig",
        .source_path = "examples/C/translucent_rounded/main.zig",
    },
    .{
        .selector = .text_editor,
        .artifact_name = "text_editor_zig",
        .source_path = "examples/C/text-editor/main.zig",
    },
    .{
        .selector = .minimal_oop,
        .artifact_name = "minimal_oop_zig",
        .source_path = "examples/C++/minimal/main.zig",
    },
    .{
        .selector = .call_js_oop,
        .artifact_name = "call_js_oop_zig",
        .source_path = "examples/C++/call_js_from_cpp/main.zig",
    },
    .{
        .selector = .call_oop_from_js,
        .artifact_name = "call_oop_from_js_zig",
        .source_path = "examples/C++/call_cpp_from_js/main.zig",
    },
    .{
        .selector = .serve_folder_oop,
        .artifact_name = "serve_folder_oop_zig",
        .source_path = "examples/C++/serve_a_folder/main.zig",
    },
    .{
        .selector = .vfs_oop,
        .artifact_name = "vfs_oop_zig",
        .source_path = "examples/C++/virtual_file_system/main.zig",
    },
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_dynamic = b.option(bool, "dynamic", "Build a dynamic library") orelse false;
    const enable_tls = b.option(bool, "enable-tls", "Enable TLS support in runtime options") orelse false;
    const enable_webui_log = b.option(bool, "enable-webui-log", "Enable runtime log defaults") orelse false;
    const minify_embedded_js = b.option(bool, "minify-embedded-js", "Minify embedded JS helpers with pure Zig asset processing (default: true)") orelse true;
    const minify_written_js = b.option(bool, "minify-written-js", "Minify written JS helper assets with pure Zig asset processing (default: false)") orelse false;
    const selected_example = b.option(ExampleChoice, "example", "Example to run with `zig build run` (default: all)") orelse .all;
    const run_mode = b.option([]const u8, "run-mode", "Runtime launch order for examples. Presets: `webview`, `browser` (app-window), `web-tab`, `web-url`. Or ordered tokens (`webview,browser,web-url`, `browser,webview`, etc). Default: webview,browser,web-url") orelse "webview,browser,web-url";
    if (!isValidRunMode(run_mode)) {
        @panic("invalid -Drun-mode value: use `webview`, `browser`, `web-tab`, `web-url`, or an ordered comma-separated combination");
    }

    const runtime_helpers_assets = prepareRuntimeHelpersAssets(b, optimize, minify_embedded_js, minify_written_js);

    const build_opts = b.addOptions();
    build_opts.addOption(bool, "dynamic", is_dynamic);
    build_opts.addOption(bool, "enable_tls", enable_tls);
    build_opts.addOption(bool, "enable_webui_log", enable_webui_log);
    build_opts.addOption([]const u8, "run_mode", run_mode);
    build_opts.addOption([]const u8, "runtime_helpers_embed_path", runtime_helpers_assets.embed_path);
    build_opts.addOption([]const u8, "runtime_helpers_written_path", runtime_helpers_assets.written_path);

    const websocket_dep = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });
    const websocket_mod = websocket_dep.module("websocket");
    const websocket_build_opts = b.addOptions();
    websocket_build_opts.addOption(bool, "websocket_blocking", false);
    websocket_mod.addOptions("build", websocket_build_opts);

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    lib_module.addOptions("build_options", build_opts);
    lib_module.addImport("websocket", websocket_mod);

    const webui_lib = b.addLibrary(.{
        .name = "webui",
        .linkage = if (is_dynamic) .dynamic else .static,
        .root_module = lib_module,
    });
    webui_lib.step.dependOn(runtime_helpers_assets.prepare_step);
    b.installArtifact(webui_lib);

    const webui_mod = b.addModule("webui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    webui_mod.addOptions("build_options", build_opts);
    webui_mod.addImport("websocket", websocket_mod);

    const example_shared_source_path = "examples/shared/demo_runner.zig";
    const example_shared_mod: ?*Build.Module = if (pathExists(example_shared_source_path)) b.addModule("example_shared", .{
        .root_source_file = b.path(example_shared_source_path),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .imports = &.{
            .{ .name = "webui", .module = webui_mod },
        },
    }) else null;

    const exe = b.addExecutable(.{
        .name = "webui-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
            .imports = &.{
                .{ .name = "webui", .module = webui_mod },
            },
        }),
    });
    exe.step.dependOn(runtime_helpers_assets.prepare_step);
    exe.linkLibrary(webui_lib);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run Zig examples (default: all, override with -Dexample=<name>)");
    var linux_webview_host_install_step: ?*Build.Step = null;
    var linux_browser_host_install_step: ?*Build.Step = null;

    if (target.result.os.tag == .linux) {
        const host = b.addExecutable(.{
            .name = "webui_linux_webview_host",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/linux_webview_host.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        host.linkSystemLibrary("gtk-3");
        host.linkSystemLibrary("webkit2gtk-4.1");

        const host_install = b.addInstallArtifact(host, .{});
        linux_webview_host_install_step = &host_install.step;
        run_step.dependOn(&host_install.step);

        const browser_host = b.addExecutable(.{
            .name = "webui_linux_browser_host",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/linux_browser_host.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = false,
            }),
        });
        const browser_host_install = b.addInstallArtifact(browser_host, .{});
        linux_browser_host_install_step = &browser_host_install.step;
        run_step.dependOn(&browser_host_install.step);
    }

    const bridge_template_mod = b.createModule(.{
        .root_source_file = b.path("src/bridge/template.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .link_libc = false,
    });
    bridge_template_mod.addOptions("build_options", build_opts);
    const bridge_gen_mod = b.createModule(.{
        .root_source_file = b.path("tools/bridge_gen.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .link_libc = false,
        .imports = &.{
            .{ .name = "bridge_template", .module = bridge_template_mod },
        },
    });
    const bridge_gen = b.addExecutable(.{
        .name = "bridge_gen",
        .root_module = bridge_gen_mod,
    });
    bridge_gen.step.dependOn(runtime_helpers_assets.prepare_step);
    const run_bridge_gen = b.addRunArtifact(bridge_gen);
    run_bridge_gen.addArg("zig-out/share/webui/webui_bridge.js");
    run_bridge_gen.addArg("ping");
    run_bridge_gen.addArg("zig-out/share/webui/webui_bridge.d.ts");
    const bridge_step = b.step("bridge", "Generate the default JavaScript bridge asset");
    bridge_step.dependOn(&run_bridge_gen.step);
    b.getInstallStep().dependOn(&run_bridge_gen.step);

    const vfs_gen = b.addExecutable(.{
        .name = "vfs_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/vfs_gen.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = false,
        }),
    });
    const run_vfs_gen = b.addRunArtifact(vfs_gen);
    run_vfs_gen.addArg("examples/C/serve_a_folder/index.html");
    run_vfs_gen.addArg("zig-out/share/webui/generated_vfs_index.zig");
    const vfs_step = b.step("vfs-gen", "Generate embedded VFS Zig source from example assets");
    vfs_step.dependOn(&run_vfs_gen.step);

    const examples_step = b.step("examples", "Build all Zig ported examples");
    var selected_example_found = selected_example == .all;
    if (example_shared_mod) |shared_mod| {
        for (examples) |example| {
            if (!pathExists(example.source_path)) continue;

            const built = addExample(b, example, webui_mod, shared_mod, webui_lib, target, optimize, runtime_helpers_assets.prepare_step);
            examples_step.dependOn(built.install_step);
            if (linux_webview_host_install_step) |host_install| built.run_step.dependOn(host_install);
            if (linux_browser_host_install_step) |host_install| built.run_step.dependOn(host_install);

            if (selected_example == .all or selected_example == example.selector) {
                selected_example_found = true;
                if (selected_example == .all) {
                    built.run_cmd.setEnvironmentVariable("WEBUI_EXAMPLE_EXIT_MS", "1800");
                }
                run_step.dependOn(built.run_step);
                if (selected_example != .all) {
                    if (b.args) |args| {
                        built.run_cmd.addArgs(args);
                    }
                }
            }
        }
    }

    if (!selected_example_found) {
        const fail = b.addFail(b.fmt(
            "selected example '{s}' is unavailable in this checkout",
            .{@tagName(selected_example)},
        ));
        run_step.dependOn(&fail.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root/tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
            .imports = &.{
                .{ .name = "webui", .module = webui_mod },
            },
        }),
    });
    mod_tests.step.dependOn(runtime_helpers_assets.prepare_step);
    mod_tests.linkLibrary(webui_lib);
    const run_mod_tests = b.addRunArtifact(mod_tests);

    var run_example_shared_tests_step: ?*Build.Step = null;
    if (example_shared_mod) |shared_mod| {
        const example_shared_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(example_shared_source_path),
                .target = target,
                .optimize = optimize,
                .link_libc = false,
                .imports = &.{
                    .{ .name = "webui", .module = webui_mod },
                    .{ .name = "example_shared", .module = shared_mod },
                },
            }),
        });
        example_shared_tests.step.dependOn(runtime_helpers_assets.prepare_step);
        example_shared_tests.linkLibrary(webui_lib);
        const run_example_shared_tests = b.addRunArtifact(example_shared_tests);
        run_example_shared_tests_step = &run_example_shared_tests.step;
    }

    const test_step = b.step("test", "Run Zig tests");
    test_step.dependOn(&run_mod_tests.step);
    if (run_example_shared_tests_step) |step| {
        test_step.dependOn(step);
    }

    const dispatcher_stress_tests = b.addTest(.{
        .root_module = webui_mod,
        .filters = &.{"threaded dispatcher stress"},
    });
    dispatcher_stress_tests.step.dependOn(runtime_helpers_assets.prepare_step);
    dispatcher_stress_tests.linkLibrary(webui_lib);

    const dispatcher_stress_step = b.step("dispatcher-stress", "Stress threaded dispatcher concurrency/lifetime paths");
    var stress_iter: usize = 0;
    while (stress_iter < 8) : (stress_iter += 1) {
        const run_stress = b.addRunArtifact(dispatcher_stress_tests);
        dispatcher_stress_step.dependOn(&run_stress.step);
    }

    const parity_report_tool = b.addExecutable(.{
        .name = "parity_report",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/parity_report.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = false,
        }),
    });
    const run_parity_report = b.addRunArtifact(parity_report_tool);
    run_parity_report.addArg("parity/features.json");
    run_parity_report.addArg("parity/status.json");
    const parity_report_step = b.step("parity-report", "Generate and validate feature parity report");
    parity_report_step.dependOn(&run_parity_report.step);

    const guards = b.addSystemCommand(&.{
        "bash",
        "-lc",
        \\set -euo pipefail
        \\if rg -n "@cImport" src tools examples >/dev/null 2>&1; then
        \\  echo "static-guard failed: found @cImport in active sources" >&2
        \\  exit 1
        \\fi
        \\if rg -n "addCSourceFile" src tools examples >/dev/null 2>&1; then
        \\  echo "static-guard failed: found addCSourceFile in active sources" >&2
        \\  exit 1
        \\fi
        \\if rg -n "translate-c|std\\.zig\\.c_translation|src/translated" src tools examples >/dev/null 2>&1; then
        \\  echo "static-guard failed: found translate-c artifacts in active sources" >&2
        \\  exit 1
        \\fi
        \\if rg -n "linkLibC\\(|std\\.c\\.|c_allocator" src tools examples >/dev/null 2>&1; then
        \\  echo "static-guard failed: found active libc linkage or std.c usage" >&2
        \\  exit 1
        \\fi
        \\if rg -n "zig\",\\s*\"cc\"|build_jsmin|tools/jsmin/jsmin\\.c" build.zig | rg -v "guard-ignore-build-c-scan" >/dev/null 2>&1; then
        \\  echo "static-guard failed: found build-time C compilation path" >&2
        \\  exit 1
        \\fi # guard-ignore-build-c-scan
    });

    const parity_step = b.step("parity-local", "Run local parity checks (tests + examples + static guards)");
    parity_step.dependOn(&run_mod_tests.step);
    if (run_example_shared_tests_step) |step| {
        parity_step.dependOn(step);
    }
    parity_step.dependOn(examples_step);
    parity_step.dependOn(parity_report_step);
    parity_step.dependOn(&guards.step);

    const os_matrix = b.step("os-matrix", "Compile OS support matrix for Linux/macOS/Windows (static + dynamic + examples)");
    const matrix_commands = [_][]const []const u8{
        &.{ "zig", "build" },
        &.{ "zig", "build", "-Ddynamic=true" },
        &.{ "zig", "build", "-Denable-tls=true" },
        &.{ "zig", "build", "-Denable-webui-log=true" },
        &.{ "zig", "build", "-Dtarget=x86_64-windows" },
        &.{ "zig", "build", "-Ddynamic=true", "-Dtarget=x86_64-windows" },
        &.{ "zig", "build", "-Dtarget=aarch64-macos" },
        &.{ "zig", "build", "-Ddynamic=true", "-Dtarget=aarch64-macos" },
        &.{ "zig", "build", "examples" },
        &.{ "zig", "build", "examples", "-Ddynamic=true" },
        &.{ "zig", "build", "examples", "-Dtarget=x86_64-windows" },
        &.{ "zig", "build", "examples", "-Ddynamic=true", "-Dtarget=x86_64-windows" },
        &.{ "zig", "build", "examples", "-Dtarget=aarch64-macos" },
        &.{ "zig", "build", "examples", "-Ddynamic=true", "-Dtarget=aarch64-macos" },
    };
    for (matrix_commands) |argv| {
        const cmd = b.addSystemCommand(argv);
        os_matrix.dependOn(&cmd.step);
    }
}

fn addExample(
    b: *Build,
    example: Example,
    webui_mod: *Build.Module,
    example_shared_mod: *Build.Module,
    webui_lib: *Build.Step.Compile,
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
    runtime_helpers_prepare_step: *Build.Step,
) struct {
    install_step: *Build.Step,
    run_step: *Build.Step,
    run_cmd: *Build.Step.Run,
} {
    const exe = b.addExecutable(.{
        .name = example.artifact_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(example.source_path),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
            .imports = &.{
                .{ .name = "webui", .module = webui_mod },
                .{ .name = "example_shared", .module = example_shared_mod },
            },
        }),
    });
    exe.step.dependOn(runtime_helpers_prepare_step);
    exe.linkLibrary(webui_lib);

    const install = b.addInstallArtifact(exe, .{});

    const run_example = b.addRunArtifact(exe);
    run_example.step.dependOn(&install.step);

    return .{
        .install_step = &install.step,
        .run_step = &run_example.step,
        .run_cmd = run_example,
    };
}

const RuntimeHelpersAssets = struct {
    prepare_step: *Build.Step,
    embed_path: []const u8,
    written_path: []const u8,
};

fn prepareRuntimeHelpersAssets(
    b: *Build,
    optimize: OptimizeMode,
    minify_embedded_js: bool,
    minify_written_js: bool,
) RuntimeHelpersAssets {
    const source_path = b.pathFromRoot("src/bridge/runtime_helpers.source.js");
    const embed_rel_path = "generated/runtime_helpers.embed.js";
    const written_rel_path = "generated/runtime_helpers.written.js";
    const embed_out_path = b.pathFromRoot("src/bridge/generated/runtime_helpers.embed.js");
    const written_out_path = b.pathFromRoot("src/bridge/generated/runtime_helpers.written.js");
    const embed_dist_path = b.pathFromRoot("zig-out/share/webui/runtime_helpers.embed.js");
    const written_dist_path = b.pathFromRoot("zig-out/share/webui/runtime_helpers.written.js");

    const js_asset_gen = b.addExecutable(.{
        .name = "js_asset_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/js_asset_gen.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .link_libc = false,
        }),
    });

    const generate_embed = b.addRunArtifact(js_asset_gen);
    generate_embed.addArg(source_path);
    generate_embed.addArg(embed_out_path);
    generate_embed.addArg(if (minify_embedded_js) "1" else "0");

    const generate_written = b.addRunArtifact(js_asset_gen);
    generate_written.addArg(source_path);
    generate_written.addArg(written_out_path);
    generate_written.addArg(if (minify_written_js) "1" else "0");

    const publish_embed = b.addRunArtifact(js_asset_gen);
    publish_embed.addArg(embed_out_path);
    publish_embed.addArg(embed_dist_path);
    publish_embed.addArg("0");
    publish_embed.step.dependOn(&generate_embed.step);

    const publish_written = b.addRunArtifact(js_asset_gen);
    publish_written.addArg(written_out_path);
    publish_written.addArg(written_dist_path);
    publish_written.addArg("0");
    publish_written.step.dependOn(&generate_written.step);

    const prepare = b.step("runtime-helpers", "Prepare runtime helper JS assets (embedded/written)");
    prepare.dependOn(&publish_embed.step);
    prepare.dependOn(&publish_written.step);

    return .{
        .prepare_step = prepare,
        .embed_path = embed_rel_path,
        .written_path = written_rel_path,
    };
}

fn isValidRunMode(mode: []const u8) bool {
    if (std.mem.eql(u8, mode, "webview") or std.mem.eql(u8, mode, "browser") or std.mem.eql(u8, mode, "web-tab") or std.mem.eql(u8, mode, "web-url")) {
        return true;
    }

    var token_count: usize = 0;
    var seen_webview = false;
    var seen_browser_surface = false;
    var seen_web_url = false;

    var it = std.mem.tokenizeAny(u8, mode, ",> ");
    while (it.next()) |raw_token| {
        const token = std.mem.trim(u8, raw_token, " \t\r\n");
        if (token.len == 0) continue;
        token_count += 1;
        if (token_count > 3) return false;

        if (std.mem.eql(u8, token, "webview")) {
            if (seen_webview) return false;
            seen_webview = true;
            continue;
        }
        if (std.mem.eql(u8, token, "browser") or std.mem.eql(u8, token, "web-tab")) {
            if (seen_browser_surface) return false;
            seen_browser_surface = true;
            continue;
        }
        if (std.mem.eql(u8, token, "web-url")) {
            if (seen_web_url) return false;
            seen_web_url = true;
            continue;
        }
        return false;
    }

    return token_count > 0;
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
