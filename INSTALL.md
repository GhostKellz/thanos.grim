# Thanos.grim Installation Guide

## Quick Install (Week 1 - Alpha Testing)

### Prerequisites

1. **Grim Editor** (v0.1.0+)
2. **Zig** (v0.16.0-dev+)
3. **Ollama** (optional, for local AI)

### Step 1: Build the Native Bridge

```bash
cd /data/projects/thanos.grim

# Build the FFI bridge library
zig build bridge

# Verify the build
ls -lh zig-out/lib/libthanos_grim_bridge.so
```

You should see:
```
.rwxr-xr-x 7.7M ... libthanos_grim_bridge.so
```

### Step 2: Install to System

```bash
# Copy library to system path
sudo cp zig-out/lib/libthanos_grim_bridge.so /usr/local/lib/
sudo ldconfig

# OR set environment variable
export THANOS_GRIM_LIB=/data/projects/thanos.grim/zig-out/lib/libthanos_grim_bridge.so
```

### Step 3: Install Plugin to Grim

```bash
# Create Grim plugins directory
mkdir -p ~/.local/share/grim/plugins/thanos

# Copy plugin files
cp init.gza ~/.local/share/grim/plugins/thanos/
cp plugin.toml ~/.local/share/grim/plugins/thanos/

# Copy native library
cp zig-out/lib/libthanos_grim_bridge.so ~/.local/share/grim/plugins/thanos/
```

### Step 4: Configure Thanos (Optional)

Create `~/.config/grim/thanos.toml`:

```toml
[ai]
mode = "hybrid"
primary_provider = "ollama"

[providers.ollama]
enabled = true
endpoint = "http://localhost:11434"
model = "codellama:13b"

[providers.anthropic]
enabled = false
api_key = "${ANTHROPIC_API_KEY}"

[routing]
fallback_chain = ["ollama", "anthropic"]
```

### Step 5: Start Ollama (For Local AI)

```bash
# Start Ollama service
ollama serve &

# Pull a code model
ollama pull codellama:13b

# Verify it's running
curl http://localhost:11434/api/tags
```

### Step 6: Launch Grim

```bash
cd /data/projects/grim
./zig-out/bin/grim
```

Expected output:
```
[Thanos.grim] Initialized with config
🌌 Thanos AI v0.2.0-grim loaded ✅
Available providers: Ollama, Claude, GPT-4, GitHub Copilot
```

---

## Testing the Plugin

### Test 1: Ping Test

In Grim, open the command palette and run:
```
:ThanosProviders
```

You should see a popup with:
```
# Available AI Providers

[
  {"name": "ollama", "available": true, "healthy": true},
  {"name": "anthropic", "available": false, "healthy": false},
  ...
]

## Current Provider
ollama
```

### Test 2: Code Completion

1. Open a Zig file:
   ```zig
   const std = @import("std");

   pub fn main() !void {
       // <cursor here>
   }
   ```

2. Position cursor after the comment

3. Press `<leader>ak` or run `:ThanosComplete`

4. Expected: AI-generated code appears at cursor

### Test 3: AI Chat

1. Press `<leader>ac` or run `:ThanosChat`

2. A split window should open with:
   ```
   # Thanos AI Chat

   Provider: ollama
   Type your message and press <Enter>
   ```

3. Type a question like: "How do I reverse a string in Zig?"

4. Press Enter

5. Expected: AI response appears below your question

### Test 4: Provider Switching

```
:ThanosSwitch anthropic
```

Expected:
```
Switched to anthropic ✅
```

(Note: Will only work if you have ANTHROPIC_API_KEY set)

### Test 5: Statistics

```
:ThanosStats
```

Expected popup:
```
# Thanos Statistics

**Current Provider:** ollama

{
  "providers_available": 1,
  "total_requests": 0,
  "cache_hits": 0,
  "avg_latency_ms": 0
}
```

---

## Keybindings

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>ac` | ThanosChat | Open AI chat window |
| `<leader>ak` | ThanosComplete | AI code completion |
| `<leader>ap` | ThanosSwitch | Switch provider |
| `<leader>as` | ThanosStats | Show statistics |
| `<leader>ah` | ThanosHealth | Check provider health |

---

## Troubleshooting

### Issue: "FFI bridge test failed"

**Fix:**
```bash
# Ensure library is in the right place
export THANOS_GRIM_LIB=/data/projects/thanos.grim/zig-out/lib/libthanos_grim_bridge.so

# Or copy to system
sudo cp zig-out/lib/libthanos_grim_bridge.so /usr/local/lib/
sudo ldconfig
```

### Issue: "Thanos initialization failed"

**Fix:**
- Check that `thanos.toml` is valid TOML
- Ensure Ollama is running if using local provider
- Check Grim logs: `./grim 2>&1 | grep Thanos`

### Issue: Plugin doesn't load

**Fix:**
```bash
# Check plugin is in the right place
ls -la ~/.local/share/grim/plugins/thanos/

# Should show:
# - init.gza
# - plugin.toml
# - libthanos_grim_bridge.so
```

### Issue: Ollama connection refused

**Fix:**
```bash
# Start Ollama
ollama serve &

# Check it's listening
lsof -i:11434

# Test connection
curl http://localhost:11434/api/tags
```

---

## Next Steps (Week 2)

- [ ] Connect to real Thanos library (currently using mocks)
- [ ] Add streaming responses
- [ ] Implement provider health monitoring
- [ ] Add cost tracking
- [ ] Test with multiple providers
- [ ] Performance optimization

---

## Development

### Rebuild After Changes

```bash
cd /data/projects/thanos.grim

# Rebuild bridge
zig build bridge

# Copy to system
sudo cp zig-out/lib/libthanos_grim_bridge.so /usr/local/lib/
sudo ldconfig

# Restart Grim to reload plugin
```

### Run Tests

```bash
zig build test
```

### Debug FFI Issues

Enable debug output in bridge.zig:
```zig
std.debug.print("[Thanos.grim] Debug: {s}\n", .{message});
```

Then watch logs:
```bash
./grim 2>&1 | grep "Thanos.grim"
```

---

## Status: Week 1 Complete ✅

**What Works:**
- ✅ Native FFI bridge compiles
- ✅ 15 exported C functions
- ✅ Ghostlang init.gza with full FFI bindings
- ✅ Basic command structure
- ✅ Mock responses (real AI coming Week 2)

**What's Next (Week 2):**
- Wire to real Thanos library
- End-to-end testing with Ollama
- Performance benchmarking
- thanos.nvim polish
