#!/usr/bin/env bash
# dotfiles-doctor — health check for the ~/.dotfiles stack.
#
# Runs a series of independent checks (PASS / WARN / FAIL) so the user
# can quickly see what's broken before symptoms cascade. Exits non-zero
# if any FAIL.
#
# Usage: dotfiles doctor  (preferred)  OR  ~/.dotfiles/scripts/dotfiles-doctor.sh

set -uo pipefail

REPO="$HOME/.dotfiles"
ZSHRC="$HOME/.zshrc"
ZSHRC_LOCAL="$HOME/.zshrc.local"
SNIPPETS_DIR="$REPO/dotfiles/zsh/zshrc.d"
BREWFILE="$REPO/Brewfile"

pass=0
warn=0
fail=0

# Colors only when stdout is a TTY.
if [ -t 1 ]; then
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_RESET=""
fi

say_pass() { printf "  ${C_GREEN}PASS${C_RESET}  %s\n" "$1"; pass=$((pass+1)); }
say_warn() { printf "  ${C_YELLOW}WARN${C_RESET}  %s\n" "$1"; [ -n "${2:-}" ] && printf "        ${C_DIM}%s${C_RESET}\n" "$2"; warn=$((warn+1)); }
say_fail() { printf "  ${C_RED}FAIL${C_RESET}  %s\n" "$1"; [ -n "${2:-}" ] && printf "        ${C_DIM}%s${C_RESET}\n" "$2"; fail=$((fail+1)); }

section() { printf "\n%s\n" "$1"; }

# ---------- 1. Repo presence + git status ----------
section "Dotfiles repo"

if [ -d "$REPO/.git" ]; then
    say_pass "~/.dotfiles is a git repo"

    git -C "$REPO" fetch --quiet 2>/dev/null || true
    behind=$(git -C "$REPO" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
    ahead=$(git -C "$REPO" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)

    if [ "$behind" -gt 0 ]; then
        say_warn "$behind commit(s) behind upstream" "Run 'dotfiles update' to pull."
    else
        say_pass "Up to date with upstream"
    fi

    if [ "$ahead" -gt 0 ]; then
        say_warn "$ahead local commit(s) ahead of upstream" "Push when ready: git -C ~/.dotfiles push"
    fi

    if ! git -C "$REPO" diff --quiet 2>/dev/null || ! git -C "$REPO" diff --cached --quiet 2>/dev/null; then
        say_warn "~/.dotfiles has uncommitted changes" "git -C ~/.dotfiles status"
    fi
else
    say_fail "~/.dotfiles is not a git repo" "Re-clone: gh repo clone <you>/dotfiles ~/.dotfiles"
fi

# ---------- 2. ~/.zshrc + managed block ----------
section "~/.zshrc + managed block"

if [ -f "$ZSHRC" ]; then
    say_pass "~/.zshrc exists"

    if grep -qF '# === DOTFILES MANAGED BLOCK :: BEGIN' "$ZSHRC" \
       && grep -qF '# === DOTFILES MANAGED BLOCK :: END'   "$ZSHRC"; then
        say_pass "Managed block present"

        block_count=$(grep -c '^# === DOTFILES MANAGED BLOCK :: BEGIN' "$ZSHRC")
        if [ "$block_count" -gt 1 ]; then
            say_warn "Managed block appears ${block_count} times (expected 1)" \
                     "Run 'dotfiles update' to consolidate."
        fi
    else
        say_fail "Managed block missing" \
                 "Re-run install: cd ~/.dotfiles && ./install.sh"
    fi

    if grep -qE '^# ---- Eza \(better ls\) ----$' "$ZSHRC"; then
        say_warn "Legacy inline block still present in ~/.zshrc" \
                 "Run 'dotfiles update' to quarantine it."
    fi
else
    say_fail "~/.zshrc does not exist" "Re-run install: cd ~/.dotfiles && ./install.sh"
fi

# Can a fresh zsh start with this config?
if zsh -i -c ':' >/dev/null 2>&1; then
    say_pass "Fresh 'zsh -i' starts cleanly"
else
    say_fail "Fresh 'zsh -i' fails to start" \
             "Run 'dotfiles rollback' to restore your last working ~/.zshrc."
fi

# ---------- 3. zshrc.d snippets ----------
section "Snippet directory"

if [ -d "$SNIPPETS_DIR" ]; then
    snippet_count=$(find "$SNIPPETS_DIR" -maxdepth 1 -name '*.zsh' -type f | wc -l | tr -d ' ')
    say_pass "$SNIPPETS_DIR exists ($snippet_count snippet file(s))"

    syntax_failures=0
    for f in "$SNIPPETS_DIR"/*.zsh; do
        [ -f "$f" ] || continue
        if ! zsh -n "$f" 2>/dev/null; then
            say_fail "$(basename "$f"): zsh syntax error" "zsh -n $f"
            syntax_failures=$((syntax_failures+1))
        fi
    done
    if [ "$syntax_failures" -eq 0 ]; then
        say_pass "All snippet files pass 'zsh -n'"
    fi
else
    say_fail "Snippet dir missing: $SNIPPETS_DIR"
fi

# ---------- 4. ~/.zshrc.local ----------
section "User-local config"

if [ -f "$ZSHRC_LOCAL" ]; then
    say_pass "~/.zshrc.local exists"
    if zsh -n "$ZSHRC_LOCAL" 2>/dev/null; then
        say_pass "~/.zshrc.local passes 'zsh -n'"
    else
        say_fail "~/.zshrc.local has zsh syntax errors" "zsh -n ~/.zshrc.local"
    fi
else
    say_warn "~/.zshrc.local not present" \
             "Optional. Will be created on next install/update for work-specific config."
fi

# Any quarantined legacy blocks lying around?
for q in "$HOME"/.dotfiles-legacy-block.*.zsh; do
    [ -f "$q" ] || continue
    say_warn "Quarantined legacy block at $q" \
             "Review, move any custom lines to ~/.zshrc.local, then 'rm $q'."
done

# ---------- 5. Brewfile / brew ----------
section "Brewfile / Homebrew"

if command -v brew >/dev/null 2>&1; then
    say_pass "brew is installed ($(brew --version | head -1))"

    if [ -f "$BREWFILE" ]; then
        say_pass "Brewfile exists"
        missing=$(brew bundle check --file "$BREWFILE" 2>&1 || true)
        if echo "$missing" | grep -q "The Brewfile's dependencies are satisfied"; then
            say_pass "All Brewfile-declared packages installed"
        else
            say_warn "Some Brewfile packages are missing" \
                     "Run 'dotfiles update' (or 'brew bundle install --file $BREWFILE')."
        fi
    else
        say_warn "Brewfile not found at $BREWFILE"
    fi
else
    say_warn "brew not installed" "Install from https://brew.sh if on macOS."
fi

# ---------- 6. opal CLI sanity (only if installed) ----------
section "Opal CLI (if installed)"

if command -v opal >/dev/null 2>&1; then
    opal_path=$(command -v opal)
    shebang=$(head -1 "$opal_path" 2>/dev/null)
    if [[ "$shebang" =~ ^\#! ]]; then
        interpreter=$(echo "$shebang" | sed 's/^#!//' | awk '{print $1}')
        if [ -x "$interpreter" ]; then
            say_pass "opal interpreter exists: $interpreter"
        else
            say_fail "opal shebang points to missing interpreter: $interpreter" \
                     "Fix: 'brew install node' (or 'brew reinstall opal')."
        fi
    fi
else
    say_pass "opal CLI not installed (skipped)"
fi

# ---------- 7. AWS credentials sanity ----------
section "AWS credentials (sanity)"

CREDS="$HOME/.aws/credentials"
if [ -f "$CREDS" ]; then
    profiles_total=$(grep -c '^\[' "$CREDS" 2>/dev/null || echo 0)
    profiles_with_keys=$(awk '
      /^\[/ { p=$0; has=0; next }
      /^aws_access_key_id[[:space:]]*=[[:space:]]*[^[:space:]]/ {
        if (!has) { print p; has=1 }
      }
    ' "$CREDS" | wc -l | tr -d ' ')
    profiles_empty=$((profiles_total - profiles_with_keys))

    if [ "$profiles_with_keys" -gt 0 ]; then
        say_pass "$profiles_with_keys / $profiles_total profile(s) in ~/.aws/credentials have populated keys"
    else
        say_warn "All $profiles_total profile(s) in ~/.aws/credentials are empty" \
                 "Run your login command (e.g. aws-login-prod) to populate one."
    fi

    if [ "$profiles_empty" -gt 0 ]; then
        say_warn "$profiles_empty profile(s) have only a [header] with no keys" \
                 "Likely expired. Re-login to refresh."
    fi

    # Does AWS_PROFILE point at a populated profile?
    if [ -n "${AWS_PROFILE:-}" ]; then
        if awk -v p="[$AWS_PROFILE]" '
              $0 == p { in_section=1; next }
              /^\[/   { in_section=0 }
              in_section && /^aws_access_key_id[[:space:]]*=[[:space:]]*[^[:space:]]/ { found=1; exit }
              END { exit !found }
           ' "$CREDS" 2>/dev/null; then
            say_pass "AWS_PROFILE=$AWS_PROFILE has populated creds"
        else
            say_fail "AWS_PROFILE=$AWS_PROFILE but that profile has no keys" \
                     "Re-login or 'aws-profile <other-profile>'."
        fi
    fi
else
    say_pass "No ~/.aws/credentials (skipped)"
fi

# ---------- Summary ----------
section "Summary"
printf "  ${C_GREEN}%d pass${C_RESET}  ${C_YELLOW}%d warn${C_RESET}  ${C_RED}%d fail${C_RESET}\n" \
    "$pass" "$warn" "$fail"

if [ "$fail" -gt 0 ]; then
    exit 1
fi
exit 0
