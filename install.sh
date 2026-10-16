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

# One-time migration: quarantine (never blindly delete) the legacy
# inline heredoc that older installs appended to ~/.zshrc. Range is from
# '# ---- Eza (better ls) ----' through the fzf source line. We:
#   1. Back up ~/.zshrc verbatim (before-legacy-migration.<ts>).
#   2. Extract the legacy range to a quarantine file the user can review.
#   3. Strip the range from ~/.zshrc so the new sentinel-managed block can
#      take over loading.
#
# If validate_zshrc() (called by the caller) detects the resulting shell
# can't start, we'll auto-rollback to the backup.
remove_legacy_zsh_block() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || return 0
    if ! grep -qE '^# ---- Eza \(better ls\) ----$' "$zshrc"; then
        return 0
    fi
    # Without the end marker the range would run to end of file and take
    # unrelated user config with it. Skip and let the user handle it.
    if ! grep -qxF '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh' "$zshrc"; then
        echo "note: found the old '# ---- Eza (better ls) ----' section in $zshrc,"
        echo "      but not its end line. Skipping the automatic migration."
        echo "      The managed block already sets up eza and zoxide, so you can"
        echo "      delete the old eza/zoxide lines from $zshrc by hand."
        return 0
    fi

    local ts
    ts="$(date +%Y%m%d%H%M%S)"
    local backup="${zshrc}.before-legacy-migration.${ts}"
    local quarantine="${HOME}/.dotfiles-legacy-block.${ts}.zsh"

    cp "$zshrc" "$backup"
    echo "Backed up $zshrc -> $backup"

    # Extract the legacy range to a quarantine file so user-added content
    # (e.g. work-specific AWS helpers) is never lost.
    awk '
      /^# ---- Eza \(better ls\) ----$/ { in_block=1 }
      in_block {
        print
        if ($0 == "[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh") in_block=0
      }
    ' "$zshrc" > "$quarantine"
    local stripped_lines
    stripped_lines=$(wc -l < "$quarantine" | tr -d ' ')

    echo "Quarantined legacy inline block ($stripped_lines lines) -> $quarantine"
    echo "  Review it. Move any custom additions (aliases, functions, exports)"
    echo "  into ~/.zshrc.local (always auto-sourced, never touched by updates)."
    echo "  Then 'rm $quarantine' when you're done."

    # Now strip the range from .zshrc.
    awk '
      /^# ---- Eza \(better ls\) ----$/ { in_block=1 }
      in_block {
        if ($0 == "[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh") { in_block=0; next }
        next
      }
      { print }
    ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
}

# Run a clean non-interactive zsh against the current ~/.zshrc and verify
# it can start. If it can't, the caller should rollback from the backup.
# Returns 0 on success, non-zero on failure.
validate_zshrc() {
    # Use a brand-new zsh process so we don't inherit fixups from this script's
    # environment. -i forces interactive-mode rc loading; -c ':' exits immediately.
    # We swallow stdout/stderr but pass through exit code.
    zsh -i -c ':' >/dev/null 2>&1
}

# After any destructive mutation of ~/.zshrc, call this to assert the
# new file still starts a shell cleanly. If not, restore from $backup.
verify_or_rollback_zshrc() {
    local backup="$1"
    if validate_zshrc; then
        return 0
    fi
    echo "ERROR: zsh failed to start with the new ~/.zshrc." >&2
    if [ -n "$backup" ] && [ -f "$backup" ]; then
        echo "       Rolling back ~/.zshrc from $backup" >&2
        cp "$backup" "$HOME/.zshrc"
        echo "       Rollback complete. Investigate the failure before re-running." >&2
    else
        echo "       No backup available to roll back from." >&2
    fi
    return 1
}

# Make sure ~/.zshrc.local exists. If absent, create an empty template
# explaining what goes there. This is the canonical home for user-local
# shell config — never touched by 'dotfiles update'.
ensure_local_zshrc() {
    local local_rc="$HOME/.zshrc.local"
    [ -f "$local_rc" ] && return 0
    cat > "$local_rc" <<'LOCAL'
#!/usr/bin/env zsh
# ~/.zshrc.local — user-local shell config.
#
# This file is auto-sourced by the dotfiles managed block in ~/.zshrc
# (via dotfiles/zsh/zshrc.d/99-local.zsh). Put any machine- or work-
# specific shell config here so it survives every 'dotfiles update'.
# Nothing in ~/.dotfiles will ever overwrite or remove this file.
#
# Examples:
#   export AWS_PROFILE=hinge-prod
#   export ECR_URI="123456789012.dkr.ecr.us-east-1.amazonaws.com"
#   alias k="kubectl"
#   source /opt/work/init.sh
LOCAL
    echo "Created empty $local_rc — put any work-specific shell config there."
    echo "  It is auto-sourced by every new shell and is never touched by 'dotfiles update'."
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
#   1) Pull ~/.dotfiles (git stashes and restores local changes itself).
#      If the pull brought new commits, restart with the new install.sh so
#      new update steps run now, not on the next update.
#   2) Re-emit the managed block in ~/.zshrc (and migrate legacy block).
#   3) brew update, then the Brewfile, then brew upgrade.
#   4) Update tmux, Oh My Zsh, p10k.
#   5) Print the new commits since last update so the user sees what changed.
#
# Usage: update_software [--after-pull <old_head>]
update_software() {
    local old_head="" new_head=""
    if [ "${1:-}" = "--after-pull" ]; then
        old_head="${2:-}"
        new_head=$(git -C "$HOME/.dotfiles" rev-parse HEAD 2>/dev/null || echo "")
        echo "Running the updated install.sh..."
    elif [ -d "$HOME/.dotfiles/.git" ]; then
        echo "================================================="
        echo "Updating ~/.dotfiles repo..."
        echo "================================================="
        old_head=$(git -C "$HOME/.dotfiles" rev-parse HEAD 2>/dev/null || echo "")
        # --autostash puts local edits back right after the pull. The
        # *.symlink configs are live files, so a stash that stays in place
        # would silently revert them.
        if ! git -C "$HOME/.dotfiles" pull --ff-only --autostash; then
            echo "git pull failed; resolve manually then re-run."
            echo "If git reports a stash conflict, your edits are in 'git -C ~/.dotfiles stash list'."
        fi
        new_head=$(git -C "$HOME/.dotfiles" rev-parse HEAD 2>/dev/null || echo "")
        if [ -n "$old_head" ] && [ -n "$new_head" ] && [ "$old_head" != "$new_head" ]; then
            exec bash "$HOME/.dotfiles/install.sh" update --after-pull "$old_head"
        fi
    else
        echo "~/.dotfiles is not a git repo; skipping pull."
    fi

    echo ""
    echo "================================================="
    echo "Re-syncing ~/.zshrc managed block..."
    echo "================================================="
    # Snapshot the current ~/.zshrc so we can auto-rollback if any of the
    # mutations below leave the shell unable to start.
    local _pre_mutation_backup="$HOME/.zshrc.before-update.$(date +%Y%m%d%H%M%S)"
    [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$_pre_mutation_backup"

    remove_legacy_zsh_block
    write_managed_block
    ensure_local_zshrc

    if ! verify_or_rollback_zshrc "$_pre_mutation_backup"; then
        echo "       Update aborted to keep your shell working." >&2
        return 1
    fi

    echo ""
    echo "================================================="
    echo "Installing/updating Homebrew packages via Brewfile..."
    echo "================================================="
    if command_exists brew; then
        echo "Refreshing Homebrew package lists..."
        brew update || echo "warning: 'brew update' failed; continuing with cached lists."
    fi
    brew_bundle_install
    if command_exists brew; then
        echo "Upgrading Homebrew formulae and casks..."
        brew upgrade
    fi

    echo ""
    echo "================================================="
    echo "Updating tmux config + plugins..."
    echo "================================================="
    setup_tmux
    link_claude_context

    echo ""
    echo "================================================="
    echo "Updating Oh My Zsh + plugins..."
    echo "================================================="
    # zsh-autosuggestions / zsh-syntax-highlighting now come from brew.
    # The git pulls below only refresh clones left by older installs.
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

    echo ""
    echo "Update complete. Run 'exec zsh' or open a new terminal to reload."
}

# Link ~/.tmux.conf, install/update TPM + plugins, reload running tmux.
# Never fatal: a tmux problem shouldn't abort the rest of install/update.
setup_tmux() {
    local script="$HOME/.dotfiles/scripts/tmux-setup.sh"
    if ! command_exists tmux; then
        echo "tmux not installed; skipping tmux setup."
        return 0
    fi
    if [ -x "$script" ]; then
        "$script" update || echo "warning: tmux setup reported problems; run 'dotfiles tmux check'."
    fi
}

# Claude Code loads every file in ~/.claude/rules/ in every session, so a
# symlink there keeps the tools list current after each 'git pull'.
# ~/.claude/CLAUDE.md stays the user's own file and is never edited.
link_claude_context() {
    local src="$HOME/.dotfiles/claude/dotfiles-tools.md"
    local dest="$HOME/.claude/rules/dotfiles-tools.md"
    [ -f "$src" ] || return 0
    mkdir -p "$HOME/.claude/rules"
    ln -sfn "$src" "$dest"
    echo "Linked Claude Code context: $dest"
    if grep -qF "Installed tools (dotfiles stack)" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
        echo "note: ~/.claude/CLAUDE.md still has an old pasted copy of the tools list."
        echo "      It is now loaded from ~/.claude/rules/. You can delete the copy from CLAUDE.md."
    fi
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
                local backup="$target.backup.$(date +%Y%m%d%H%M%S)"
                echo "Backing up existing $target to $backup"
                mv "$target" "$backup"
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

# Function to install packages based on the package manager
install_packages() {
    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y zsh curl git
        # Install eza for debian/ubuntu
        sudo mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
        sudo apt-get update
        sudo apt-get install -y eza
        # Install zoxide
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    elif command_exists yum; then
        sudo yum update -y
        sudo yum install -y zsh curl git
        # For eza and zoxide on RHEL/CentOS, recommend manual installation
        echo "Please install eza and zoxide manually for your RHEL/CentOS system"
    elif command_exists brew; then
        # All formulae + casks live in ~/.dotfiles/Brewfile so updates flow
        # automatically through 'dotfiles update' / 'brew bundle install'.
        brew_bundle_install

        # Terminal choice is interactive, so handle it separately from Brewfile.
        local term_choice
        term_choice=$(ask_choice "Preferred terminal? 1) iTerm2  2) Ghostty")
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
    shift
    update_software "$@"
    exit $?
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
    _had_zshrc=0
    [ -f "$HOME/.zshrc" ] && _had_zshrc=1
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    if [ "$_had_zshrc" = 1 ]; then
        echo ""
        echo "NOTE: Oh My Zsh replaced your ~/.zshrc with its template."
        echo "      Your old file is now one of these:"
        ls -1d "$HOME"/.zshrc.pre-oh-my-zsh* 2>/dev/null | sed 's/^/        /'
        echo "      Copy any custom lines from it into ~/.zshrc.local."
        echo ""
    fi
    unset _had_zshrc
else
    echo "Oh My Zsh is already installed"
fi

# Back up ~/.zshrc before any install step edits it. This is also the
# rollback point if the final shell check fails. 'dotfiles rollback'
# finds it by its .before-install.<ts> name.
_pre_install_backup="$HOME/.zshrc.before-install.$(date +%Y%m%d%H%M%S)"
if [ -f "$HOME/.zshrc" ]; then
    echo "Backing up ~/.zshrc -> $_pre_install_backup"
    cp "$HOME/.zshrc" "$_pre_install_backup"
fi

echo "Installing powerlevel10k..."
setup_powerlevel10k

# zsh-autosuggestions and zsh-syntax-highlighting come from the Brewfile
# and load from dotfiles/zsh/zshrc.d/90-zsh-plugins.zsh.

# Create symlinks for dotfiles
create_symlinks

# tmux: config link (done above), TPM, plugins
setup_tmux

# Optional: yabai + skhd (macOS window manager + hotkeys)
if command_exists brew && [[ "$OSTYPE" == "darwin"* ]]; then
    if [ "$(ask_yes_no "Install and (re)start yabai + skhd?")" = "y" ]; then
        manage_services
    fi
fi

# Install/refresh the dotfiles-managed block in ~/.zshrc.
# The block is just a sourcing loop over dotfiles/zsh/zshrc.d/*.zsh, so future
# changes to gwtree, aliases, the `dotfiles` CLI, etc. arrive via 'git pull'
# (i.e. 'dotfiles update') with no further edits to ~/.zshrc.
echo "Installing dotfiles managed block in ~/.zshrc..."
remove_legacy_zsh_block
write_managed_block
ensure_local_zshrc
verify_or_rollback_zshrc "$_pre_install_backup" || {
    echo "Aborting install: new ~/.zshrc broke shell startup. Rolled back." >&2
    exit 1
}
unset _pre_install_backup

# fzf keybindings come from dotfiles/zsh/zshrc.d/20-fzf.zsh (no installer,
# no extra ~/.zshrc edits). Configure git delta when using Homebrew.
if command_exists brew; then
    if command_exists delta && command_exists git; then
        # Only fill in unset values, so a pager you chose yourself stays.
        if ! git config --global --get core.pager >/dev/null; then
            echo "Configuring delta as git pager..."
            git config --global core.pager delta
        fi
        if ! git config --global --get interactive.diffFilter >/dev/null; then
            git config --global interactive.diffFilter "delta --color-only"
        fi
    fi
fi

# macOS apps (fonts, alt-tab, raycast, stats) are now declared in the
# Brewfile and installed by brew_bundle_install above. Nothing to do here.

# Install recommended font (MesloLGS NF). macOS only reads ~/Library/Fonts.
# Files that already exist are skipped, so re-runs download nothing.
if [[ "$OSTYPE" == "darwin"* ]]; then
    FONT_DIR="$HOME/Library/Fonts"
else
    FONT_DIR="$HOME/.local/share/fonts"
fi
mkdir -p "$FONT_DIR"
FONT_URLS=(
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
)

fonts_added=0
for URL in "${FONT_URLS[@]}"; do
    font_file="$FONT_DIR/$(basename "$URL" | sed 's/%20/ /g')"
    [ -f "$font_file" ] && continue
    echo "Downloading $(basename "$font_file")..."
    curl -fsSL "$URL" -o "$font_file" && fonts_added=1
done
if [ "$fonts_added" = 0 ]; then
    echo "MesloLGS NF already installed in $FONT_DIR"
fi

# Refresh font cache (Linux, and macOS if fontconfig is installed)
if [ "$fonts_added" = 1 ] && command_exists fc-cache; then
    fc-cache -f
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

# Claude Code install context: tools list + pointer to the tmux workflow guide
link_claude_context

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
echo "Updates & safety:"
echo "  dotfiles update       - pull ~/.dotfiles, run Brewfile, refresh ~/.zshrc"
echo "                          managed block, update brew/Oh My Zsh/plugins/p10k"
echo "  dotfiles status       - show repo status + commits ahead/behind upstream"
echo "  dotfiles log          - show last 20 commits in ~/.dotfiles"
echo "  dotfiles doctor       - health-check (PASS/WARN/FAIL): managed block,"
echo "                          snippet syntax, brewfile sync, AWS creds, etc."
echo "  dotfiles rollback     - restore ~/.zshrc from most recent backup"
echo "                          (every install/update takes one automatically)"
echo "  ./install.sh update   - same as 'dotfiles update' (run from anywhere)"
echo "  dotfiles tmux check   - verify tmux config link, syntax, TPM, plugins"
echo "  dotfiles tmux update  - re-link ~/.tmux.conf, install/update plugins"
echo ""
echo "tmux (prefix is Ctrl+A):"
echo "  tmux new -s <task>    - one session per task (Claude/Codex inside)"
echo "  Ctrl+A, Shift+T       - sesh picker to switch tasks"
echo "  Ctrl+A, d             - detach; 'tmux attach' to come back"
echo "  Step-by-step guide:     ~/.dotfiles/docs/tmux-claude-workflow.md"
echo ""
echo "Work-specific shell config:"
echo "  ~/.zshrc.local        - your private, never-touched shell config."
echo "                          Put work aliases, exports, AWS helpers, etc."
echo "                          here so they survive every 'dotfiles update'."
echo ""
