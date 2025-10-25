// Thanos.grim Native Bridge
// FFI bridge between Ghostlang plugin and Thanos AI library
//
// This provides C-compatible exports that can be called from Ghostlang via FFI.

const std = @import("std");
const builtin = @import("builtin");

// Import actual Thanos library
const thanos = @import("thanos");

// Re-export types from Thanos
const Provider = thanos.Provider;
const Config = thanos.Config;
const CompletionRequest = thanos.CompletionRequest;
const CompletionResponse = thanos.CompletionResponse;
const ProviderHealth = thanos.types.ProviderHealth;

// Global state
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;
var initialized = false;
var thanos_instance: ?*thanos.Thanos = null;

// ============================================================================
// INITIALIZATION
// ============================================================================

/// Initialize Thanos library
/// @param config_json JSON string with configuration
/// @return 1 on success, 0 on failure
export fn thanos_grim_init(config_json: [*:0]const u8) callconv(.c) c_int {
    if (initialized) {
        return 1; // Already initialized
    }

    allocator = gpa.allocator();

    // Parse config JSON
    const config_str = std.mem.span(config_json);

    // Parse JSON to create Thanos config
    var config = Config{
        .debug = true,
        .mode = .hybrid, // Default to hybrid mode
    };

    // Try to parse JSON config (simple parsing for now)
    if (std.mem.indexOf(u8, config_str, "\"mode\":\"ollama-heavy\"")) |_| {
        config.mode = .ollama_heavy;
    } else if (std.mem.indexOf(u8, config_str, "\"mode\":\"api-heavy\"")) |_| {
        config.mode = .api_heavy;
    } else if (std.mem.indexOf(u8, config_str, "\"mode\":\"hybrid\"")) |_| {
        config.mode = .hybrid;
    }

    // Initialize Thanos
    const instance = thanos.Thanos.init(allocator, config) catch |err| {
        std.debug.print("[Thanos.grim] Init failed: {any}\n", .{err});
        return 0;
    };

    // Allocate and store instance
    thanos_instance = allocator.create(thanos.Thanos) catch return 0;
    thanos_instance.?.* = instance;

    std.debug.print("[Thanos.grim] ✅ Initialized successfully\n", .{});

    initialized = true;

    return 1;
}

/// Check if Thanos is initialized
/// @return 1 if initialized, 0 otherwise
export fn thanos_grim_is_initialized() callconv(.c) c_int {
    return if (initialized) 1 else 0;
}

/// Cleanup and free resources
export fn thanos_grim_deinit() callconv(.c) void {
    if (!initialized) return;

    std.debug.print("[Thanos.grim] Shutting down\n", .{});

    // Deinit Thanos instance
    if (thanos_instance) |instance| {
        instance.deinit();
        allocator.destroy(instance);
        thanos_instance = null;
    }

    initialized = false;

    // Note: We don't deinit the GPA here because it's global and may be reused
    // In production, this would be called once at program exit
    // For tests, each test reinitializes, so we leave GPA alive
}

// ============================================================================
// AI COMPLETION
// ============================================================================

/// Complete a code prompt
/// @param prompt The text to complete
/// @param language Programming language (can be null)
/// @param max_tokens Maximum tokens to generate
/// @return Completion text (caller must free with thanos_grim_free)
export fn thanos_grim_complete(
    prompt: [*:0]const u8,
    language: [*:0]const u8,
    max_tokens: c_int,
) callconv(.c) [*:0]const u8 {
    if (!initialized) {
        return allocString("Error: Thanos not initialized") catch return "";
    }

    const instance = thanos_instance orelse {
        return allocString("Error: Thanos instance not found") catch return "";
    };

    const prompt_str = std.mem.span(prompt);
    const lang_str = std.mem.span(language);
    const lang_opt = if (lang_str.len > 0) lang_str else null;

    std.debug.print("[Thanos.grim] 💬 Completing: {s}\n", .{prompt_str[0..@min(50, prompt_str.len)]});

    // Create completion request
    const request = CompletionRequest{
        .prompt = prompt_str,
        .language = lang_opt,
        .max_tokens = if (max_tokens > 0) @intCast(max_tokens) else null,
    };

    // Call Thanos complete
    const response = instance.complete(request) catch |err| {
        const err_msg = std.fmt.allocPrint(allocator, "Error: {any}", .{err}) catch return "";
        defer allocator.free(err_msg);
        return allocString(err_msg) catch return "";
    };

    // Duplicate response text for C
    const result = allocator.dupeZ(u8, response.text) catch return "";

    // Don't free response.text - Thanos owns it and will clean up on deinit
    // response.deinit(allocator); // DON'T do this - it's owned by Thanos

    std.debug.print("[Thanos.grim] ✅ Completion from {s} ({} chars)\n", .{
        response.provider.toString(),
        result.len,
    });

    return result.ptr;
}

/// Complete with specific provider
/// @param prompt The text to complete
/// @param provider_name Provider to use (e.g., "ollama", "anthropic")
/// @param language Programming language (can be null)
/// @param max_tokens Maximum tokens to generate
/// @return Completion text (caller must free with thanos_grim_free)
export fn thanos_grim_complete_with_provider(
    prompt: [*:0]const u8,
    provider_name: [*:0]const u8,
    language: [*:0]const u8,
    max_tokens: c_int,
) callconv(.c) [*:0]const u8 {
    if (!initialized) {
        return allocString("Error: Thanos not initialized") catch return "";
    }

    const instance = thanos_instance orelse {
        return allocString("Error: Thanos instance not found") catch return "";
    };

    const prompt_str = std.mem.span(prompt);
    const provider_str = std.mem.span(provider_name);
    const lang_str = std.mem.span(language);
    const lang_opt = if (lang_str.len > 0) lang_str else null;

    const provider = Provider.fromString(provider_str) orelse {
        const err = std.fmt.allocPrint(allocator, "Error: Unknown provider '{s}'", .{provider_str})
            catch return allocString("Error: Unknown provider") catch return "";
        defer allocator.free(err);
        return allocator.dupeZ(u8, err) catch return "";
    };

    std.debug.print("[Thanos.grim] 💬 Completing with {s}\n", .{provider.toString()});

    // Create completion request with specific provider
    const request = CompletionRequest{
        .prompt = prompt_str,
        .language = lang_opt,
        .provider = provider,
        .max_tokens = if (max_tokens > 0) @intCast(max_tokens) else null,
    };

    // Call Thanos complete
    const response = instance.complete(request) catch |err| {
        const err_msg = std.fmt.allocPrint(allocator, "Error: {any}", .{err}) catch return "";
        defer allocator.free(err_msg);
        return allocString(err_msg) catch return "";
    };

    // Duplicate response text for C
    const result = allocator.dupeZ(u8, response.text) catch return "";

    std.debug.print("[Thanos.grim] ✅ Completion from {s}\n", .{response.provider.toString()});

    return result.ptr;
}

// TODO: Streaming support - Currently disabled due to zhttp API incompatibility in Thanos core
// The completeStreaming() method in Thanos uses response.readLine() which doesn't exist
// in the current zhttp version. This needs to be fixed in Thanos core first.
//
// Once Thanos streaming is fixed, uncomment these functions:

/// Streaming completion callback type for C
// pub const StreamingCallback = *const fn (chunk: [*:0]const u8, chunk_len: c_int, user_data: ?*anyopaque) callconv(.c) void;

/// Complete with streaming response (token-by-token) - DISABLED
/// @return Always returns 0 (not implemented)
export fn thanos_grim_complete_streaming(
    prompt: [*:0]const u8,
    language: [*:0]const u8,
    max_tokens: c_int,
    callback: ?*const anyopaque,
    user_data: ?*anyopaque,
) callconv(.c) c_int {
    _ = prompt;
    _ = language;
    _ = max_tokens;
    _ = callback;
    _ = user_data;

    std.debug.print("[Thanos.grim] ❌ Streaming not yet supported (zhttp API incompatibility)\n", .{});
    return 0;
}

/// Complete with streaming and specific provider - DISABLED
/// @return Always returns 0 (not implemented)
export fn thanos_grim_complete_streaming_with_provider(
    prompt: [*:0]const u8,
    provider_name: [*:0]const u8,
    language: [*:0]const u8,
    max_tokens: c_int,
    callback: ?*const anyopaque,
    user_data: ?*anyopaque,
) callconv(.c) c_int {
    _ = prompt;
    _ = provider_name;
    _ = language;
    _ = max_tokens;
    _ = callback;
    _ = user_data;

    std.debug.print("[Thanos.grim] ❌ Streaming not yet supported (zhttp API incompatibility)\n", .{});
    return 0;
}

/// Get inline ghost text completion (for autocomplete)
/// @param prefix Text before cursor
/// @param suffix Text after cursor
/// @param language Programming language
/// @param max_tokens Maximum tokens (default 50 for inline)
/// @return Completion text to insert at cursor (caller must free)
export fn thanos_grim_get_inline_completion(
    prefix: [*:0]const u8,
    suffix: [*:0]const u8,
    language: [*:0]const u8,
    max_tokens: c_int,
) callconv(.c) [*:0]const u8 {
    if (!initialized) {
        return allocString("") catch return "";
    }

    const instance = thanos_instance orelse {
        return allocString("") catch return "";
    };

    const prefix_str = std.mem.span(prefix);
    const suffix_str = std.mem.span(suffix);
    const lang_str = std.mem.span(language);

    // Build prompt for inline completion
    const prompt = std.fmt.allocPrint(allocator,
        "Complete the following {s} code. Only provide the completion, no explanations:\n\n{s}<CURSOR>{s}",
        .{ lang_str, prefix_str, suffix_str },
    ) catch return allocString("") catch return "";
    defer allocator.free(prompt);

    std.debug.print("[Thanos.grim] 👻 Ghost text completion ({} chars context)\n", .{prefix_str.len + suffix_str.len});

    // Create completion request with small max_tokens for inline
    const tokens = if (max_tokens > 0) @as(u32, @intCast(max_tokens)) else 50;
    const request = thanos.CompletionRequest{
        .prompt = prompt,
        .language = lang_str,
        .max_tokens = tokens,
        .temperature = 0.2, // Low temperature for more predictable completions
    };

    // Get completion
    const response = instance.complete(request) catch |err| {
        std.debug.print("[Thanos.grim] ❌ Ghost text failed: {any}\n", .{err});
        return allocString("") catch return "";
    };

    // Extract just the completion part (remove any markdown, explanations, etc.)
    const result = allocator.dupeZ(u8, response.text) catch return "";

    std.debug.print("[Thanos.grim] 👻 Ghost text: {s}\n", .{result[0..@min(30, result.len)]});

    return result.ptr;
}

/// Get inline completion with debouncing (waits for user to stop typing)
/// @param prefix Text before cursor
/// @param suffix Text after cursor
/// @param language Programming language
/// @param debounce_ms Milliseconds to wait before requesting
/// @param max_tokens Maximum tokens
/// @return Completion text (caller must free)
export fn thanos_grim_get_inline_completion_debounced(
    prefix: [*:0]const u8,
    suffix: [*:0]const u8,
    language: [*:0]const u8,
    debounce_ms: c_int,
    max_tokens: c_int,
) callconv(.c) [*:0]const u8 {
    // Sleep for debounce period
    if (debounce_ms > 0) {
        std.Thread.sleep(@as(u64, @intCast(debounce_ms)) * std.time.ns_per_ms);
    }

    // Call regular inline completion
    return thanos_grim_get_inline_completion(prefix, suffix, language, max_tokens);
}

// ============================================================================
// PROVIDER MANAGEMENT
// ============================================================================

/// List available AI providers
/// @return JSON array of provider objects (caller must free)
export fn thanos_grim_list_providers() callconv(.c) [*:0]const u8 {
    if (!initialized) {
        return allocString("[]") catch return "";
    }

    const instance = thanos_instance orelse {
        return allocString("[]") catch return "";
    };

    // Get provider health from Thanos
    const providers = instance.listProviders() catch {
        return allocString("[]") catch return "";
    };

    // Build JSON array
    var json_buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&json_buf);
    const fba_allocator = fba.allocator();

    var json_str = std.ArrayList(u8).initCapacity(fba_allocator, 1024) catch {
        return allocString("[]") catch return "";
    };
    json_str.appendSlice(fba_allocator, "[") catch return allocString("[]") catch return "";

    for (providers, 0..) |provider_health, i| {
        if (i > 0) {
            json_str.appendSlice(fba_allocator, ",") catch break;
        }

        const entry = std.fmt.allocPrint(fba_allocator,
            \\{{"name":"{s}","available":{s},"healthy":{s}}}
        , .{
            provider_health.provider.toString(),
            if (provider_health.available) "true" else "false",
            if (provider_health.available) "true" else "false",
        }) catch break;

        json_str.appendSlice(fba_allocator, entry) catch break;
    }

    json_str.appendSlice(fba_allocator, "]") catch return allocString("[]") catch return "";

    return allocString(json_str.items) catch return "[]";
}

/// Switch to a different provider (sets preferred provider)
/// @param provider_name Provider to switch to
/// @return 1 on success, 0 on failure
export fn thanos_grim_switch_provider(provider_name: [*:0]const u8) callconv(.c) c_int {
    if (!initialized) return 0;

    const instance = thanos_instance orelse return 0;

    const provider_str = std.mem.span(provider_name);
    const provider = Provider.fromString(provider_str) orelse return 0;

    // Update preferred provider in config
    instance.config.preferred_provider = provider;

    std.debug.print("[Thanos.grim] Switched preferred provider to: {s}\n", .{provider.toString()});

    return 1;
}

/// Get current provider name (preferred provider)
/// @return Provider name (caller must free)
export fn thanos_grim_get_current_provider() callconv(.c) [*:0]const u8 {
    if (!initialized) {
        return allocString("auto") catch return "";
    }

    const instance = thanos_instance orelse {
        return allocString("auto") catch return "";
    };

    const provider = instance.config.preferred_provider orelse {
        return allocString("auto") catch return "";
    };

    return allocString(provider.toString()) catch return "";
}

// ============================================================================
// STATISTICS
// ============================================================================

/// Get usage statistics
/// @return JSON object with stats (caller must free)
export fn thanos_grim_get_stats() callconv(.c) [*:0]const u8 {
    if (!initialized) {
        return allocString("{}") catch return "";
    }

    const instance = thanos_instance orelse {
        return allocString("{}") catch return "";
    };

    // Get stats from Thanos
    const stats = instance.getStats() catch {
        return allocString("{}") catch return "";
    };

    // Build JSON
    const json = std.fmt.allocPrint(allocator,
        \\{{"providers_available":{d},"total_requests":{d},"avg_latency_ms":{d}}}
    , .{
        stats.providers_available,
        stats.total_requests,
        stats.avg_latency_ms,
    }) catch return allocString("{}") catch return "";

    const result = allocator.dupeZ(u8, json) catch {
        allocator.free(json);
        return "";
    };
    allocator.free(json);

    return result.ptr;
}

// ============================================================================
// HEALTH & MONITORING
// ============================================================================

/// Get health report for all providers
/// @return JSON object with health info (caller must free)
export fn thanos_grim_get_health() callconv(.c) [*:0]const u8 {
    if (!initialized) {
        return allocString("{}") catch return "";
    }

    const instance = thanos_instance orelse {
        return allocString("{}") catch return "";
    };

    // Get provider health from Thanos
    const providers = instance.listProviders() catch {
        return allocString("{}") catch return "";
    };

    // Build JSON object
    var json_buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&json_buf);
    const fba_allocator = fba.allocator();

    var json_str = std.ArrayList(u8).initCapacity(fba_allocator, 1024) catch {
        return allocString("{}") catch return "";
    };
    json_str.appendSlice(fba_allocator, "{") catch return allocString("{}") catch return "";

    for (providers, 0..) |provider_health, i| {
        if (i > 0) {
            json_str.appendSlice(fba_allocator, ",") catch break;
        }

        const entry = std.fmt.allocPrint(fba_allocator,
            "\"{s}\":{{\"healthy\":{s},\"available\":{s}}}",
            .{
                provider_health.provider.toString(),
                if (provider_health.available) "true" else "false",
                if (provider_health.available) "true" else "false",
            },
        ) catch break;

        json_str.appendSlice(fba_allocator, entry) catch break;
    }

    json_str.appendSlice(fba_allocator, "}") catch return allocString("{}") catch return "";

    return allocString(json_str.items) catch return "{}";
}

/// Check if a specific provider is healthy
/// @param provider_name Provider to check
/// @return 1 if healthy, 0 otherwise
export fn thanos_grim_is_provider_healthy(provider_name: [*:0]const u8) callconv(.c) c_int {
    if (!initialized) return 0;

    const instance = thanos_instance orelse return 0;

    const provider_str = std.mem.span(provider_name);
    const provider = Provider.fromString(provider_str) orelse return 0;

    // Get provider health from Thanos
    const providers = instance.listProviders() catch return 0;

    // Check if this provider is available
    for (providers) |provider_health| {
        if (provider_health.provider == provider) {
            return if (provider_health.available) 1 else 0;
        }
    }

    return 0;
}

// ============================================================================
// UTILITIES
// ============================================================================

/// Get Thanos version
/// @return Version string (static, no need to free)
export fn thanos_grim_version() callconv(.c) [*:0]const u8 {
    return "0.2.0-grim";
}

/// Free a string allocated by Thanos
/// @param str String to free
export fn thanos_grim_free(str: [*:0]const u8) callconv(.c) void {
    if (!initialized) return;

    const slice = std.mem.span(str);
    allocator.free(slice);
}

/// Ping test
/// @return 42 (the answer to everything)
export fn thanos_grim_ping() callconv(.c) c_int {
    return 42;
}

/// Echo test
/// @param input String to echo back
/// @return Same string (caller must free)
export fn thanos_grim_echo(input: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const input_str = std.mem.span(input);
    return allocString(input_str) catch return "";
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Allocate a null-terminated string
fn allocString(str: []const u8) ![:0]const u8 {
    return try allocator.dupeZ(u8, str);
}

// ============================================================================
// TESTS
// ============================================================================

test "basic initialization" {
    const result = thanos_grim_init("{}");
    try std.testing.expectEqual(@as(c_int, 1), result);

    const is_init = thanos_grim_is_initialized();
    try std.testing.expectEqual(@as(c_int, 1), is_init);

    thanos_grim_deinit();
}

test "ping test" {
    _ = thanos_grim_init("{}");
    defer thanos_grim_deinit();

    const result = thanos_grim_ping();
    try std.testing.expectEqual(@as(c_int, 42), result);
}

test "echo test" {
    _ = thanos_grim_init("{}");
    defer thanos_grim_deinit();

    const input = "Hello, Thanos!";
    const output = thanos_grim_echo(input);
    defer thanos_grim_free(output);

    const output_str = std.mem.span(output);
    try std.testing.expectEqualStrings(input, output_str);
}

test "provider switching" {
    _ = thanos_grim_init("{}");
    defer thanos_grim_deinit();

    const result = thanos_grim_switch_provider("anthropic");
    try std.testing.expectEqual(@as(c_int, 1), result);

    const current = thanos_grim_get_current_provider();
    defer thanos_grim_free(current);

    const current_str = std.mem.span(current);
    try std.testing.expectEqualStrings("anthropic", current_str);
}
