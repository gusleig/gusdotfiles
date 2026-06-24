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

# Sentinel markers for the dotfiles-managed block in ~/.zshrc.
# These let us idempotently rewrite the block on every install/update.
DOTFILES_BLOCK_BEGIN="# === DOTFILES MANAGED BLOCK :: BEGIN (do not edit; see ~/.dotfiles) ==="
DOTFILES_BLOCK_END="# === DOTFILES MANAGED BLOCK :: END ==="

# One-time migration: strip the legacy (pre-managed-block) inline heredoc
# that older installs appended to ~/.zshrc. Range is from
# '# ---- Eza (better ls) ----' through the fzf source line.
remove_legacy_zsh_block() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || return 0
    if ! grep -qE '^# ---- Eza \(better ls\) ----$' "$zshrc"; then
        return 0
    fi
    echo "Removing legacy inline shell block from $zshrc (one-time migration)..."
    awk '
      /^# ---- Eza \(better ls\) ----$/ { in_block=1 }
      in_block {
        if ($0 == "[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh") { in_block=0; next }
        next
      }
      { print }
    ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
}

# Idempotently (re)write the managed block in ~/.zshrc. The block is just a
# tiny loader that sources every *.zsh in dotfiles/zsh/zshrc.d/, so future
# updates to gwtree, aliases, etc. arrive via a simple 'git pull'.
write_managed_block() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || touch "$zshrc"

    # Strip any existing managed block first (handles re-runs cleanly).
    if grep -qF "$DOTFILES_BLOCK_BEGIN" "$zshrc"; then
        awk -v B="$DOTFILES_BLOCK_BEGIN" -v E="$DOTFILES_BLOCK_END" '
          $0 == B { in_block=1; next }
          in_block { if ($0 == E) in_block=0; next }
          { print }
        ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
    fi

    # Trim trailing blank lines so successive rewrites don't accumulate them.
    awk '
      { lines[NR]=$0 }
      END {
        last=NR
        while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
        for (i=1; i<=last; i++) print lines[i]
      }
    ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"

    cat >> "$zshrc" <<BLOCK

$DOTFILES_BLOCK_BEGIN
# Source every *.zsh in ~/.dotfiles/dotfiles/zsh/zshrc.d/ in name order.
# Add new shell functions/aliases by dropping a *.zsh file there.
if [ -d "\$HOME/.dotfiles/dotfiles/zsh/zshrc.d" ]; then
  for _df_f in "\$HOME"/.dotfiles/dotfiles/zsh/zshrc.d/*.zsh; do
    [ -r "\$_df_f" ] && source "\$_df_f"
  done
  unset _df_f
fi
$DOTFILES_BLOCK_END
BLOCK
    echo "Refreshed dotfiles managed block in $zshrc"
}

# Install Homebrew packages via Brewfile (idempotent, picks up new tools).
brew_bundle_install() {
    if ! command_exists brew; then
        return 0
    fi
    local brewfile="$HOME/.dotfiles/Brewfile"
    if [ -f "$brewfile" ]; then
        echo "Installing/updating packages from Brewfile..."
        brew bundle install --file "$brewfile" || echo "warning: 'brew bundle install' reported errors"
    else
        echo "warning: $brewfile not found; skipping brew bundle."
    fi
}

# Update installed software:
#   1) Pull ~/.dotfiles (with auto-stash if dirty).
#   2) Re-run Brewfile so new tools land automatically.
#   3) Re-emit the managed block in ~/.zshrc (and migrate legacy block).
#   4) Update brew, Oh My Zsh, p10k, plugins.
#   5) Print the new commits since last update so the user sees what changed.
update_software() {
    echo "================================================="
    echo "Updating ~/.dotfiles repo..."
    echo "================================================="
    local old_head="" new_head=""
    local dirty=0
    if [ -d "$HOME/.dotfiles/.git" ]; then
        old_head=$(git -C "$HOME/.dotfiles" rev-parse HEAD 2>/dev/null || echo "")
        if ! git -C "$HOME/.dotfiles" diff --quiet 2>/dev/null \
            || ! git -C "$HOME/.dotfiles" diff --cached --quiet 2>/dev/null; then
            dirty=1
            echo "Stashing local changes in ~/.dotfiles..."
            git -C "$HOME/.dotfiles" stash push -u \
                -m "dotfiles auto-stash $(date +%Y%m%d%H%M%S)" || true
        fi
        git -C "$HOME/.dotfiles" pull --ff-only \
            || echo "git pull failed; resolve manually then re-run."
        new_head=$(git -C "$HOME/.dotfiles" rev-parse HEAD 2>/dev/null || echo "")
    else
        echo "~/.dotfiles is not a git repo; skipping pull."
    fi

    echo ""
    echo "================================================="
    echo "Re-syncing ~/.zshrc managed block..."
    echo "================================================="
    remove_legacy_zsh_block
    write_managed_block

    echo ""
    echo "================================================="
    echo "Installing/updating Homebrew packages via Brewfile..."
    echo "================================================="
    brew_bundle_install
    if command_exists brew; then
        echo "Updating Homebrew formulae and casks..."
        brew update && brew upgrade
        brew upgrade --cask
    fi

    echo ""
    echo "================================================="
    echo "Updating Oh My Zsh + plugins..."
    echo "================================================="
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

    if [ -n "$old_head" ] && [ -n "$new_head" ] && [ "$old_head" != "$new_head" ]; then
        echo ""
        echo "================================================="
        echo "Changes in ~/.dotfiles since last update:"
        echo "================================================="
        git -C "$HOME/.dotfiles" log --oneline "$old_head..$new_head"
    fi

    if [ "$dirty" = "1" ]; then
        echo ""
        echo "Note: your local ~/.dotfiles changes are in 'git stash'."
        echo "      Re-apply with: git -C ~/.dotfiles stash pop"
    fi

    echo ""
    echo "Update complete. Run 'exec zsh' or open a new terminal to reload."
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

# Linux fallback list (apt/yum only). On macOS we use the Brewfile.
package_to_install="
    bash
    tmux
    tree
    wget
    watch
    zsh
    curl
    git
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
        # All formulae + casks live in ~/.dotfiles/Brewfile so updates flow
        # automatically through 'dotfiles update' / 'brew bundle install'.
        brew_bundle_install

        # Terminal choice is interactive, so handle it separately from Brewfile.
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

# Install/refresh the dotfiles-managed block in ~/.zshrc.
# The block is just a sourcing loop over dotfiles/zsh/zshrc.d/*.zsh, so future
# changes to gwtree, aliases, the `dotfiles` CLI, etc. arrive via 'git pull'
# (i.e. 'dotfiles update') with no further edits to ~/.zshrc.
echo "Installing dotfiles managed block in ~/.zshrc..."
remove_legacy_zsh_block
write_managed_block

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

# macOS apps (fonts, alt-tab, raycast, stats) are now declared in the
# Brewfile and installed by brew_bundle_install above. Nothing to do here.

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
echo "  lazydocker  - TUI for docker (containers, images, logs, stats)"
echo "  gh          - GitHub CLI (pr, issue, repo from terminal)"
echo "  aws s3 ...  - AWS CLI / S3 (if installed)"
echo "  gwtree <name> [-f] [-y]            - worktree ../wt/<name>, branch <name> (use -f for feature/<name>)"
echo "  gwtree feat <ticket> <description> - branch feature/<ticket>/<description>, folder ../wt/<description>"
echo "  gwtree from <branch> [<name>]      - worktree ../wt/<name> (default: basename branch), existing <branch>"
echo "  gwtree --help                      - full usage"
echo ""
echo "Updates:"
echo "  dotfiles update       - pull ~/.dotfiles, run Brewfile, refresh ~/.zshrc"
echo "                          managed block, update brew/Oh My Zsh/plugins/p10k"
echo "  dotfiles status       - show repo status + commits ahead/behind upstream"
echo "  dotfiles log          - show last 20 commits in ~/.dotfiles"
echo "  ./install.sh update   - same as 'dotfiles update' (run from anywhere)"
echo ""
