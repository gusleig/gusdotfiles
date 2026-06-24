#!/usr/bin/env bash
# dotfiles-rollback — restore ~/.zshrc from the most recent dotfiles backup.
#
# The install script takes timestamped backups before any mutation:
#   ~/.zshrc.before-install.<ts>
#   ~/.zshrc.before-update.<ts>
#   ~/.zshrc.before-legacy-migration.<ts>
#
# This script finds the newest one, shows a diff against the current
# ~/.zshrc, and (with confirmation, or -y) restores it.
#
# Usage:
#   dotfiles rollback         # interactive, confirms before restoring
#   dotfiles rollback -y      # restore without prompting
#   dotfiles rollback --list  # just list available backups, do not restore

set -uo pipefail

ZSHRC="$HOME/.zshrc"
YES=0
LIST_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)  YES=1; shift ;;
        --list)    LIST_ONLY=1; shift ;;
        -h|--help)
            cat <<'USAGE'
dotfiles rollback — restore ~/.zshrc from the most recent backup.

Usage:
  dotfiles rollback           Restore most recent backup (asks for confirmation).
  dotfiles rollback -y        Restore without prompting.
  dotfiles rollback --list    Show available backups, do not restore.
  dotfiles rollback -h        This help.
USAGE
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

shopt -s nullglob
backups=(
    "$HOME"/.zshrc.before-install.*
    "$HOME"/.zshrc.before-update.*
    "$HOME"/.zshrc.before-legacy-migration.*
    "$HOME"/.zshrc.backup*
)
shopt -u nullglob

if [ "${#backups[@]}" -eq 0 ]; then
    echo "No ~/.zshrc backups found." >&2
    echo "Backups are created automatically when you run 'dotfiles update' or 'install.sh'." >&2
    exit 1
fi

# Newest by mtime first.
IFS=$'\n' backups_sorted=($(ls -t -- "${backups[@]}"))
unset IFS

if [ "$LIST_ONLY" -eq 1 ]; then
    echo "Available ~/.zshrc backups (newest first):"
    for b in "${backups_sorted[@]}"; do
        size=$(wc -l < "$b" | tr -d ' ')
        when=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$b" 2>/dev/null \
               || stat -c '%y' "$b" 2>/dev/null)
        printf "  %s  (%s lines, %s)\n" "$b" "$size" "$when"
    done
    exit 0
fi

newest="${backups_sorted[0]}"

echo "Most recent backup: $newest"
size=$(wc -l < "$newest" | tr -d ' ')
when=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$newest" 2>/dev/null \
       || stat -c '%y' "$newest" 2>/dev/null)
echo "  $size lines, $when"
echo

if [ -f "$ZSHRC" ]; then
    if diff -q "$ZSHRC" "$newest" >/dev/null 2>&1; then
        echo "~/.zshrc is already identical to the newest backup. Nothing to do."
        exit 0
    fi
    echo "Diff (current ~/.zshrc -> backup):"
    if command -v delta >/dev/null 2>&1; then
        diff -u "$ZSHRC" "$newest" | delta || true
    else
        diff -u "$ZSHRC" "$newest" | head -100 || true
    fi
    echo
fi

if [ "$YES" -ne 1 ]; then
    printf "Restore ~/.zshrc from this backup? [y/N] "
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

# Safety: save current ~/.zshrc *before* overwriting it, in case the user
# changes their mind. Yes — even rollback is reversible.
if [ -f "$ZSHRC" ]; then
    pre_rollback="$ZSHRC.before-rollback.$(date +%Y%m%d%H%M%S)"
    cp "$ZSHRC" "$pre_rollback"
    echo "Saved current ~/.zshrc -> $pre_rollback"
fi

cp "$newest" "$ZSHRC"
echo "Restored ~/.zshrc from $newest"

# Validate the restored file actually starts a shell.
if zsh -i -c ':' >/dev/null 2>&1; then
    echo "Verified: 'zsh -i' starts cleanly with the restored ~/.zshrc."
else
    echo "WARNING: the restored ~/.zshrc still fails to start a shell." >&2
    echo "         Inspect ~/.zshrc and the backup file directly." >&2
    exit 1
fi

echo
echo "Open a new shell (or 'source ~/.zshrc') to pick up the rollback."
exit 0
