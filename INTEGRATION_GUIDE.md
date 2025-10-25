# Thanos.grim Integration Guide

Complete step-by-step guide to integrate thanos.grim with Grim editor.

---

## Phase 1: Build & Install (30 minutes)

### Step 1: Build Thanos Library

```bash
cd /data/projects/thanos
zig build

# Verify all providers compiled
ls -la zig-out/lib/libthanos.a
```

### Step 2: Build Thanos.grim Bridge

```bash
cd /data/projects/thanos.grim
zig build bridge

# Should see:
ls -lh zig-out/lib/libthanos_grim_bridge.so
# Output: ~7-8MB shared library
```

### Step 3: Install Library

```bash
# Option A: System-wide
sudo cp zig-out/lib/libthanos_grim_bridge.so /usr/local/lib/
sudo ldconfig

# Option B: Local (recommended for development)
export THANOS_GRIM_LIB=/data/projects/thanos.grim/zig-out/lib/libthanos_grim_bridge.so
```

### Step 4: Install Plugin to Grim

```bash
mkdir -p ~/.local/share/grim/plugins/thanos

# Copy plugin files
cp init.gza ~/.local/share/grim/plugins/thanos/
cp plugin.toml ~/.local/share/grim/plugins/thanos/
cp thanos.toml ~/.local/share/grim/plugins/thanos/
cp zig-out/lib/libthanos_grim_bridge.so ~/.local/share/grim/plugins/thanos/
```

---

## Phase 2: Grim Editor Integration (2-3 hours)

### Step 1: Update Grim's Build System

**File:** `/data/projects/grim/build.zig`

Add AI module to build:

```zig
// After other imports
const ai = b.addModule("ai", .{
    .root_source_file = b.path("src/ai/mod.zig"),
    .target = target,
    .optimize = optimize,
});

// Add to main executable imports
.imports = &.{
    .{ .name = "ai", .module = ai },
    // ... other imports
},
```

### Step 2: Create Plugin Loader

**File:** `/data/projects/grim/src/plugins/thanos_loader.zig`

```zig
const std = @import("std");
const ai = @import("ai");

pub const ThanosPlugin = struct {
    lib: std.DynLib,
    allocator: std.mem.Allocator,

    // FFI function pointers
    init_fn: *const fn (config: [*:0]const u8) callconv(.C) c_int,
    complete_fn: *const fn (prompt: [*:0]const u8, lang: [*:0]const u8, max_tokens: c_int) callconv(.C) [*:0]const u8,
    inline_complete_fn: *const fn (prefix: [*:0]const u8, suffix: [*:0]const u8, lang: [*:0]const u8, debounce: c_int, max_tokens: c_int) callconv(.C) [*:0]const u8,
    list_providers_fn: *const fn () callconv(.C) [*:0]const u8,
    switch_provider_fn: *const fn (provider: [*:0]const u8) callconv(.C) c_int,
    get_current_provider_fn: *const fn () callconv(.C) [*:0]const u8,
    get_stats_fn: *const fn () callconv(.C) [*:0]const u8,
    free_fn: *const fn (str: [*:0]const u8) callconv(.C) void,

    pub fn load(allocator: std.mem.Allocator) !ThanosPlugin {
        // Try to load library
        const lib_path = std.posix.getenv("THANOS_GRIM_LIB") orelse
            "/usr/local/lib/libthanos_grim_bridge.so";

        var lib = std.DynLib.open(lib_path) catch |err| {
            std.debug.print("Failed to load thanos.grim: {s}\n", .{@errorName(err)});
            return err;
        };

        // Load function pointers
        const init_fn = lib.lookup(@TypeOf(ThanosPlugin.init_fn), "thanos_grim_init") orelse
            return error.SymbolNotFound;
        const complete_fn = lib.lookup(@TypeOf(ThanosPlugin.complete_fn), "thanos_grim_complete") orelse
            return error.SymbolNotFound;
        const inline_complete_fn = lib.lookup(@TypeOf(ThanosPlugin.inline_complete_fn), "thanos_grim_get_inline_completion_debounced") orelse
            return error.SymbolNotFound;
        const list_providers_fn = lib.lookup(@TypeOf(ThanosPlugin.list_providers_fn), "thanos_grim_list_providers") orelse
            return error.SymbolNotFound;
        const switch_provider_fn = lib.lookup(@TypeOf(ThanosPlugin.switch_provider_fn), "thanos_grim_switch_provider") orelse
            return error.SymbolNotFound;
        const get_current_provider_fn = lib.lookup(@TypeOf(ThanosPlugin.get_current_provider_fn), "thanos_grim_get_current_provider") orelse
            return error.SymbolNotFound;
        const get_stats_fn = lib.lookup(@TypeOf(ThanosPlugin.get_stats_fn), "thanos_grim_get_stats") orelse
            return error.SymbolNotFound;
        const free_fn = lib.lookup(@TypeOf(ThanosPlugin.free_fn), "thanos_grim_free") orelse
            return error.SymbolNotFound;

        // Initialize plugin
        const config = "{}"; // Empty JSON config
        const result = init_fn(config.ptr);

        if (result != 1) {
            std.debug.print("Thanos initialization failed\n", .{});
            return error.InitFailed;
        }

        std.debug.print("✅ Thanos.grim loaded successfully\n", .{});

        return ThanosPlugin{
            .lib = lib,
            .allocator = allocator,
            .init_fn = init_fn,
            .complete_fn = complete_fn,
            .inline_complete_fn = inline_complete_fn,
            .list_providers_fn = list_providers_fn,
            .switch_provider_fn = switch_provider_fn,
            .get_current_provider_fn = get_current_provider_fn,
            .get_stats_fn = get_stats_fn,
            .free_fn = free_fn,
        };
    }

    pub fn deinit(self: *ThanosPlugin) void {
        self.lib.close();
    }
};
```

### Step 3: Add AI State to Editor

**File:** `/data/projects/grim/src/editor/editor.zig` (or wherever your main Editor struct is)

```zig
const ai = @import("ai");
const ThanosPlugin = @import("../plugins/thanos_loader.zig").ThanosPlugin;

pub const Editor = struct {
    // ... existing fields

    // AI components
    thanos_plugin: ?ThanosPlugin,
    inline_engine: ai.InlineCompletionEngine,
    ghost_renderer: ai.GhostTextRenderer,
    chat_window: ai.ChatWindow,
    provider_switcher: ai.ProviderSwitcher,
    diff_viewer: ?ai.DiffViewer,
    context_manager: ai.ContextManager,
    cost_tracker: ai.CostTracker,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        // ... existing init

        // Load thanos.grim plugin
        const thanos_plugin = ThanosPlugin.load(allocator) catch |err| {
            std.debug.print("⚠️  Thanos.grim not available: {s}\n", .{@errorName(err)});
            return Editor{
                // ... with thanos_plugin = null
            };
        };

        // Initialize AI components
        var inline_engine = ai.InlineCompletionEngine.init(allocator, 200);
        inline_engine.setCompletionFunction(thanos_plugin.inline_complete_fn);

        var chat_window = try ai.ChatWindow.init(allocator, 50);
        chat_window.setCompletionFunction(thanos_plugin.complete_fn);

        var provider_switcher = try ai.ProviderSwitcher.init(allocator);
        provider_switcher.setFFIFunctions(
            thanos_plugin.list_providers_fn,
            thanos_plugin.switch_provider_fn,
            thanos_plugin.get_current_provider_fn,
        );

        return Editor{
            // ... existing fields
            .thanos_plugin = thanos_plugin,
            .inline_engine = inline_engine,
            .ghost_renderer = ai.GhostTextRenderer.init(allocator),
            .chat_window = chat_window,
            .provider_switcher = provider_switcher,
            .diff_viewer = null,
            .context_manager = ai.ContextManager.init(allocator, 8000),
            .cost_tracker = ai.CostTracker.init(allocator),
        };
    }

    pub fn deinit(self: *Editor) void {
        if (self.thanos_plugin) |*plugin| {
            plugin.deinit();
        }
        self.inline_engine.deinit();
        self.ghost_renderer.deinit();
        self.chat_window.deinit();
        self.provider_switcher.deinit();
        if (self.diff_viewer) |*viewer| {
            viewer.deinit();
        }
        self.context_manager.deinit();
        self.cost_tracker.deinit();

        // ... existing deinit
    }
};
```

### Step 4: Hook Up Insert Mode Completions

**File:** `/data/projects/grim/src/editor/insert_mode.zig` (or similar)

```zig
pub fn handleInsertModeInput(editor: *Editor, key: Key) !void {
    switch (key) {
        .char => |ch| {
            // Insert character
            try editor.current_buffer.insert(ch);

            // Request inline completion
            if (editor.thanos_plugin != null) {
                try requestInlineCompletion(editor);
            }
        },

        .tab => {
            // Accept ghost text if present
            if (editor.ghost_renderer.getCurrentGhost()) |ghost| {
                try editor.current_buffer.insert(ghost.text);
                editor.ghost_renderer.clearGhostText();
                editor.inline_engine.acceptCompletion();
            } else {
                // Normal tab behavior
                try editor.current_buffer.insert('\t');
            }
        },

        .escape => {
            // Clear ghost text
            editor.ghost_renderer.clearGhostText();
            // Switch to normal mode
            editor.mode = .normal;
        },

        else => {
            // Clear ghost text on cursor movement
            editor.ghost_renderer.clearGhostText();
        },
    }
}

fn requestInlineCompletion(editor: *Editor) !void {
    const buffer = editor.current_buffer;
    const cursor = editor.cursor;

    const context = ai.CompletionContext{
        .prefix = try buffer.getTextBeforeCursor(editor.allocator),
        .suffix = try buffer.getTextAfterCursor(editor.allocator),
        .file_path = buffer.file_path orelse "untitled",
        .language = buffer.language orelse "text",
        .line = cursor.line,
        .column = cursor.column,
    };

    if (try editor.inline_engine.requestCompletion(context)) |completion| {
        defer completion.deinit();

        try editor.ghost_renderer.showGhostText(
            completion.text,
            cursor.line,
            cursor.column,
        );
    }
}
```

### Step 5: Render Ghost Text

**File:** `/data/projects/grim/src/ui-tui/renderer.zig` (or wherever TUI rendering happens)

```zig
pub fn renderBuffer(editor: *const Editor, writer: anytype) !void {
    // ... existing buffer rendering

    // Render ghost text at cursor position
    if (editor.ghost_renderer.getCurrentGhost()) |ghost| {
        if (ghost.visible and ghost.line == editor.cursor.line) {
            // Position cursor at ghost text location
            try writer.print("\x1b[{};{}H", .{ ghost.line + 1, ghost.column + 1 });

            // Render ghost text (dim + italic)
            try writer.writeAll("\x1b[2;3m");
            try writer.writeAll(ghost.text);
            try writer.writeAll("\x1b[0m");

            // Restore cursor position
            try writer.print("\x1b[{};{}H", .{ editor.cursor.line + 1, editor.cursor.column + 1 });
        }
    }
}
```

### Step 6: Add Commands

**File:** `/data/projects/grim/src/commands/thanos.zig`

```zig
const std = @import("std");
const Editor = @import("../editor/editor.zig").Editor;
const ai = @import("ai");

pub fn chatCommand(editor: *Editor) !void {
    if (editor.thanos_plugin == null) {
        try editor.showError("Thanos.grim not loaded");
        return;
    }

    editor.chat_window.toggle();
}

pub fn completeCommand(editor: *Editor) !void {
    if (editor.thanos_plugin == null) {
        try editor.showError("Thanos.grim not loaded");
        return;
    }

    const plugin = editor.thanos_plugin.?;
    const buffer = editor.current_buffer;

    const prompt = try buffer.getTextBeforeCursor(editor.allocator);
    defer editor.allocator.free(prompt);

    const prompt_z = try editor.allocator.dupeZ(u8, prompt);
    defer editor.allocator.free(prompt_z);

    const language_z = try editor.allocator.dupeZ(u8, buffer.language orelse "text");
    defer editor.allocator.free(language_z);

    const result_ptr = plugin.complete_fn(prompt_z.ptr, language_z.ptr, 150);
    const result = std.mem.span(result_ptr);

    // Insert completion
    try buffer.insert(result);

    // Free result
    plugin.free_fn(result_ptr);
}

pub fn switchProviderCommand(editor: *Editor) !void {
    if (editor.thanos_plugin == null) {
        try editor.showError("Thanos.grim not loaded");
        return;
    }

    try editor.provider_switcher.show();
    editor.mode = .provider_switcher;
}

pub fn statsCommand(editor: *Editor) !void {
    if (editor.thanos_plugin == null) {
        try editor.showError("Thanos.grim not loaded");
        return;
    }

    const plugin = editor.thanos_plugin.?;
    const stats_ptr = plugin.get_stats_fn();
    const stats = std.mem.span(stats_ptr);

    try editor.showPopup("Thanos Stats", stats);

    plugin.free_fn(stats_ptr);
}
```

### Step 7: Register Commands

**File:** `/data/projects/grim/src/commands/mod.zig`

```zig
const thanos = @import("thanos.zig");

pub const command_table = std.ComptimeStringMap(*const fn (*Editor) anyerror!void, .{
    // ... existing commands
    .{ "ThanosChat", thanos.chatCommand },
    .{ "ThanosComplete", thanos.completeCommand },
    .{ "ThanosSwitch", thanos.switchProviderCommand },
    .{ "ThanosStats", thanos.statsCommand },
});
```

### Step 8: Add Keybindings

**File:** `/data/projects/grim/src/keymaps/default.zig`

```zig
pub const normal_mode_bindings = std.ComptimeStringMap(Command, .{
    // ... existing bindings
    .{ "<leader>ac", .ThanosChat },
    .{ "<leader>ak", .ThanosComplete },
    .{ "<leader>ap", .ThanosSwitch },
    .{ "<leader>as", .ThanosStats },
});
```

---

## Phase 3: Testing (1-2 hours)

### Test 1: Plugin Loading

```bash
cd /data/projects/grim
zig build run

# Should see:
# ✅ Thanos.grim loaded successfully
```

### Test 2: Inline Completions

```zig
// In Grim, open a .zig file and type:
fn fibonacci(

// Wait 200ms - should see ghost text:
// fn fibonacci(n: usize) usize {
//     if (n <= 1) return n;
//     return fibonacci(n-1) + fibonacci(n-2);
// }

// Press Tab to accept
```

### Test 3: Chat Window

```
:ThanosChat
# Type: "How do I reverse a string in Zig?"
# Press Enter
# Should see response from AI
```

### Test 4: Provider Switching

```
:ThanosSwitch
# Use ↑/↓ to select Anthropic
# Press Enter
# Status line should show "AI: anthropic"
```

### Test 5: Cost Tracking

```
:ThanosStats
# Should show JSON with:
# {"providers_available":1,"total_requests":N,"avg_latency_ms":XXX}
```

---

## Phase 4: Configuration

### Setup API Keys

```bash
# Add to ~/.bashrc or ~/.zshrc:
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export XAI_API_KEY="xai-..."

# For GitHub Copilot:
gh auth login
```

### Configure thanos.toml

```toml
[ai]
mode = "hybrid"
primary_provider = "ollama"

[providers.ollama]
enabled = true
model = "codellama:13b"

[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"
model = "claude-sonnet-4-20250514"

[providers.openai]
enabled = true
api_key = "${OPENAI_API_KEY}"
model = "gpt-4-turbo-preview"

[routing]
fallback_chain = ["ollama", "anthropic", "openai"]
```

---

## Troubleshooting

### Issue: Library Not Found

```bash
# Check library exists
ls -la /usr/local/lib/libthanos_grim_bridge.so

# If not, install it
sudo cp zig-out/lib/libthanos_grim_bridge.so /usr/local/lib/
sudo ldconfig

# Or use environment variable
export THANOS_GRIM_LIB=/path/to/libthanos_grim_bridge.so
```

### Issue: Symbols Not Found

```bash
# Check exported symbols
nm -D zig-out/lib/libthanos_grim_bridge.so | grep thanos_grim

# Should see:
# thanos_grim_init
# thanos_grim_complete
# thanos_grim_get_inline_completion_debounced
# etc.
```

### Issue: Ollama Not Running

```bash
# Start Ollama
ollama serve &

# Pull a model
ollama pull codellama:13b

# Test
curl http://localhost:11434/api/tags
```

---

## Performance Tips

1. **Use Ollama for inline completions** - Much faster than cloud APIs
2. **Enable caching** - Reuse previous completions
3. **Adjust debounce time** - Lower = faster, higher = fewer requests
4. **Set token limits** - Lower limits = faster responses
5. **Use hybrid mode** - Local first, cloud for complex tasks

---

## Next Steps

1. ✅ Build everything
2. ✅ Load plugin in Grim
3. ✅ Test inline completions
4. ✅ Test chat window
5. ✅ Test provider switching
6. ⬜ Add syntax highlighting to chat
7. ⬜ Add streaming support
8. ⬜ Polish UI
9. ⬜ Write user docs
10. ⬜ Ship it! 🚀

---

**Integration Complete!** 🎉

You now have a fully-functional Claude Code alternative built specifically for Grim!
