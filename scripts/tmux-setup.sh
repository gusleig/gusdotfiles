#!/usr/bin/env bash
# tmux-setup: install, verify, and update the dotfiles tmux workspace
# (tmux + TPM plugins + sesh picker).
#
# The config lives in ~/.dotfiles/dotfiles/tmux.conf.symlink and is
# symlinked to ~/.tmux.conf, so 'git pull' is enough to change it.
#
# Usage:
#   dotfiles tmux check    Verify only. Prints PASS/WARN/FAIL, exits 1 on FAIL.
#   dotfiles tmux update   Link the config (backing up any existing file),
#                          install/update TPM and plugins, reload running tmux.
#   (or call ~/.dotfiles/scripts/tmux-setup.sh directly)

set -uo pipefail

REPO="$HOME/.dotfiles"
SRC="$REPO/dotfiles/tmux.conf.symlink"
TARGET="$HOME/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"
PLUGINS_DIR="$HOME/.tmux/plugins"
TPM_REPO="https://github.com/tmux-plugins/tpm"
MIN_TMUX="3.2"   # display-popup and terminal-features need 3.2+

# --embedded: used by dotfiles-doctor. No header/summary, and a final
# 'COUNTS <pass> <warn> <fail>' line so the doctor can merge totals.
EMBEDDED=0
COLOR=auto

pass=0
warn=0
fail=0

setup_colors() {
    if [ "$COLOR" = always ] || { [ "$COLOR" = auto ] && [ -t 1 ]; }; then
        C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
        C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
    else
        C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_RESET=""
    fi
}

say_pass() { printf "  ${C_GREEN}PASS${C_RESET}  %s\n" "$1"; pass=$((pass+1)); }
say_warn() { printf "  ${C_YELLOW}WARN${C_RESET}  %s\n" "$1"; [ -n "${2:-}" ] && printf "        ${C_DIM}%s${C_RESET}\n" "$2"; warn=$((warn+1)); }
say_fail() { printf "  ${C_RED}FAIL${C_RESET}  %s\n" "$1"; [ -n "${2:-}" ] && printf "        ${C_DIM}%s${C_RESET}\n" "$2"; fail=$((fail+1)); }
info()     { printf "%s\n" "$1"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Prints e.g. "3.8" from "tmux 3.8", "tmux 3.3a", "tmux next-3.6".
tmux_version() {
    tmux -V 2>/dev/null | sed -E 's/^tmux (next-)?([0-9]+\.[0-9]+).*/\2/'
}

# version_ge 3.8 3.2 -> true
version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n | head -1)" = "$2" ]
}

# Plugin repo names declared in a config, e.g. "tmux-plugins/tpm".
declared_plugins() {
    sed -nE "s/^[[:space:]]*set(-option)? +-g +@plugin +['\"]([^'\"]+)['\"].*/\2/p" "$1"
}

# Load the config into a throwaway tmux server to catch unknown commands
# and invalid options. 'run' lines are stripped so TPM, resurrect, and
# continuum never execute against the scratch server.
# Prints tmux's error output on failure.
validate_conf() {
    local conf="$1" tmp sock out rc
    tmp="$(mktemp "${TMPDIR:-/tmp}/tmux-check.XXXXXX")" || return 1
    grep -vE '^[[:space:]]*run(-shell)?[[:space:]]' "$conf" > "$tmp"
    sock="dotfiles-check-$$"
    out=$(tmux -L "$sock" -f /dev/null new-session -d \; source-file "$tmp" 2>&1)
    rc=$?
    tmux -L "$sock" kill-server >/dev/null 2>&1
    rm -f "$tmp"
    [ -n "$out" ] && printf '%s\n' "$out"
    return "$rc"
}

# ---------------------------------------------------------------- check
run_check() {
    [ "$EMBEDDED" = 1 ] || info "tmux workspace"

    # tmux binary + version
    if command_exists tmux; then
        local v
        v="$(tmux_version)"
        if [ -n "$v" ] && version_ge "$v" "$MIN_TMUX"; then
            say_pass "tmux $v installed"
        else
            say_fail "tmux ${v:-unknown} is older than $MIN_TMUX" "brew upgrade tmux"
        fi
    else
        say_fail "tmux not installed" "brew bundle install --file $REPO/Brewfile"
    fi

    # Companion tools
    if command_exists sesh; then
        say_pass "sesh installed (Ctrl+A, Shift+T picker)"
    else
        say_warn "sesh not installed: the Ctrl+A, Shift+T picker won't work" \
                 "brew install sesh"
    fi
    for t in fzf zoxide; do
        if command_exists "$t"; then
            say_pass "$t installed"
        else
            say_warn "$t not installed" "brew install $t"
        fi
    done

    # Config link
    if [ ! -f "$SRC" ]; then
        say_fail "Repo config missing: $SRC" "git -C $REPO status"
    elif [ -L "$TARGET" ]; then
        local dest
        dest="$(readlink "$TARGET")"
        if [ "$dest" = "$SRC" ]; then
            say_pass "~/.tmux.conf -> dotfiles/tmux.conf.symlink"
        else
            say_fail "~/.tmux.conf points somewhere else: $dest" "dotfiles tmux update"
        fi
    elif [ -f "$TARGET" ]; then
        if cmp -s "$TARGET" "$SRC"; then
            say_warn "~/.tmux.conf is a copy, not a symlink (future updates won't apply)" \
                     "dotfiles tmux update"
        else
            say_fail "~/.tmux.conf is a local file that differs from the dotfiles version" \
                     "dotfiles tmux update  (backs it up first; diff ~/.tmux.conf $SRC)"
        fi
    else
        say_fail "~/.tmux.conf missing" "dotfiles tmux update"
    fi

    # Config validity
    if command_exists tmux && [ -f "$SRC" ]; then
        local errs
        if errs="$(validate_conf "$SRC")"; then
            say_pass "Config loads without errors"
        else
            say_fail "Config has errors" "$(printf '%s' "$errs" | head -3 | tr '\n' ' ')"
        fi
    fi

    # TPM + plugins
    if [ -x "$TPM_DIR/tpm" ]; then
        say_pass "TPM installed at ~/.tmux/plugins/tpm"
    else
        say_fail "TPM not installed" "dotfiles tmux update"
    fi
    if [ -f "$SRC" ]; then
        local missing="" p name
        for p in $(declared_plugins "$SRC"); do
            name="${p##*/}"
            [ "$name" = tpm ] && continue
            [ -d "$PLUGINS_DIR/$name" ] || missing="$missing $name"
        done
        if [ -z "$missing" ]; then
            say_pass "All declared plugins installed"
        else
            say_fail "Missing plugins:$missing" "dotfiles tmux update  (or Ctrl+A, Shift+I inside tmux)"
        fi
    fi

    # Running server picked up the current config?
    if command_exists tmux && tmux list-sessions >/dev/null 2>&1; then
        if [ "$(tmux show-options -gv prefix 2>/dev/null)" = "C-a" ]; then
            say_pass "Running tmux server uses the Ctrl+A prefix"
        else
            say_warn "Running tmux server hasn't loaded this config" \
                     "tmux source-file ~/.tmux.conf  (or Ctrl+A, r)"
        fi
    fi

    if [ "$EMBEDDED" = 1 ]; then
        printf 'COUNTS %d %d %d\n' "$pass" "$warn" "$fail"
    else
        printf "\n  ${C_GREEN}%d pass${C_RESET}  ${C_YELLOW}%d warn${C_RESET}  ${C_RED}%d fail${C_RESET}\n" \
            "$pass" "$warn" "$fail"
    fi
    [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------- update
link_config() {
    if [ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SRC" ]; then
        info "~/.tmux.conf already linked."
        return 0
    fi
    if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
        local backup="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
        # cp -P keeps a foreign symlink as a symlink instead of copying its target.
        cp -P "$TARGET" "$backup" || { echo "ERROR: could not back up $TARGET" >&2; return 1; }
        info "Backed up existing ~/.tmux.conf -> $backup"
    fi
    ln -sfn "$SRC" "$TARGET" || return 1
    info "Linked ~/.tmux.conf -> $SRC"
}

install_tpm() {
    if [ -d "$TPM_DIR/.git" ]; then
        info "Updating TPM..."
        git -C "$TPM_DIR" pull --ff-only --quiet || echo "warning: TPM pull failed; continuing."
    else
        info "Cloning TPM..."
        mkdir -p "$PLUGINS_DIR"
        git clone --quiet "$TPM_REPO" "$TPM_DIR" || { echo "ERROR: could not clone TPM." >&2; return 1; }
    fi
}

install_plugins() {
    info "Installing tmux plugins..."
    "$TPM_DIR/bin/install_plugins" \
        || echo "warning: plugin install needs attention: press Ctrl+A, Shift+I inside tmux."
    info "Updating tmux plugins..."
    "$TPM_DIR/bin/update_plugins" all \
        || echo "warning: plugin update needs attention: press Ctrl+A, Shift+U inside tmux."
}

run_update() {
    if ! command_exists tmux; then
        echo "ERROR: tmux is not installed. Run: brew bundle install --file $REPO/Brewfile" >&2
        return 1
    fi
    if ! command_exists git; then
        echo "ERROR: git is required to install TPM." >&2
        return 1
    fi
    if [ ! -f "$SRC" ]; then
        echo "ERROR: $SRC not found." >&2
        return 1
    fi

    # Validate before touching anything, so a broken config in the repo
    # never replaces a working ~/.tmux.conf.
    local errs
    if ! errs="$(validate_conf "$SRC")"; then
        echo "ERROR: $SRC has errors; leaving ~/.tmux.conf untouched." >&2
        printf '%s\n' "$errs" >&2
        return 1
    fi

    command_exists sesh || echo "warning: sesh not installed; run 'brew install sesh' for the Ctrl+A, Shift+T picker."

    link_config || return 1
    install_tpm || return 1

    # A server started before TPM existed never ran tpm, so it lacks
    # TMUX_PLUGIN_MANAGER_PATH and install_plugins aborts. Reload first so
    # tpm runs, then reload again afterwards so new plugins take effect.
    local server_running=0
    if tmux list-sessions >/dev/null 2>&1; then
        server_running=1
        tmux source-file "$TARGET" >/dev/null 2>&1
    fi

    install_plugins

    if [ "$server_running" = 1 ]; then
        info "Reloading running tmux server..."
        tmux source-file "$TARGET" || echo "warning: reload reported errors; check with 'dotfiles tmux check'."
    fi

    echo ""
    run_check
}

usage() {
    cat <<'USAGE'
dotfiles tmux: manage the tmux workspace (tmux + TPM + sesh).

Usage:
  dotfiles tmux check     Verify config link, syntax, TPM, plugins, and tools.
                          Read-only. Exits 1 if anything FAILs.
  dotfiles tmux update    Back up any existing ~/.tmux.conf, link the dotfiles
                          version, install/update TPM + plugins, reload tmux.
  dotfiles tmux diff      Show how ~/.tmux.conf differs from the dotfiles version.
USAGE
}

main() {
    local cmd="${1:-check}"
    [ $# -gt 0 ] && shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --embedded) EMBEDDED=1 ;;
            --color)    COLOR=always ;;
            --no-color) COLOR=never ;;
            *) echo "tmux-setup: unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
    setup_colors

    case "$cmd" in
        check)          run_check ;;
        update|install) run_update ;;
        diff)
            if [ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SRC" ]; then
                echo "~/.tmux.conf is linked to the dotfiles version; nothing to diff."
            else
                diff -u "$TARGET" "$SRC"
            fi
            ;;
        -h|--help|help) usage ;;
        *) echo "tmux-setup: unknown command: $cmd" >&2; usage >&2; exit 2 ;;
    esac
}

main "$@"
