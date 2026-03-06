const std = @import("std");

const bridge_template = @import("../bridge/template.zig");
const api_types = @import("api_types.zig");
const rpc_reflect = @import("rpc_reflect.zig");
const rpc_runtime = @import("rpc_runtime.zig");

const BridgeOptions = api_types.BridgeOptions;
const CustomDispatcher = api_types.CustomDispatcher;
const DispatcherMode = api_types.DispatcherMode;
const RpcOptions = api_types.RpcOptions;
const State = rpc_runtime.State;

const buildTsArgSignature = rpc_reflect.buildTsArgSignature;
const tsTypeNameForReturn = rpc_reflect.tsTypeNameForReturn;
const makeInvoker = rpc_reflect.makeInvoker;

/// Registers Zig RPC functions and exposes generated JS/TypeScript bridge artifacts.
pub const RpcRegistry = struct {
    allocator: std.mem.Allocator,
    state: *State,

    /// Registers every public function in `RpcStruct` and refreshes the generated bridge artifacts.
    pub fn register(self: RpcRegistry, comptime RpcStruct: type, options: RpcOptions) !void {
        self.state.bridge_options = options.bridge_options;
        self.state.dispatcher_mode = options.dispatcher_mode;
        self.state.custom_dispatcher = options.custom_dispatcher;
        self.state.custom_context = options.custom_context;
        self.state.threaded_poll_interval_ns = options.threaded_poll_interval_ns;

        if (self.state.dispatcher_mode == .threaded) {
            try self.state.ensureWorkerStarted();
        }

        var registered_count: usize = 0;

        const info = @typeInfo(RpcStruct);
        if (info != .@"struct") return error.InvalidRpcContainer;

        inline for (info.@"struct".decls) |decl| {
            const value = @field(RpcStruct, decl.name);
            switch (@typeInfo(@TypeOf(value))) {
                .@"fn" => {
                    const fn_info = @typeInfo(@TypeOf(value)).@"fn";
                    const ts_arg_signature = try buildTsArgSignature(self.allocator, fn_info.params);
                    defer self.allocator.free(ts_arg_signature);
                    try self.state.addFunction(
                        self.allocator,
                        decl.name,
                        fn_info.params.len,
                        makeInvoker(RpcStruct, decl.name),
                        ts_arg_signature,
                        tsTypeNameForReturn(fn_info.return_type orelse void),
                    );
                    registered_count += 1;
                },
                else => {},
            }
        }

        if (registered_count == 0) return error.NoRpcFunctions;
        try self.refreshGeneratedArtifacts();
    }

    /// Returns the generated JavaScript client bridge for the currently registered RPC surface.
    pub fn generatedClientScript(self: RpcRegistry) []const u8 {
        return self.state.generated_script;
    }

    /// Generates the JavaScript client bridge at comptime for `RpcStruct`.
    pub fn generatedClientScriptComptime(comptime RpcStruct: type, comptime options: BridgeOptions) []const u8 {
        return bridge_template.renderComptime(RpcStruct, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        });
    }

    /// Writes the generated JavaScript client bridge to `output_path`.
    pub fn writeGeneratedClientScript(self: RpcRegistry, output_path: []const u8) !void {
        if (std.fs.path.dirname(output_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        const file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(self.generatedClientScript());
    }

    /// Returns the generated TypeScript declarations for the currently registered RPC surface.
    pub fn generatedTypeScriptDeclarations(self: RpcRegistry) []const u8 {
        return self.state.generated_typescript;
    }

    /// Generates the TypeScript declarations at comptime for `RpcStruct`.
    pub fn generatedTypeScriptDeclarationsComptime(comptime RpcStruct: type, comptime options: BridgeOptions) []const u8 {
        return bridge_template.renderTypeScriptDeclarationsComptime(RpcStruct, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        });
    }

    /// Writes the generated TypeScript declarations to `output_path`.
    pub fn writeGeneratedTypeScriptDeclarations(self: RpcRegistry, output_path: []const u8) !void {
        if (std.fs.path.dirname(output_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        const file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(self.generatedTypeScriptDeclarations());
    }

    /// Rebuilds the generated JavaScript and TypeScript bridge artifacts from the registered RPC handlers.
    fn refreshGeneratedArtifacts(self: RpcRegistry) !void {
        const functions = try self.functionMetas();
        defer self.allocator.free(functions);

        const render_options: bridge_template.RenderOptions = .{
            .namespace = self.state.bridge_options.namespace,
            .rpc_route = self.state.bridge_options.rpc_route,
        };

        const generated_script = try bridge_template.render(self.allocator, render_options, functions);
        errdefer self.allocator.free(generated_script);
        const generated_typescript = try bridge_template.renderTypeScriptDeclarations(self.allocator, render_options, functions);
        errdefer self.allocator.free(generated_typescript);

        self.state.replaceGeneratedArtifacts(self.allocator, generated_script, generated_typescript);
    }

    /// Builds the bridge template metadata for the currently registered RPC handlers.
    fn functionMetas(self: RpcRegistry) ![]bridge_template.RpcFunctionMeta {
        const functions = try self.allocator.alloc(bridge_template.RpcFunctionMeta, self.state.handlers.items.len);
        for (self.state.handlers.items, 0..) |handler, idx| {
            functions[idx] = .{
                .name = handler.name,
                .arity = handler.arity,
                .ts_arg_signature = handler.ts_arg_signature,
                .ts_return_type = handler.ts_return_type,
            };
        }
        return functions;
    }
};
