const runner = @import("example_shared");

pub const rpc_methods = runner.rpc_methods;

pub fn main() !void {
    try runner.runExample(.fancy_window, rpc_methods);
}
