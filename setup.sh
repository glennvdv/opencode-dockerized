#!/bin/bash

# Setup script to initialize OpenCode configuration
# This helps new users get started quickly

set -e

# Source the shared config module (provides colors, logging, and config functions)
# Resolve symlinks so SCRIPT_DIR points to the real source directory
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/config-lib.sh"

# Define colors before use (config-lib.sh provides defaults via : "${VAR:=...}")
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}OpenCode Docker Setup${NC}"
echo "================================"
echo ""

# Function to create directory if it doesn't exist
ensure_dir() {
    if [ ! -d "$1" ]; then
        echo -e "${YELLOW}Creating directory: $1${NC}"
        mkdir -p "$1"
    else
        echo -e "${GREEN}✓${NC} Directory exists: $1"
    fi
}

# Function to ensure at least one of the files exists
# Creates the first file with default content if none exist
ensure_any_file() {
    local default_content="$1"
    shift
    local files=("$@")

    # Check if any file already exists
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${GREEN}✓${NC} Config file exists: $file"
            return 0
        fi
    done

    # None exist, create the first one
    local first_file="${files[0]}"
    echo -e "${YELLOW}Creating file: $first_file${NC}"
    mkdir -p "$(dirname "$first_file")"
    echo "$default_content" > "$first_file"
}

echo "Checking OpenCode configuration..."
echo ""

# Check/create OpenCode directories
ensure_dir "$HOME/.config/opencode"
ensure_dir "$HOME/.config/opencode/agent"
ensure_dir "$HOME/.config/opencode/plugin"
ensure_dir "$HOME/.config/opencode/command"
ensure_dir "$HOME/.local/share/opencode"
ensure_dir "$HOME/.local/state/opencode"
ensure_dir "$HOME/.cache/opencode"
ensure_dir "$HOME/.cache/oh-my-opencode"
ensure_dir "$HOME/.mcp-auth"

# Check/create OpenCode config files
ensure_any_file '{}' "$HOME/.config/opencode/opencode.json" "$HOME/.config/opencode/opencode.jsonc"

# Copy OpenSpec config if not already present
ensure_dir "$HOME/.config/openspec"
if [ ! -f "$HOME/.config/openspec/config.json" ]; then
    if [ -f "$SCRIPT_DIR/config/openspec/config.json" ]; then
        cp "$SCRIPT_DIR/config/openspec/config.json" "$HOME/.config/openspec/config.json"
        echo -e "${GREEN}✓${NC} Copied OpenSpec config to ~/.config/openspec/config.json"
    else
        print_warning "OpenSpec config template not found at $SCRIPT_DIR/config/openspec/config.json"
    fi
else
    echo -e "${GREEN}✓${NC} OpenSpec config already exists at ~/.config/openspec/config.json"
fi

interactive_config_setup

# Shell completions setup
echo ""
echo -e "${BLUE}Shell Completions Setup${NC}"

# Helper functions for completions (defined before use)
install_bash_completion() {
    local bash_rc="$HOME/.bashrc"
    local completion_line="[ -f \"$SCRIPT_DIR/completions/bash.sh\" ] && source \"$SCRIPT_DIR/completions/bash.sh\""
    
    if grep -qF "$completion_line" "$bash_rc" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Bash completion already configured in ~/.bashrc"
    else
        echo "" >> "$bash_rc"
        echo "# OpenCode Dockerized completion" >> "$bash_rc"
        echo "$completion_line" >> "$bash_rc"
        echo -e "${GREEN}✓${NC} Added bash completion to ~/.bashrc"
        echo -e "${YELLOW}  Run: source ~/.bashrc${NC}"
    fi
}

install_zsh_completion() {
    local zsh_rc="$HOME/.zshrc"
    local completion_line="[ -f \"$SCRIPT_DIR/completions/zsh.sh\" ] && source \"$SCRIPT_DIR/completions/zsh.sh\""
    
    if grep -qF "$completion_line" "$zsh_rc" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Zsh completion already configured in ~/.zshrc"
    else
        echo "" >> "$zsh_rc"
        echo "# OpenCode Dockerized completion" >> "$zsh_rc"
        echo "$completion_line" >> "$zsh_rc"
        echo -e "${GREEN}✓${NC} Added zsh completion to ~/.zshrc"
        echo -e "${YELLOW}  Run: source ~/.zshrc${NC}"
    fi
}

# Check if completions are already installed
bash_completion_line="[ -f \"$SCRIPT_DIR/completions/bash.sh\" ] && source \"$SCRIPT_DIR/completions/bash.sh\""
zsh_completion_line="[ -f \"$SCRIPT_DIR/completions/zsh.sh\" ] && source \"$SCRIPT_DIR/completions/zsh.sh\""
bash_completion_installed=false
zsh_completion_installed=false

if [ -f "$HOME/.bashrc" ] && grep -qF "$bash_completion_line" "$HOME/.bashrc" 2>/dev/null; then
    bash_completion_installed=true
fi
if [ -f "$HOME/.zshrc" ] && grep -qF "$zsh_completion_line" "$HOME/.zshrc" 2>/dev/null; then
    zsh_completion_installed=true
fi

if [ "$bash_completion_installed" = true ] && [ "$zsh_completion_installed" = true ]; then
    echo -e "${GREEN}✓${NC} Shell completions already configured (bash + zsh)"
    read -r -p "Reconfigure completions? (y/N): " reconfigure_completions
    [[ "$reconfigure_completions" =~ ^[Yy]$ ]] || install_completions="skip"
elif [ "$bash_completion_installed" = true ]; then
    echo -e "${GREEN}✓${NC} Bash completion already configured"
    echo "Would you like to also install zsh completions?"
    read -r -p "Install zsh completions? (y/N): " install_zsh_only
    if [[ "$install_zsh_only" =~ ^[Yy]$ ]]; then
        install_zsh_completion
    fi
    install_completions="skip"
elif [ "$zsh_completion_installed" = true ]; then
    echo -e "${GREEN}✓${NC} Zsh completion already configured"
    echo "Would you like to also install bash completions?"
    read -r -p "Install bash completions? (y/N): " install_bash_only
    if [[ "$install_bash_only" =~ ^[Yy]$ ]]; then
        install_bash_completion
    fi
    install_completions="skip"
fi

if [ "${install_completions:-}" != "skip" ]; then
    echo "Would you like to install shell completions? (enables tab completion for commands)"
    read -r -p "Install completions? (y/n): " install_completions

    if [[ "$install_completions" =~ ^[Yy]$ ]]; then
        # Detect shell
        detected_shell=""
        if [ -n "$BASH_VERSION" ]; then
            detected_shell="bash"
        elif [ -n "$ZSH_VERSION" ]; then
            detected_shell="zsh"
        fi

        echo ""
        echo "Detected shell: ${detected_shell:-unknown}"
        echo "Available completions:"
        echo "  1) bash"
        echo "  2) zsh"
        echo "  3) both"
        echo "  4) skip"
        read -r -p "Select option (1-4): " shell_choice

        case "$shell_choice" in
            1)
                install_bash_completion
                ;;
            2)
                install_zsh_completion
                ;;
            3)
                install_bash_completion
                install_zsh_completion
                ;;
            4)
                echo "Skipping completions installation."
                ;;
            *)
                echo -e "${YELLOW}Invalid choice, skipping completions.${NC}"
                ;;
        esac
    else
        echo "Skipping completions installation."
    fi
fi

# Shell aliases setup
echo ""
echo -e "${BLUE}Shell Aliases Setup${NC}"

# Helper functions for aliases (defined before use)
install_bash_aliases() {
    local bash_rc="$HOME/.bashrc"
    local alias_marker="# OpenCode Dockerized aliases"
    local alias_ocd="alias ocd='$SCRIPT_DIR/opencode-dockerized.sh'"
    local alias_ocd_run="alias ocd-run='$SCRIPT_DIR/opencode-dockerized.sh run'"
    local alias_ocd_auth="alias ocd-auth='$SCRIPT_DIR/opencode-dockerized.sh auth'"
    
    if grep -qF "$alias_marker" "$bash_rc" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Bash aliases already configured in ~/.bashrc"
    else
        echo "" >> "$bash_rc"
        echo "$alias_marker" >> "$bash_rc"
        echo "$alias_ocd" >> "$bash_rc"
        echo "$alias_ocd_run" >> "$bash_rc"
        echo "$alias_ocd_auth" >> "$bash_rc"
        echo -e "${GREEN}✓${NC} Added aliases to ~/.bashrc"
        echo -e "${YELLOW}  Run: source ~/.bashrc${NC}"
    fi
}

install_zsh_aliases() {
    local zsh_rc="$HOME/.zshrc"
    local alias_marker="# OpenCode Dockerized aliases"
    local alias_ocd="alias ocd='$SCRIPT_DIR/opencode-dockerized.sh'"
    local alias_ocd_run="alias ocd-run='$SCRIPT_DIR/opencode-dockerized.sh run'"
    local alias_ocd_auth="alias ocd-auth='$SCRIPT_DIR/opencode-dockerized.sh auth'"
    
    if grep -qF "$alias_marker" "$zsh_rc" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Zsh aliases already configured in ~/.zshrc"
    else
        echo "" >> "$zsh_rc"
        echo "$alias_marker" >> "$zsh_rc"
        echo "$alias_ocd" >> "$zsh_rc"
        echo "$alias_ocd_run" >> "$zsh_rc"
        echo "$alias_ocd_auth" >> "$zsh_rc"
        echo -e "${GREEN}✓${NC} Added aliases to ~/.zshrc"
        echo -e "${YELLOW}  Run: source ~/.zshrc${NC}"
    fi
}

# Check if aliases are already installed
alias_marker="# OpenCode Dockerized aliases"
bash_aliases_installed=false
zsh_aliases_installed=false

if [ -f "$HOME/.bashrc" ] && grep -qF "$alias_marker" "$HOME/.bashrc" 2>/dev/null; then
    bash_aliases_installed=true
fi
if [ -f "$HOME/.zshrc" ] && grep -qF "$alias_marker" "$HOME/.zshrc" 2>/dev/null; then
    zsh_aliases_installed=true
fi

setup_aliases="ask"
if [ "$bash_aliases_installed" = true ] && [ "$zsh_aliases_installed" = true ]; then
    echo -e "${GREEN}✓${NC} Shell aliases already configured (bash + zsh)"
    read -r -p "Reconfigure aliases? (y/N): " reconfigure_aliases
    [[ "$reconfigure_aliases" =~ ^[Yy]$ ]] || setup_aliases="skip"
elif [ "$bash_aliases_installed" = true ]; then
    echo -e "${GREEN}✓${NC} Bash aliases already configured"
    echo "Would you like to also install zsh aliases?"
    read -r -p "Install zsh aliases? (y/N): " install_zsh_aliases_only
    if [[ "$install_zsh_aliases_only" =~ ^[Yy]$ ]]; then
        install_zsh_aliases
    fi
    setup_aliases="skip"
elif [ "$zsh_aliases_installed" = true ]; then
    echo -e "${GREEN}✓${NC} Zsh aliases already configured"
    echo "Would you like to also install bash aliases?"
    read -r -p "Install bash aliases? (y/N): " install_bash_aliases_only
    if [[ "$install_bash_aliases_only" =~ ^[Yy]$ ]]; then
        install_bash_aliases
    fi
    setup_aliases="skip"
fi

if [ "$setup_aliases" != "skip" ]; then
    echo "Would you like to set up convenient aliases for opencode-dockerized.sh?"
    echo "This will create short aliases like 'ocd' for easier command access."
    read -r -p "Setup aliases? (y/n): " setup_aliases

    if [[ "$setup_aliases" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Recommended aliases:"
        echo "  ocd       -> opencode-dockerized.sh"
        echo "  ocd-run   -> opencode-dockerized.sh run"
        echo "  ocd-auth  -> opencode-dockerized.sh auth"
        echo ""
        echo "Available shells:"
        echo "  1) bash"
        echo "  2) zsh"
        echo "  3) both"
        echo "  4) skip"
        read -r -p "Select option (1-4): " alias_shell_choice

        case "$alias_shell_choice" in
            1)
                install_bash_aliases
                ;;
            2)
                install_zsh_aliases
                ;;
            3)
                install_bash_aliases
                install_zsh_aliases
                ;;
            4)
                echo "Skipping aliases installation."
                ;;
            *)
                echo -e "${YELLOW}Invalid choice, skipping aliases.${NC}"
                ;;
        esac
    else
        echo "Skipping aliases installation."
    fi
fi

# Global install (symlink to PATH)
echo ""
echo -e "${BLUE}Global Installation${NC}"

INSTALL_DIR="$HOME/.local/bin"
LINK_NAME="opencode-dockerized"
TARGET_SCRIPT="$SCRIPT_DIR/opencode-dockerized.sh"

# Check if global install is already configured correctly
global_already_installed=false
if [ -L "$INSTALL_DIR/$LINK_NAME" ]; then
    existing_target="$(readlink -f "$INSTALL_DIR/$LINK_NAME")"
    if [ "$existing_target" = "$(readlink -f "$TARGET_SCRIPT")" ]; then
        global_already_installed=true
    fi
fi

if [ "$global_already_installed" = true ]; then
    echo -e "${GREEN}✓${NC} Already installed globally: $INSTALL_DIR/$LINK_NAME"
    if echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        echo -e "${GREEN}✓${NC} $INSTALL_DIR is in PATH"
    else
        echo -e "${YELLOW}⚠${NC} $INSTALL_DIR is not in your PATH (add it for the command to work)"
    fi
else
    echo "Install 'opencode-dockerized' as a command available from any directory."
    echo "This creates a symlink in ~/.local/bin (added to PATH if needed)."
    read -r -p "Install globally? (y/n): " install_global

    if [[ "$install_global" =~ ^[Yy]$ ]]; then
        # Ensure install directory exists
        mkdir -p "$INSTALL_DIR"

        # Create or update symlink
        if [ -L "$INSTALL_DIR/$LINK_NAME" ]; then
            ln -sf "$TARGET_SCRIPT" "$INSTALL_DIR/$LINK_NAME"
            echo -e "${GREEN}✓${NC} Updated symlink: $INSTALL_DIR/$LINK_NAME -> $TARGET_SCRIPT"
        elif [ -e "$INSTALL_DIR/$LINK_NAME" ]; then
            echo -e "${YELLOW}⚠${NC} $INSTALL_DIR/$LINK_NAME already exists and is not a symlink. Skipping."
        else
            ln -s "$TARGET_SCRIPT" "$INSTALL_DIR/$LINK_NAME"
            echo -e "${GREEN}✓${NC} Created symlink: $INSTALL_DIR/$LINK_NAME -> $TARGET_SCRIPT"
        fi

        # Check if ~/.local/bin is in PATH
        if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
            echo -e "${YELLOW}⚠${NC} $INSTALL_DIR is not in your PATH."
            echo ""

            # Try to add it to the appropriate shell rc file
            path_line="export PATH=\"\$HOME/.local/bin:\$PATH\""
            added_to_rc=false

            if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
                rc_file="$HOME/.zshrc"
                if ! grep -qF '.local/bin' "$rc_file" 2>/dev/null; then
                    echo "" >> "$rc_file"
                    echo "# Added by opencode-dockerized setup" >> "$rc_file"
                    echo "$path_line" >> "$rc_file"
                    echo -e "${GREEN}✓${NC} Added ~/.local/bin to PATH in ~/.zshrc"
                    added_to_rc=true
                fi
            fi

            if [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
                rc_file="$HOME/.bashrc"
                if ! grep -qF '.local/bin' "$rc_file" 2>/dev/null; then
                    echo "" >> "$rc_file"
                    echo "# Added by opencode-dockerized setup" >> "$rc_file"
                    echo "$path_line" >> "$rc_file"
                    echo -e "${GREEN}✓${NC} Added ~/.local/bin to PATH in ~/.bashrc"
                    added_to_rc=true
                fi
            fi

            if [ "$added_to_rc" = true ]; then
                echo -e "${YELLOW}  Restart your shell or run: source ~/.bashrc (or ~/.zshrc)${NC}"
            else
                echo "  Add this to your shell rc file:"
                echo "    $path_line"
            fi
        else
            echo -e "${GREEN}✓${NC} $INSTALL_DIR is already in PATH"
        fi

        echo ""
        echo "  You can now run 'opencode-dockerized' from any directory:"
        echo "    opencode-dockerized run"
        echo "    opencode-dockerized build"
        echo "    opencode-dockerized auth"
    else
        echo "Skipping global installation."
        echo "  You can always run it directly: $SCRIPT_DIR/opencode-dockerized.sh"
    fi
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Build the Docker image:"
echo "     opencode-dockerized build"
echo ""
echo "  2. Authenticate with your LLM provider (no local OpenCode needed!):"
echo "     opencode-dockerized auth"
echo ""
echo "  3. Run OpenCode in your project:"
echo "     opencode-dockerized run /path/to/your/project"
echo ""

# Show OpenSpec instructions only if it was enabled
if [ "$OPENSPEC_SUPPORT" = true ]; then
    echo "  4. OpenSpec will automatically initialize when you first run OpenCode"
    echo "     in a project that doesn't have an openspec/ directory yet."
    echo "     It runs: openspec init --tools opencode && openspec update"
    echo ""
fi

echo "Note: If you already have OpenCode configured locally, your"
echo "      existing authentication will be automatically available."
echo ""
