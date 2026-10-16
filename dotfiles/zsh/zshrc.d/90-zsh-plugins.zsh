# ---- zsh-autosuggestions + zsh-syntax-highlighting (installed by brew) ----
# Skip a plugin that is already loaded (an Oh My Zsh plugin or a line in
# ~/.zshrc). syntax-highlighting must load after other widgets, so this
# file sorts late, just before 99-local.zsh.
for _df_share in "${HOMEBREW_PREFIX:-}/share" /opt/homebrew/share /usr/local/share /home/linuxbrew/.linuxbrew/share /usr/share; do
  [ -d "$_df_share/zsh-autosuggestions" ] || [ -d "$_df_share/zsh-syntax-highlighting" ] || continue
  if ! (( $+functions[_zsh_autosuggest_start] )) && [ -r "$_df_share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
    source "$_df_share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  fi
  if [ -z "${ZSH_HIGHLIGHT_VERSION:-}" ] && [ -r "$_df_share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
    source "$_df_share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  fi
  break
done
unset _df_share
