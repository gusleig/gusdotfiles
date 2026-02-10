#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ask user yes/no (default no when non-interactive)
ask_yes_no() {
    local prompt="$1"
    if [ ! -t 0 ]; then
        echo "n"
        return
    fi
    local answer
    read -r -p "$prompt [y/N]: " answer
    case "${answer:-n}" in
        [yY]|[yY][eE][sS]) echo "y" ;;
        *) echo "n" ;;
    esac
}

# Ask user to choose between options (returns 1 or 2; default 1 when non-interactive)
ask_choice() {
    local prompt="$1"
    local opt1="$2"
    local opt2="$3"
    if [ ! -t 0 ]; then
        echo "1"
        return
    fi
    local answer
    read -r -p "$prompt [1/2] (default 1): " answer
    case "${answer:-1}" in
        2) echo "2" ;;
        *) echo "1" ;;
    esac
}

# Portable sed -i (macOS requires sed -i '' for in-place with no backup)
sed_in_place() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Update installed software (Homebrew, Oh My Zsh plugins, etc.)
update_software() {
    echo "================================================="
    echo "Updating installed software..."
    echo "================================================="
    if command_exists brew; then
        echo "Updating Homebrew and formulae..."
        brew update && brew upgrade
        echo "Updating casks..."
        brew upgrade --cask
    fi
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "Updating Oh My Zsh..."
        (cd "$HOME/.oh-my-zsh" && git pull)
        if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
            echo "Updating Powerlevel10k..."
            (cd "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" && git pull)
        fi
        for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
            if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin" ]; then
                echo "Updating $plugin..."
                (cd "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin" && git pull)
            fi
        done
    fi
    echo "Software update complete."
}

# Function to create symlinks for dotfiles
create_symlinks() {
    echo "Creating symlinks for dotfiles..."
    for file in "$HOME/.dotfiles/dotfiles/"*.symlink; do
        if [ -f "$file" ]; then
            filename=$(basename "$file" .symlink)
            target="$HOME/.$filename"
            
            # Backup existing file if it's not a symlink
            if [ -f "$target" ] && [ ! -L "$target" ]; then
                echo "Backing up existing $target to $target.backup"
                mv "$target" "$target.backup"
            fi
            
            # Create symlink
            echo "Creating symlink: $target -> $file"
            ln -sf "$file" "$target"
        fi
    done
}

# Function to manage services
manage_services() {
    if command_exists brew; then
        echo "Setting up yabai and skhd services..."
        
        # Install yabai and skhd if not already installed
        if ! command_exists yabai; then
            echo "Installing yabai..."
            brew install koekeishiya/formulae/yabai
        fi
        
        if ! command_exists skhd; then
            echo "Installing skhd..."
            brew install koekeishiya/formulae/skhd
        fi
        
        # Stop services if they're running
        echo "Stopping services if running..."
        yabai --stop-service 2>/dev/null
        skhd --stop-service 2>/dev/null
        
        # Start services
        echo "Starting yabai and skhd services..."
        yabai --start-service
        skhd --start-service
        
        echo "Services started. Note: you might need to allow accessibility permissions"
        echo "System Preferences -> Security & Privacy -> Privacy -> Accessibility"
    else
        echo "Homebrew not found. Please install yabai and skhd manually."
    fi
}

package_to_install="
    tmux
    tree
    wget
    watch
    zsh
    curl
    git
    eza
    zoxide
    mole
    lazygit
    fzf
    bat
    ripgrep
    fd
    delta
    gh
    zsh-autosuggestions
    zsh-syntax-highlighting
"

# Function to install packages based on the package manager
install_packages() {
    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y zsh curl git
        # Install eza for debian/ubuntu
        sudo mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/TheLocehiliosan/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
        sudo apt-get update
        sudo apt-get install -y eza
        # Install zoxide
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    elif command_exists yum; then
        sudo yum update
        sudo yum install -y zsh curl git
        # For eza and zoxide on RHEL/CentOS, recommend manual installation
        echo "Please install eza and zoxide manually for your RHEL/CentOS system"
    elif command_exists brew; then
        brew install $package_to_install

        # Terminal choice: iTerm2 or Ghostty
        local term_choice
        term_choice=$(ask_choice "Preferred terminal? 1) iTerm2  2) Ghostty" "iTerm2" "Ghostty")
        if [ "$term_choice" = "2" ]; then
            echo "Installing Ghostty..."
            brew install --cask ghostty
            echo "1. Launch Ghostty and set MesloLGS NF as the default font"
            echo "2. Run 'p10k configure' to set up Powerlevel10k"
        else
            echo "Installing iTerm2..."
            brew install --cask iterm2
            echo "1. Launch iTerm2"
            echo "2. Set MesloLGS NF as the default font in iTerm2 preferences"
            echo "3. Import your iTerm2 preferences (if you have them in your dotfiles)"
        fi
    else
        echo "No supported package manager found. Please install zsh, curl, git, eza, and zoxide manually."
        exit 1
    fi
}

setup_powerlevel10k() {
    # First check if Oh My Zsh is installed
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "Oh My Zsh detected, setting up Powerlevel10k as Oh My Zsh theme..."
        
        # Install Powerlevel10k theme for Oh My Zsh if not already installed
        if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
            echo "Installing Powerlevel10k theme..."
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
        else
            echo "Powerlevel10k theme is already installed for Oh My Zsh"
        fi
        
        # Check if ZSH_THEME is already set to powerlevel10k
        if grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$HOME/.zshrc"; then
            echo "Powerlevel10k theme is already configured in .zshrc"
        else
            # Backup existing .zshrc if it exists
            if [ -f "$HOME/.zshrc" ]; then
                echo "Backing up existing .zshrc..."
                cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
            fi
            
            # Update .zshrc configuration
            echo "Updating .zshrc to use Powerlevel10k theme..."
            sed_in_place 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
        fi
    else
        echo "Oh My Zsh not detected, setting up standalone Powerlevel10k..."
        
        # Install standalone Powerlevel10k if not already installed
        if [ ! -d "$HOME/powerlevel10k" ]; then
            echo "Installing standalone Powerlevel10k..."
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k"
        else
            echo "Standalone Powerlevel10k is already installed"
        fi
        
        # Check if powerlevel10k is already sourced in .zshrc
        if grep -q 'source ~/powerlevel10k/powerlevel10k.zsh-theme' "$HOME/.zshrc"; then
            echo "Standalone Powerlevel10k is already configured in .zshrc"
        else
            # Backup existing .zshrc if it exists
            if [ -f "$HOME/.zshrc" ]; then
                echo "Backing up existing .zshrc..."
                cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
            fi
            
            # Add source line to .zshrc
            echo "Adding Powerlevel10k source line to .zshrc..."
            echo "source ~/powerlevel10k/powerlevel10k.zsh-theme" >> "$HOME/.zshrc"
        fi
    fi
}

# Ensure script is run from the correct directory (skip for "update" command)
if [ "${1:-}" = "update" ]; then
    update_software
    exit 0
fi

if [ ! -d "$HOME/.dotfiles" ]; then
    echo "Error: ~/.dotfiles directory not found!"
    echo "Please clone the repository to ~/.dotfiles first."
    exit 1
fi

echo "Installing required packages..."
install_packages

# Check if Oh My Zsh is already installed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "Oh My Zsh is already installed"
fi

# Backup existing .zshrc if it exists
if [ -f "$HOME/.zshrc" ]; then
    echo "Backing up existing .zshrc..."
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

echo "Installing powerlevel10k..."
setup_powerlevel10k

# Install zsh-autosuggestions
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
else
    echo "zsh-autosuggestions is already installed"
fi

# Install zsh-syntax-highlighting
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
else
    echo "zsh-syntax-highlighting is already installed"
fi

# Create symlinks for dotfiles
create_symlinks

# Start services after symlinks are created
manage_services

# Update plugins in .zshrc
sed_in_place 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"

# Add eza alias, zoxide, and custom functions
echo "Adding eza alias, zoxide, and gwt worktree helper..."
cat << 'EOF' >> "$HOME/.zshrc"

# ---- Eza (better ls) ----
alias ls="eza --icons=always"

# ---- Zoxide (better cd) ----
eval "$(zoxide init zsh)"

# ---- Git worktree helper (overrides git plugin gwt alias) ----
unalias gwt 2>/dev/null
gwt() {
  local name="$1"
  local branch="${2:-feature/$name}"
  [[ -z "$name" ]] && { echo "usage: gwt <name> [branch]"; return 1; }

  mkdir -p ../wt
  git worktree add "../wt/$name" -b "$branch" || return 1
  cd "../wt/$name" || return 1

  # --- uv env ---
  uv venv --quiet
  uv sync

  # --- dbt isolation (per worktree) ---
  export DBT_TARGET_PATH="target"
  export DBT_LOG_PATH="logs"
  mkdir -p "$DBT_LOG_PATH"

  if command -v dbt >/dev/null 2>&1; then
    dbt deps >/dev/null 2>&1 || true
  fi

  lazygit
}

# ---- fzf (fuzzy finder: Ctrl+R history, ** tab completion) ----
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
EOF

# Configure fzf keybindings (zsh) and git delta, when using Homebrew
if command_exists brew; then
    if [ -x "$(brew --prefix)/opt/fzf/install" ]; then
        echo "Configuring fzf keybindings..."
        "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish 2>/dev/null || true
    fi
    if command_exists delta && command_exists git; then
        echo "Configuring delta as git pager..."
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
    fi
fi

# macOS-only: fonts, alt-tab
if command_exists brew; then
    echo "================================================="
    echo "Install fonts and Alt-tab"
    echo "================================================="
    brew tap epk/epk
    brew install --cask font-sf-mono-nerd-font

    echo "================================================="
    echo "Installing Alt-tab and Raycast"
    echo "================================================="
    brew install --cask alt-tab
    brew install --cask raycast
fi

# Install recommended font (MesloLGS NF) - works on macOS and Linux
echo "Installing recommended Meslo Nerd Font..."
mkdir -p "$HOME/.local/share/fonts"
FONT_URLS=(
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
)

for URL in "${FONT_URLS[@]}"; do
    curl -fL "$URL" -o "$HOME/.local/share/fonts/$(basename "$URL")"
done

# Refresh font cache (Linux, and macOS if fontconfig is installed)
if command_exists fc-cache; then
    fc-cache -f -v
fi

# Borders config (used by yabai/borders)
mkdir -p "$HOME/.config/borders"
ln -sf "$HOME/.dotfiles/borders/bordersrc.symlink" "$HOME/.config/borders/bordersrc"

# Cursor install context: symlink rules so AI can see installed tools
if [ -d "$HOME/.dotfiles/.cursor/rules" ]; then
    echo "Linking Cursor rules..."
    mkdir -p "$HOME/.cursor/rules"
    for f in "$HOME/.dotfiles/.cursor/rules/"*.mdc; do
        [ -f "$f" ] && ln -sf "$f" "$HOME/.cursor/rules/$(basename "$f")"
    done
fi

# Claude Code install context: ensure ~/.claude/CLAUDE.md includes installed tools (for users who use Claude Code, not Cursor)
if [ -f "$HOME/.dotfiles/claude/dotfiles-tools.md" ]; then
    echo "Setting up Claude Code install context..."
    mkdir -p "$HOME/.claude"
    ln -sf "$HOME/.dotfiles/claude/dotfiles-tools.md" "$HOME/.claude/dotfiles-tools.md"
    if [ ! -f "$HOME/.claude/CLAUDE.md" ]; then
        cp "$HOME/.dotfiles/claude/dotfiles-tools.md" "$HOME/.claude/CLAUDE.md"
        echo "Created ~/.claude/CLAUDE.md with installed tools list."
    elif ! grep -q "Installed tools (dotfiles stack)" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
        printf '\n\n---\n\n' >> "$HOME/.claude/CLAUDE.md"
        cat "$HOME/.dotfiles/claude/dotfiles-tools.md" >> "$HOME/.claude/CLAUDE.md"
        echo "Appended installed tools section to ~/.claude/CLAUDE.md"
    fi
fi

# Optional: sketchybar (macOS only)
if command_exists brew && [ -f "$HOME/.dotfiles/install_sketchybar.sh" ]; then
    if [ "$(ask_yes_no "Install sketchybar (status bar)?")" = "y" ]; then
        echo "Installing sketchybar..."
        bash "$HOME/.dotfiles/install_sketchybar.sh"
    fi
fi

# Optional: AWS CLI (includes S3)
if [ "$(ask_yes_no "Install AWS CLI (includes S3)?")" = "y" ]; then
    if command_exists brew; then
        echo "Installing AWS CLI..."
        brew install awscli
    elif command_exists apt-get; then
        echo "Installing AWS CLI..."
        sudo apt-get update && sudo apt-get install -y awscli
    else
        echo "Please install AWS CLI manually: https://aws.amazon.com/cli/"
    fi
fi

# Optional: update installed software now
if [ "$(ask_yes_no "Update all installed software now (brew, Oh My Zsh, plugins)?")" = "y" ]; then
    update_software
fi

echo "================================================="
echo "Installation complete!"
echo "================================================="
echo ""
echo "Next steps:"
echo "  1. Use your chosen terminal (iTerm2 or Ghostty) as default"
echo "  2. Set MesloLGS NF as the default font"
echo "  3. Run 'p10k configure' to set up Powerlevel10k"
echo ""
echo "Basic commands:"
echo "  ls          - eza (directory listing with icons)"
echo "  cd <dir>    - zoxide (smarter cd with history)"
echo "  bat <file>  - bat (syntax-highlighted cat)"
echo "  rg <pat>    - ripgrep (fast search in files)"
echo "  fd <name>   - fd (simple fast find)"
echo "  watch <cmd> - run a command repeatedly (e.g. watch -n 2 'git status')"
echo "  Ctrl+R     - fzf (fuzzy search shell history)"
echo "  lazygit     - TUI for git (commit, branches, diff; uses delta for diffs)"
echo "  gh          - GitHub CLI (pr, issue, repo from terminal)"
echo "  aws s3 ...  - AWS CLI / S3 (if installed)"
echo "  gwt <name> [branch] - create a git worktree in ../wt/<name>, set up uv + dbt, open lazygit"
echo "                         e.g. gwt my-feature    → branch feature/my-feature"
echo "                              gwt hotfix main   → branch main"
echo ""
echo "Updates:"
echo "  ./install.sh update   - update Homebrew, Oh My Zsh, plugins, Powerlevel10k"
echo ""
