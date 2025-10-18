# thanos.grim

<div align="center">
  <img src="assets/icons/thanos.png" alt="Thanos logo" width="200" height="200">

**Universal AI Assistant Plugin for Grim Editor**

*Talk to Claude, GPT-4, Grok, Ollama, and more—all from Grim*

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig%200.16-yellow?logo=zig&style=for-the-badge)
![Grim Plugin](https://img.shields.io/badge/Editor-Grim-gray?style=for-the-badge)
![Multi-Provider](https://img.shields.io/badge/Providers-7+-purple?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

[![GitHub Stars](https://img.shields.io/github/stars/ghostkellz/thanos.grim?style=social)](https://github.com/ghostkellz/thanos.grim)
[![Issues](https://img.shields.io/github/issues/ghostkellz/thanos.grim)](https://github.com/ghostkellz/thanos.grim/issues)

</div>

---

## 🌟 Overview

**thanos.grim** is a native Zig plugin that brings the power of the [Thanos AI Gateway](https://github.com/ghostkellz/thanos) directly into the Grim editor. Get AI-powered code completions, explanations, and assistance from multiple providers without leaving your editor.

### Why Thanos.grim?

- 🚀 **Native Performance** - Written in Zig, no FFI overhead
- 🎯 **Multi-Provider** - Switch between Claude, GPT-4, Ollama, and more
- 💰 **Cost Optimized** - Built-in caching and intelligent routing via Omen
- 🔒 **Privacy First** - Local-first with Ollama, cloud when you need it
- ⚡ **Zero Config** - Works out of the box with sensible defaults
- 🛠️ **Extensible** - Full access to Thanos orchestration layer

---

## ✨ Features

### Core Capabilities

- ✅ **Code Completion** - Inline AI completions like GitHub Copilot
- ✅ **AI Chat** - Ask questions about your code
- ✅ **Multi-Provider Support** - Claude, GPT-4, Grok, Ollama, GitHub Copilot
- ✅ **Smart Routing** - Automatic provider selection via Omen
- ✅ **Request Caching** - Save money with LRU cache + TTL
- ✅ **Retry Logic** - Exponential backoff with circuit breaker
- ✅ **Error Handling** - Comprehensive error types and recovery

### Supported Providers

| Provider | Status | Use Case |
|----------|--------|----------|
| 🦙 **Ollama** | ✅ | Local, free, privacy-focused |
| 🧠 **Anthropic Claude** | ✅ | Best for complex code generation |
| 🤖 **OpenAI GPT-4** | ✅ | General-purpose AI |
| 🚀 **xAI Grok** | ✅ | Fast, conversational |
| 🐙 **GitHub Copilot** | ✅ | If you have a subscription |
| 🌐 **Google Gemini** | ✅ | Multimodal support |
| 🔀 **Omen Gateway** | ✅ | Intelligent routing & cost optimization |

---

## 📦 Installation

### Prerequisites

- **Grim** >= 0.1.0 ([Install Guide](https://github.com/ghostkellz/grim))
- **Zig** >= 0.16.0-dev
- **Thanos** library ([Install Guide](https://github.com/ghostkellz/thanos))

### Option 1: Install via Zig Build (Recommended)

```bash
# 1. Clone the plugin
git clone https://github.com/ghostkellz/thanos.grim ~/.config/grim/plugins/thanos

# 2. Add Thanos dependency
cd ~/.config/grim/plugins/thanos
zig build

# 3. The plugin will auto-load when Grim starts
```

### Option 2: Use with Phantom.grim

[Phantom.grim](https://github.com/ghostkellz/phantom.grim) includes thanos.grim out-of-the-box:

```bash
git clone https://github.com/ghostkellz/phantom.grim ~/.config/grim
grim
# Thanos AI is ready to use!
```

### Option 3: Zig Package Manager

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .thanos_grim = .{
        .url = "https://github.com/ghostkellz/thanos.grim/archive/main.tar.gz",
        .hash = "1220...", // zig will tell you the hash
    },
},
```

---

## ⚙️ Configuration

### Default Configuration

thanos.grim uses sensible defaults from `~/.config/grim/thanos.toml`:

```toml
[general]
debug = false
preferred_provider = "anthropic"  # or "ollama" for local-first

[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"
model = "claude-sonnet-4-20250514"

[providers.ollama]
enabled = true
model = "codellama:latest"

[providers.omen]
enabled = true
routing_strategy = "cost-optimized"
```

### Custom Configuration

Create `~/.config/grim/thanos.toml` to override defaults:

```toml
[general]
preferred_provider = "ollama"  # Local-first!

[providers.ollama]
enabled = true
model = "deepseek-coder:latest"
endpoint = "http://localhost:11434"

[providers.anthropic]
enabled = true
api_key = "sk-ant-..."  # Or use environment variable
```

---

## 🎮 Usage

### Commands

Once loaded in Grim, thanos.grim exposes these functions via the plugin API:

```zig
// Complete code at cursor
:thanos complete

// Ask AI a question
:thanos ask "How do I implement a binary tree in Zig?"

// List available providers
:thanos providers

// Show statistics
:thanos stats

// Switch provider
:thanos switch ollama
```

### Keybindings (in Phantom.grim)

| Key | Action | Description |
|-----|--------|-------------|
| `<leader>ac` | AI Complete | Complete code at cursor |
| `<leader>aa` | AI Ask | Ask AI a question |
| `<leader>at` | AI Chat | Open chat window |
| `<leader>ap` | AI Providers | List providers |
| `<leader>as` | AI Stats | Show statistics |

### Programmatic Usage

```zig
const thanos_grim = @import("thanos_grim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize plugin
    var plugin = try thanos_grim.ThanosGrimPlugin.init(allocator);
    defer plugin.deinit();

    // Complete code
    const prompt = "fn fibonacci(n: usize) usize {";
    const completion = try plugin.complete(prompt, "zig");
    defer allocator.free(completion);

    std.debug.print("AI completion: {s}\n", .{completion});

    // List providers
    const providers = try plugin.listProviders();
    for (providers) |provider| {
        std.debug.print("Provider: {s} - Available: {}\n", .{
            provider.provider.toString(),
            provider.available,
        });
    }

    // Get stats
    const stats = try plugin.getStats();
    std.debug.print("Total requests: {}\n", .{stats.total_requests});
}
```

---

## 🛠️ Development

### Building from Source

```bash
# Clone repository
git clone https://github.com/ghostkellz/thanos.grim
cd thanos.grim

# Build
zig build

# Run tests
zig build test

# Install to Grim plugins directory
zig build install --prefix ~/.config/grim/plugins/thanos
```

### Project Structure

```
thanos.grim/
├── src/
│   ├── root.zig           # Plugin entry point
│   └── main.zig           # CLI tool (optional)
├── assets/
│   └── icons/
│       └── thanos.png     # Plugin logo
├── build.zig              # Zig build configuration
├── build.zig.zon          # Dependencies
└── README.md
```

### Running Tests

```bash
zig build test
```

---

## 🔗 Integration with Thanos

thanos.grim is a thin wrapper around the [Thanos library](https://github.com/ghostkellz/thanos). All the heavy lifting (HTTP requests, provider routing, caching, retry logic) is handled by Thanos.

```
┌─────────────────────────────────────┐
│ Grim Editor                         │
│  └─ thanos.grim (this plugin)      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Thanos Library (Zig)                │
│  ├─ Provider Discovery              │
│  ├─ Request Caching                 │
│  ├─ Retry Logic                     │
│  └─ Error Handling                  │
└──────────────┬──────────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌──────────┐      ┌──────────┐
│ Omen     │      │ Ollama   │
│ Gateway  │      │ (Local)  │
└────┬─────┘      └──────────┘
     │
  ┌──┴──┬──────┬─────────┐
  ▼     ▼      ▼         ▼
Claude GPT-4 Grok  Copilot
```

---

## 📊 Performance

- **Startup Time**: < 50ms (native Zig, no VM overhead)
- **Completion Latency**:
  - Ollama (local): ~200-500ms
  - Claude/GPT-4: ~1-3s (network dependent)
  - Cached responses: < 10ms
- **Memory Usage**: ~5MB (Thanos library + plugin state)

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Ways to Contribute

- 🐛 Report bugs
- 💡 Suggest features
- 🔧 Submit pull requests
- 📝 Improve documentation
- ⭐ Star the repo!

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🙏 Credits

Built with:
- **[Thanos](https://github.com/ghostkellz/thanos)** - Universal AI gateway
- **[Grim](https://github.com/ghostkellz/grim)** - Zig-powered editor
- **[Zig](https://ziglang.org/)** - Performance and safety

Inspired by:
- **[GitHub Copilot](https://copilot.github.com/)** - AI code completion
- **[Claude Code](https://claude.ai/claude-code)** - AI pair programming
- **[Zed AI](https://zed.dev/)** - Editor-native AI

---

## 🔗 Related Projects

- **[thanos](https://github.com/ghostkellz/thanos)** - Core AI gateway library
- **[thanos.nvim](https://github.com/ghostkellz/thanos.nvim)** - Neovim plugin
- **[phantom.grim](https://github.com/ghostkellz/phantom.grim)** - Full Grim distro with Thanos
- **[grim](https://github.com/ghostkellz/grim)** - The editor itself

---

<div align="center">

**Made with 🌌 by the Ghost Ecosystem**

[⭐ Star on GitHub](https://github.com/ghostkellz/thanos.grim) • [📖 Documentation](https://github.com/ghostkellz/thanos.grim/wiki) • [🐛 Report Bug](https://github.com/ghostkellz/thanos.grim/issues)

</div>
