#!/bin/bash

# Thanos.grim Installer
# AI plugin for Grim editor
# Powered by Thanos AI Gateway

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PLUGIN_NAME="thanos.grim"
PLUGIN_DIR="$HOME/.local/share/grim/plugins/thanos"
CONFIG_DIR="$HOME/.config/grim"
THANOS_LIB_NAME="libthanos_grim_bridge.so"

# Print functions
print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║         Thanos.grim Installer v0.2.0             ║"
    echo "║    AI-Powered Completions for Grim Editor        ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."

    # Check for Zig
    if ! command -v zig &> /dev/null; then
        print_error "Zig compiler not found (required version >= 0.16.0)"
        echo "  Install from: https://ziglang.org/download/"
        exit 1
    fi

    local zig_version=$(zig version)
    print_success "Zig $zig_version found"

    # Check for Grim
    if ! command -v grim &> /dev/null; then
        print_warning "Grim editor not found in PATH"
        print_warning "Install Grim first: cd /data/projects/grim && ./install.sh"
    else
        print_success "Grim editor found"
    fi

    # Check for Thanos library
    if [ ! -d "/data/projects/thanos" ]; then
        print_warning "Thanos library not found at /data/projects/thanos"
        print_warning "Some features may not work without Thanos core"
    else
        print_success "Thanos library found"
    fi

    # Check for Ollama (optional)
    if command -v ollama &> /dev/null; then
        print_success "Ollama found (local AI provider)"
    else
        print_warning "Ollama not found (optional local AI provider)"
        echo "  Install from: https://ollama.com"
    fi
}

# Build the bridge
build_bridge() {
    print_step "Building Thanos.grim FFI bridge..."

    # Build the native bridge
    if ! zig build bridge; then
        print_error "Build failed!"
        exit 1
    fi

    print_success "Bridge compiled successfully"

    # Check output
    if [ ! -f "zig-out/lib/$THANOS_LIB_NAME" ]; then
        print_error "Bridge library not found: zig-out/lib/$THANOS_LIB_NAME"
        exit 1
    fi

    local lib_size=$(du -h "zig-out/lib/$THANOS_LIB_NAME" | cut -f1)
    print_success "Library size: $lib_size"
}

# Install plugin
install_plugin() {
    print_step "Installing plugin to $PLUGIN_DIR..."

    # Create plugin directory
    mkdir -p "$PLUGIN_DIR"

    # Copy plugin files
    cp -r init.gza "$PLUGIN_DIR/"
    cp -r lua "$PLUGIN_DIR/" 2>/dev/null || true

    # Create lib directory
    mkdir -p "$PLUGIN_DIR/lib"

    # Copy native bridge
    cp "zig-out/lib/$THANOS_LIB_NAME" "$PLUGIN_DIR/lib/"

    # Copy README and docs
    cp README.md "$PLUGIN_DIR/" 2>/dev/null || true
    cp INSTALL.md "$PLUGIN_DIR/" 2>/dev/null || true

    print_success "Plugin files installed"
}

# Configure plugin
configure_plugin() {
    print_step "Configuring Thanos.grim..."

    # Create Grim config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"

    # Create thanos config file if it doesn't exist
    local thanos_config="$CONFIG_DIR/thanos.gza"

    if [ ! -f "$thanos_config" ]; then
        cat > "$thanos_config" << 'EOF'
-- Thanos.grim Configuration
-- AI completion settings for Grim editor

return {
  -- Mode: "hybrid", "ollama-heavy", "api-heavy"
  mode = "hybrid",

  -- Preferred provider (optional)
  -- Options: "ollama", "anthropic", "openai", "grok", "copilot", "gemini"
  preferred_provider = nil,  -- Auto-select by default

  -- Debug mode
  debug = false,

  -- API Keys (optional - can use environment variables)
  api_keys = {
    anthropic = os.getenv("ANTHROPIC_API_KEY"),
    openai = os.getenv("OPENAI_API_KEY"),
    xai = os.getenv("XAI_API_KEY"),
    github = os.getenv("GITHUB_TOKEN"),
    google = os.getenv("GOOGLE_API_KEY"),
  },

  -- Ollama settings
  ollama = {
    url = "http://localhost:11434",
    model = "codellama",  -- or "deepseek-coder", "qwen2.5-coder"
  },

  -- Ghost text (inline completion) settings
  ghost_text = {
    enabled = true,
    debounce_ms = 300,
    max_tokens = 50,
  },
}
EOF
        print_success "Created default config: $thanos_config"
    else
        print_success "Config already exists: $thanos_config"
    fi
}

# Check Ollama models
check_ollama() {
    if command -v ollama &> /dev/null; then
        print_step "Checking Ollama models..."

        # Check if Ollama is running
        if ! curl -s http://localhost:11434/api/tags &> /dev/null; then
            print_warning "Ollama not running. Start with: systemctl start ollama"
            return
        fi

        # List available models
        local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")

        if [ -z "$models" ]; then
            print_warning "No Ollama models installed"
            echo ""
            echo "  Recommended models for coding:"
            echo "    ollama pull codellama"
            echo "    ollama pull deepseek-coder"
            echo "    ollama pull qwen2.5-coder"
        else
            print_success "Ollama models found:"
            echo "$models" | while read model; do
                echo "    - $model"
            done
        fi
    fi
}

# Print next steps
print_next_steps() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗"
    echo -e "║        Thanos.grim Installed Successfully!       ║"
    echo -e "╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Configure your AI providers:"
    echo "   Edit: $CONFIG_DIR/thanos.gza"
    echo ""
    echo "2. Set up API keys (optional):"
    echo "   export ANTHROPIC_API_KEY='sk-ant-...'"
    echo "   export OPENAI_API_KEY='sk-...'"
    echo ""
    echo "3. Install Ollama models (recommended):"
    echo "   ollama pull codellama"
    echo ""
    echo "4. Launch Grim and try AI completion:"
    echo "   grim"
    echo "   :ThanosComplete Write a function to reverse a string"
    echo ""
    echo "Commands:"
    echo "  :ThanosComplete <prompt>    - AI code completion"
    echo "  :ThanosAsk <question>       - Ask AI a question"
    echo "  :ThanosChat                 - Open AI chat"
    echo "  :ThanosProviders            - List available providers"
    echo "  :ThanosSwitch <provider>    - Switch AI provider"
    echo "  :ThanosStats                - Show usage statistics"
    echo "  :ThanosHealth               - Check provider health"
    echo ""
    echo "Documentation:"
    echo "  README: $PLUGIN_DIR/README.md"
    echo "  Config: $CONFIG_DIR/thanos.gza"
    echo ""
}

# Main installation flow
main() {
    print_header

    # Get script directory and go to project root
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
    cd "$SCRIPT_DIR"

    check_prerequisites
    build_bridge
    install_plugin
    configure_plugin
    check_ollama
    print_next_steps

    echo -e "${GREEN}Installation complete!${NC} 🚀"
}

# Run main function
main "$@"
