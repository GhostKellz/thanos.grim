//! Thanos Grim Plugin - Native Zig AI integration for Grim editor
//!
//! This plugin provides AI-powered completions and tools directly in Grim
//! using the Thanos orchestration layer.
//!
//! This is a HYBRID plugin: Ghostlang (init.gza) handles UI/commands,
//! while this native code handles performance-critical AI operations.
const std = @import("std");
const thanos = @import("thanos");

// Grim native plugin API types
const NativePluginInfo = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    api_version: u32,
};

const GRIM_PLUGIN_API_VERSION: u32 = 1;

/// Plugin state
pub const ThanosGrimPlugin = struct {
    allocator: std.mem.Allocator,
    thanos_instance: ?*thanos.Thanos = null,
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator) !ThanosGrimPlugin {
        return ThanosGrimPlugin{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ThanosGrimPlugin) void {
        if (self.thanos_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }
    }

    /// Initialize Thanos with default configuration
    pub fn initializeThanos(self: *ThanosGrimPlugin) !void {
        if (self.initialized) return;

        // Try to load config from file, fallback to defaults
        var config = if (std.fs.cwd().access("thanos.toml", .{})) |_|
            thanos.config.loadConfig(self.allocator, "thanos.toml") catch blk: {
                std.debug.print("[Thanos] Failed to load thanos.toml, using defaults\n", .{});
                break :blk thanos.types.Config{
                    .mode = .hybrid,
                    .debug = true,
                    .preferred_provider = .ollama,
                    .fallback_providers = &.{.ollama},
                };
            }
        else |_| thanos.types.Config{
            .mode = .hybrid,
            .debug = true,
            .preferred_provider = .ollama,
            .fallback_providers = &.{.ollama},
        };

        // Initialize task routing
        try config.initTaskRouting(self.allocator);

        const instance = try self.allocator.create(thanos.Thanos);
        instance.* = try thanos.Thanos.init(self.allocator, config);
        self.thanos_instance = instance;
        self.initialized = true;
    }

    /// Complete code at cursor
    pub fn complete(self: *ThanosGrimPlugin, prompt: []const u8, language: ?[]const u8) ![]const u8 {
        if (!self.initialized) try self.initializeThanos();

        const instance = self.thanos_instance orelse return error.NotInitialized;

        const request = thanos.types.CompletionRequest{
            .prompt = prompt,
            .language = language,
            .max_tokens = 100,
        };

        const response = try instance.complete(request);
        // Note: Caller must free this string
        return response.text;
    }

    /// List available providers
    pub fn listProviders(self: *ThanosGrimPlugin) ![]thanos.types.ProviderHealth {
        if (!self.initialized) try self.initializeThanos();

        const instance = self.thanos_instance orelse return error.NotInitialized;
        return instance.listProviders();
    }

    /// Get statistics
    pub fn getStats(self: *ThanosGrimPlugin) !thanos.ThanosStats {
        if (!self.initialized) try self.initializeThanos();

        const instance = self.thanos_instance orelse return error.NotInitialized;
        return instance.getStats();
    }
};

// ============================================================================
// Grim Native Plugin API Exports (required for all native/hybrid plugins)
// ============================================================================

/// Plugin metadata
pub export fn grim_plugin_info() callconv(.c) NativePluginInfo {
    return .{
        .name = "thanos",
        .version = "0.1.0",
        .author = "Ghost Stack <dev@ghoststack.io>",
        .api_version = GRIM_PLUGIN_API_VERSION,
    };
}

/// Initialize plugin (required)
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var plugin_instance: ?ThanosGrimPlugin = null;

pub export fn grim_plugin_init() callconv(.c) bool {
    const allocator = gpa.allocator();
    plugin_instance = ThanosGrimPlugin.init(allocator) catch return false;
    return true;
}

/// Setup hook (optional) - called after init
pub export fn grim_plugin_setup() callconv(.c) void {
    // Initialization happens lazily on first use
}

/// Teardown hook (optional) - called before unload
pub export fn grim_plugin_teardown() callconv(.c) void {
    if (plugin_instance) |*instance| {
        instance.deinit();
    }
    _ = gpa.deinit();
}

// ============================================================================
// FFI Bridge Functions (called from Ghostlang via call_native())
// ============================================================================

/// AI code completion
/// Called from Ghostlang as: call_native("thanos_complete", prompt)
pub export fn thanos_complete(prompt: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const prompt_str = std.mem.span(prompt);

    var instance = &(plugin_instance orelse return "error: not initialized");

    const result = instance.complete(prompt_str, null) catch |err| {
        var buf: [128]u8 = undefined;
        const error_msg = std.fmt.bufPrintZ(&buf, "error: {s}", .{@errorName(err)}) catch return "error";
        return error_msg.ptr;
    };

    // Convert to null-terminated string
    // Note: This uses a static buffer, so it will be overwritten on next call
    var static_buf: [4096]u8 = undefined;
    const result_z = std.fmt.bufPrintZ(&static_buf, "{s}", .{result}) catch return "error: result too long";
    return result_z.ptr;
}

/// List available providers
/// Called from Ghostlang as: call_native("thanos_providers")
pub export fn thanos_providers(_: [*:0]const u8) callconv(.c) [*:0]const u8 {
    var instance = &(plugin_instance orelse return "error: not initialized");

    const providers = instance.listProviders() catch return "error: failed to list providers";

    // Format as simple string list
    var buf: [1024]u8 = undefined;
    var offset: usize = 0;

    for (providers, 0..) |provider, i| {
        const name = @tagName(provider.provider);
        const status = if (provider.available) "available" else "unavailable";

        if (i > 0) {
            buf[offset] = ',';
            buf[offset + 1] = ' ';
            offset += 2;
        }

        const written = std.fmt.bufPrint(buf[offset..], "{s}({s})", .{ name, status }) catch return "error: format failed";
        offset += written.len;
    }

    const result_z = std.fmt.bufPrintZ(buf[offset..], "", .{}) catch return "error";
    _ = result_z;
    return buf[0..offset :0].ptr;
}

/// Get statistics
/// Called from Ghostlang as: call_native("thanos_stats")
pub export fn thanos_stats(_: [*:0]const u8) callconv(.c) [*:0]const u8 {
    var instance = &(plugin_instance orelse return "error: not initialized");

    const stats = instance.getStats() catch return "error: failed to get stats";

    var buf: [512]u8 = undefined;
    const result = std.fmt.bufPrintZ(&buf,
        "Providers: {d}, Requests: {d}, Avg Latency: {d}ms",
        .{
            stats.providers_available,
            stats.total_requests,
            stats.avg_latency_ms,
        }
    ) catch return "error: format failed";

    return result.ptr;
}

test "plugin initialization" {
    var plugin = try ThanosGrimPlugin.init(std.testing.allocator);
    defer plugin.deinit();

    try std.testing.expect(!plugin.initialized);
}
