const build_options = @import("build_options");

pub const embedded_runtime_helpers_js = @embedFile(build_options.runtime_helpers_embed_path);
pub const written_runtime_helpers_js = @embedFile(build_options.runtime_helpers_written_path);
