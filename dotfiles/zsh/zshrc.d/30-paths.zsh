# ---- ~/.local/bin on PATH ----
# uv, pipx, cargo-installed binaries, and many "curl | sh" installers
# (rustup, deno, bun, etc.) drop binaries here. Without this on PATH,
# gwtree's `command -v uv` check silently skipped uv setup and made
# the new worktree unusable. So: if the dir exists, put it on PATH.
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# If a tool installer also dropped a managed env file (uv does this:
# ~/.local/bin/env), source it so any installer-managed exports apply.
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
