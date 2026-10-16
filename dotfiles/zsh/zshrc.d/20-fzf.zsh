# ---- fzf (fuzzy finder: Ctrl+R history, Ctrl+T files, ** tab completion) ----
# fzf 0.48+ prints its own zsh setup with 'fzf --zsh'. An older install
# script wrote ~/.fzf.zsh instead, so use that file when it exists.
if [ -f ~/.fzf.zsh ]; then
  source ~/.fzf.zsh
elif command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh 2>/dev/null)
fi
