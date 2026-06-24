# ---- User-local shell config (~/.zshrc.local) ----
# Put any machine-/work-specific shell config in ~/.zshrc.local.
# That file is NOT tracked in ~/.dotfiles and survives every
# 'dotfiles update' (the legacy-block migration cannot touch it).
[ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
