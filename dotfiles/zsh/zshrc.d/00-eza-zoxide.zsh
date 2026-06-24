# ---- Eza (better ls) ----
if command -v eza >/dev/null 2>&1; then
  alias ls="eza --icons=always"
fi

# ---- Zoxide (better cd) ----
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
