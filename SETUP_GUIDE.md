# Thanos.grim Setup Guide

**Status**: Ready to install! 🚀

This guide shows you how to get `:Thanos` working in Grim editor (just like `:Claude-Code`).

---

## Prerequisites

1. **Grim editor** installed at `/data/projects/grim`
2. **API Keys** for providers you want to use (optional, Ollama works without keys)
3. **Zig 0.16+** (already used to build thanos.grim)

---

## Quick Start (5 Minutes)

### Step 1: Install Plugin to Grim

```bash
# Create plugin directory
mkdir -p ~/.config/grim/plugins/thanos

# Copy plugin files
cp -r /data/projects/thanos.grim/* ~/.config/grim/plugins/thanos/

# Copy built libraries
cp /data/projects/thanos.grim/zig-out/lib/*.so ~/.config/grim/plugins/thanos/native/
```

### Step 2: Configure API Keys

Create or edit `~/.config/grim/plugins/thanos/thanos.toml`:

```toml
[ai]
mode = "hybrid"
primary_provider = "ollama"  # Start with free local model

[general]
debug = true
request_timeout_ms = 30000

# --- Provider Configuration ---

[providers.ollama]
enabled = true
endpoint = "http://localhost:11434"
model = "codellama:13b"
# Install with: ollama pull codellama:13b

[providers.anthropic]
enabled = true
api_key = "sk-ant-..."  # Get from: https://console.anthropic.com/
model = "claude-3-5-sonnet-20241022"
max_tokens = 4096
temperature = 0.7

[providers.openai]
enabled = true
api_key = "sk-proj-..."  # Get from: https://platform.openai.com/api-keys
model = "gpt-4-turbo"
max_tokens = 4096
temperature = 0.7

[providers.xai]
enabled = true
api_key = "xai-..."  # Get from: https://x.ai/api
model = "grok-beta"
max_tokens = 4096
temperature = 0.7

[providers.github_copilot]
enabled = true
# No API key needed! Auto-fetches from: gh auth token
# Setup: gh auth login --scopes copilot

# --- Routing Configuration ---

[routing]
# Chat: conversational AI
chat = "anthropic"  # or "openai", "xai", "ollama"
fallback_chain = ["anthropic", "openai", "xai", "ollama"]

# Autocomplete: fast code completion
autocomplete = "github_copilot"
fallback_autocomplete = ["ollama"]
```

### Step 3: Set Environment Variables (Optional)

Instead of hardcoding keys in TOML, you can use environment variables:

```bash
# Add to ~/.bashrc or ~/.zshrc
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-proj-..."
export XAI_API_KEY="xai-..."
```

Then in `thanos.toml`, use:
```toml
[providers.anthropic]
api_key = "${ANTHROPIC_API_KEY}"
```

### Step 4: Start Grim

```bash
cd /data/projects/grim
zig build run
```

---

## Usage

### Commands

Once Grim loads the plugin, you'll have these commands:

| Command | Keybind | Description |
|---------|---------|-------------|
| `:Thanos` | `<leader>ac` | **Open AI chat** (like Claude Code) |
| `:ThanosChat` | `<leader>ac` | Same as above |
| `:ThanosComplete` | `<leader>ak` | AI code completion at cursor |
| `:ThanosAsk <question>` | - | Quick question to AI |
| `:ThanosSwitch <provider>` | `<leader>ap` | Switch provider |
| `:ThanosProviders` | - | List available providers |
| `:ThanosStats` | `<leader>as` | Show usage stats |
| `:ThanosHealth` | `<leader>ah` | Check provider health |

### Keybindings (Default Leader: Space)

```
<Space>ac   - Open AI chat
<Space>ak   - AI complete code
<Space>ap   - Switch provider
<Space>as   - Show stats
<Space>ah   - Health check
```

### Example Workflow

```vim
# 1. Open a file
:e mycode.zig

# 2. Type some code, press <Space>ak for completion
fn fibonacci(
  <Space>ak   # AI completes: n: u32) u32 { ... }

# 3. Ask a question
:ThanosAsk How do I handle errors in Zig?

# 4. Open interactive chat
:Thanos
  # Chat window opens, type messages and press Enter

# 5. Switch to a different provider
:ThanosSwitch ollama
  # Now using local Ollama instead of Claude

# 6. Check what's available
:ThanosProviders
  # Shows: Ollama ✅, Claude ✅, GPT-4 ✅, Copilot ⚠️ (not auth'd)
```

---

## Provider Setup Guides

### Ollama (Recommended First - Free & Local)

```bash
# 1. Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# 2. Pull a code model
ollama pull codellama:13b    # 7GB, good quality
# or
ollama pull deepseek-coder:6.7b  # 4GB, faster

# 3. Start Ollama server
ollama serve  # Runs on http://localhost:11434

# 4. Test it
curl http://localhost:11434/api/generate -d '{
  "model": "codellama:13b",
  "prompt": "Write a hello world in Zig"
}'
```

**Pros**: Free, private, works offline, fast (with good GPU)
**Cons**: Requires local compute (8GB+ RAM recommended)

---

### GitHub Copilot (Best for Autocomplete)

```bash
# 1. Authenticate with GitHub CLI
gh auth login --scopes copilot

# 2. Verify authentication
gh auth token  # Should print a token

# 3. Enable in thanos.toml
[providers.github_copilot]
enabled = true
```

**Pros**: Best autocomplete quality, fast (500ms), $10/month subscription
**Cons**: Requires subscription, sends code to GitHub

---

### Anthropic Claude (Best for Complex Reasoning)

```bash
# 1. Get API key
# Visit: https://console.anthropic.com/settings/keys
# Create a new API key

# 2. Set environment variable
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# 3. Test it
curl https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello, Claude"}]
  }'
```

**Pricing**: $3/$15 per 1M tokens (input/output)
**Pros**: Best reasoning, large context (200k tokens), code quality
**Cons**: Pay per use, slower than Ollama (1-3s)

---

### OpenAI GPT-4

```bash
# 1. Get API key
# Visit: https://platform.openai.com/api-keys

# 2. Set environment variable
export OPENAI_API_KEY="sk-proj-..."

# 3. Test it
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

**Pricing**: $10/$30 per 1M tokens
**Pros**: Versatile, good quality, widely supported
**Cons**: More expensive than Claude

---

### xAI Grok

```bash
# 1. Get API key
# Visit: https://x.ai/api

# 2. Set environment variable
export XAI_API_KEY="xai-..."

# 3. Test it
curl https://api.x.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -d '{
    "model": "grok-beta",
    "messages": [{"role": "user", "content": "Hello Grok!"}]
  }'
```

**Pricing**: $5/$15 per 1M tokens
**Pros**: Fast, conversational, cheaper than GPT-4
**Cons**: Newer, less mature than Claude/GPT

---

## Troubleshooting

### Plugin not loading

```bash
# Check if plugin is discovered
ls -la ~/.config/grim/plugins/thanos/

# Should see:
# - plugin.toml
# - init.gza
# - native/libthanos_grim_bridge.so

# Check Grim logs
tail -f ~/.local/share/grim/logs/grim.log
```

### "Thanos not initialized" error

The FFI bridge failed to load. Check:

```bash
# 1. Verify library exists
ls -lh ~/.config/grim/plugins/thanos/native/*.so

# 2. Check library dependencies
ldd ~/.config/grim/plugins/thanos/native/libthanos_grim_bridge.so

# 3. Set explicit library path
export THANOS_GRIM_LIB="$HOME/.config/grim/plugins/thanos/native/libthanos_grim_bridge.so"
```

### Provider not available

```bash
# Check provider health
:ThanosHealth

# For Ollama
curl http://localhost:11434/api/tags  # Should list models

# For API providers
echo $ANTHROPIC_API_KEY  # Should print key
echo $OPENAI_API_KEY
echo $XAI_API_KEY

# For GitHub Copilot
gh auth status  # Should show: Logged in to github.com as <user>
```

### Completions too slow

```bash
# 1. Use faster providers
:ThanosSwitch ollama  # Local is fastest

# 2. Reduce max_tokens in thanos.toml
[providers.ollama]
max_tokens = 100  # Default is 2048

# 3. Use smaller Ollama models
ollama pull codellama:7b  # Faster than 13b
```

---

## Configuration Tips

### Cost Optimization (Use Free Ollama for Most Tasks)

```toml
[routing]
# Use free Ollama for everything except complex reasoning
chat = "ollama"
autocomplete = "ollama"
fallback_chain = ["ollama", "anthropic"]  # Only use Claude if Ollama fails
```

**Estimated savings**: 90%+ (most tasks work fine with local models)

### Quality First (Use Claude for Everything)

```toml
[routing]
chat = "anthropic"
autocomplete = "anthropic"
fallback_chain = ["anthropic", "openai", "ollama"]
```

**Estimated cost**: $5-20/day for heavy usage

### Balanced (Copilot + Ollama + Claude)

```toml
[routing]
autocomplete = "github_copilot"  # Fast, included in subscription
chat = "ollama"  # Free for quick questions
fallback_chain = ["ollama", "anthropic"]  # Claude for hard problems
```

**Estimated cost**: $10/month (Copilot) + ~$20/month (Claude for complex tasks)

---

## What's Next?

### Planned Features (Coming Soon)

- [ ] **Streaming responses** - See AI output token-by-token
- [ ] **Multi-file context** - AI sees your whole project
- [ ] **Code review mode** - AI reviews your changes
- [ ] **Inline ghost text** - Copilot-style completions as you type
- [ ] **Custom system prompts** - Tailor AI behavior per project
- [ ] **Cost budgets** - Set daily/monthly spending limits

### Contributing

Want to add a provider or feature? Check:
- `/data/projects/thanos/src/clients/` - Provider clients
- `/data/projects/thanos.grim/src/` - Plugin core
- `/data/projects/thanos.grim/init.gza` - UI layer

---

## Support

**Issues**: File at https://github.com/ghostkellz/thanos.grim/issues
**Docs**: See `/data/projects/thanos.grim/IMPLEMENTATION_COMPLETE.md`
**Examples**: See `/data/projects/grim/plugins/examples/`

---

**Built with ❤️ for the Ghost Ecosystem**

🌌 **Thanos.grim** - Universal AI for Grim Editor
