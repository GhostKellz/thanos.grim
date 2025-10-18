//! Thanos Grim Plugin - Native Zig AI integration for Grim editor
//!
//! This plugin provides AI-powered completions and tools directly in Grim
//! using the Thanos orchestration layer.
const std = @import("std");
const thanos = @import("thanos");

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

        const config = thanos.types.Config{
            .debug = true,
            .preferred_provider = .omen,
            .fallback_providers = &.{ .ollama },
        };

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

/// Plugin entry point for Grim
pub export fn grim_plugin_init() c_int {
    return 0; // Success
}

/// Plugin metadata
pub export fn grim_plugin_name() [*:0]const u8 {
    return "Thanos AI";
}

pub export fn grim_plugin_version() [*:0]const u8 {
    return "0.1.0";
}

pub export fn grim_plugin_description() [*:0]const u8 {
    return "Unified AI Infrastructure Gateway for Grim";
}

test "plugin initialization" {
    var plugin = try ThanosGrimPlugin.init(std.testing.allocator);
    defer plugin.deinit();

    try std.testing.expect(!plugin.initialized);
}
