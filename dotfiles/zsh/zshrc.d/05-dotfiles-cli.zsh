# ---- dotfiles CLI ----
# Tiny wrapper so 'dotfiles update' (and friends) is always one command away.
dotfiles() {
  local repo="$HOME/.dotfiles"
  case "${1:-}" in
    update)
      (cd "$repo" && ./install.sh update)
      ;;
    status)
      git -C "$repo" fetch --quiet 2>/dev/null
      git -C "$repo" status --short --branch
      local behind ahead
      behind=$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
      ahead=$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
      echo "Behind upstream: $behind | Ahead: $ahead"
      ;;
    log)
      git -C "$repo" log --oneline -20
      ;;
    edit)
      if command -v cursor >/dev/null 2>&1; then
        cursor "$repo"
      else
        ${EDITOR:-vi} "$repo"
      fi
      ;;
    cd)
      cd "$repo"
      ;;
    doctor)
      shift
      "$repo/scripts/dotfiles-doctor.sh" "$@"
      ;;
    rollback)
      shift
      "$repo/scripts/dotfiles-rollback.sh" "$@"
      ;;
    -h|--help|"")
      cat <<'USAGE'
dotfiles — manage your dotfiles repo.

Usage:
  dotfiles update     Pull repo, run Brewfile, refresh ~/.zshrc managed block,
                      update brew formulae/casks + Oh My Zsh + plugins.
  dotfiles status     Show repo status + commits ahead/behind upstream.
  dotfiles log        Show last 20 commits in ~/.dotfiles.
  dotfiles edit       Open ~/.dotfiles in your editor (cursor or $EDITOR).
  dotfiles cd         cd into ~/.dotfiles.
  dotfiles doctor     Health-check the dotfiles stack (PASS/WARN/FAIL).
                      Run this when something feels off after an update.
  dotfiles rollback   Restore ~/.zshrc from the most recent timestamped
                      backup (taken before every install/update).
                      Use '--list' to see backups, '-y' to skip confirmation.
USAGE
      ;;
    *)
      echo "dotfiles: unknown subcommand: $1 (try 'dotfiles --help')" >&2
      return 1
      ;;
  esac
}
