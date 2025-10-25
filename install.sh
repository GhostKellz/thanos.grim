#!/bin/bash
# Thanos.grim Installation Script
# Install thanos.grim plugin for Grim editor

set -e

echo "🌌 Thanos.grim Installation"
echo "=============================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect plugin directory
PLUGIN_DIR="${HOME}/.config/grim/plugins/thanos"
THANOS_GRIM_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${YELLOW}→${NC} Plugin will be installed to: ${PLUGIN_DIR}"
echo ""

# Step 1: Create plugin directory
echo -e "${YELLOW}→${NC} Creating plugin directory..."
mkdir -p "${PLUGIN_DIR}/native"
echo -e "${GREEN}✓${NC} Directory created"

# Step 2: Copy plugin files
echo -e "${YELLOW}→${NC} Copying plugin files..."
cp "${THANOS_GRIM_DIR}/plugin.toml" "${PLUGIN_DIR}/"
cp "${THANOS_GRIM_DIR}/init.gza" "${PLUGIN_DIR}/"
cp "${THANOS_GRIM_DIR}/thanos.toml" "${PLUGIN_DIR}/"
echo -e "${GREEN}✓${NC} Plugin files copied"

# Step 3: Build and copy native libraries
echo -e "${YELLOW}→${NC} Building native libraries..."
cd "${THANOS_GRIM_DIR}"
zig build -Doptimize=ReleaseFast

if [ ! -f "zig-out/lib/libthanos_grim_bridge.so" ]; then
    echo -e "${RED}✗${NC} Build failed! Library not found."
    exit 1
fi

cp zig-out/lib/libthanos_grim_bridge.so "${PLUGIN_DIR}/native/"
cp zig-out/lib/libthanos_grim.so "${PLUGIN_DIR}/native/"
echo -e "${GREEN}✓${NC} Native libraries built and copied"

# Step 4: Check for Ollama
echo ""
echo -e "${YELLOW}→${NC} Checking for Ollama..."
if command -v ollama &> /dev/null; then
    echo -e "${GREEN}✓${NC} Ollama found!"

    # Check if codellama is installed
    if ollama list | grep -q "codellama"; then
        echo -e "${GREEN}✓${NC} CodeLlama model installed"
    else
        echo -e "${YELLOW}!${NC} CodeLlama not installed"
        echo ""
        read -p "Install CodeLlama:13b? (7GB download) [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ollama pull codellama:13b
            echo -e "${GREEN}✓${NC} CodeLlama installed"
        fi
    fi
else
    echo -e "${YELLOW}!${NC} Ollama not found"
    echo "  Install from: https://ollama.com/download"
    echo "  Or run: curl -fsSL https://ollama.com/install.sh | sh"
fi

# Step 5: Check for GitHub CLI
echo ""
echo -e "${YELLOW}→${NC} Checking for GitHub CLI..."
if command -v gh &> /dev/null; then
    echo -e "${GREEN}✓${NC} GitHub CLI found"

    # Check if authenticated
    if gh auth status &> /dev/null; then
        echo -e "${GREEN}✓${NC} GitHub authenticated"
    else
        echo -e "${YELLOW}!${NC} Not authenticated with GitHub"
        echo ""
        read -p "Authenticate now for GitHub Copilot? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gh auth login --scopes copilot
        fi
    fi
else
    echo -e "${YELLOW}!${NC} GitHub CLI not found"
    echo "  Install from: https://cli.github.com/"
fi

# Step 6: Check for API keys
echo ""
echo -e "${YELLOW}→${NC} Checking for API keys..."

if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "${GREEN}✓${NC} ANTHROPIC_API_KEY set"
else
    echo -e "${YELLOW}!${NC} ANTHROPIC_API_KEY not set"
    echo "  Get key from: https://console.anthropic.com/settings/keys"
    echo "  Add to ~/.bashrc: export ANTHROPIC_API_KEY=\"sk-ant-...\""
fi

if [ -n "$OPENAI_API_KEY" ]; then
    echo -e "${GREEN}✓${NC} OPENAI_API_KEY set"
else
    echo -e "${YELLOW}!${NC} OPENAI_API_KEY not set"
    echo "  Get key from: https://platform.openai.com/api-keys"
    echo "  Add to ~/.bashrc: export OPENAI_API_KEY=\"sk-proj-...\""
fi

if [ -n "$XAI_API_KEY" ]; then
    echo -e "${GREEN}✓${NC} XAI_API_KEY set"
else
    echo -e "${YELLOW}!${NC} XAI_API_KEY not set"
    echo "  Get key from: https://x.ai/api"
    echo "  Add to ~/.bashrc: export XAI_API_KEY=\"xai-...\""
fi

# Step 7: Configuration summary
echo ""
echo "=============================="
echo -e "${GREEN}✓ Installation Complete!${NC}"
echo "=============================="
echo ""
echo "Plugin installed to: ${PLUGIN_DIR}"
echo ""
echo "Next steps:"
echo "  1. Edit ${PLUGIN_DIR}/thanos.toml to configure providers"
echo "  2. Restart Grim editor"
echo "  3. Run :Thanos to open AI chat"
echo ""
echo "Commands available in Grim:"
echo "  :Thanos            - Open AI chat (like :Claude-Code)"
echo "  :ThanosComplete    - AI code completion"
echo "  :ThanosSwitch      - Switch provider"
echo "  :ThanosProviders   - List providers"
echo ""
echo "Keybindings:"
echo "  <Space>ac          - Open AI chat"
echo "  <Space>ak          - AI complete code"
echo "  <Space>ap          - Switch provider"
echo "  <Space>as          - Show stats"
echo ""
echo "Documentation: ${THANOS_GRIM_DIR}/SETUP_GUIDE.md"
echo ""
echo "🌌 Enjoy Thanos.grim!"
