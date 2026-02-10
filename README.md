# My Dotfiles

Personal dotfiles and setup scripts for macOS/Linux. Includes Zsh (Oh My Zsh + Powerlevel10k), a terminal-first tool stack, optional yabai/skhd/sketchybar, and a custom git worktree helper.

## Installation

1. Clone this repository into your home directory:

```bash
git clone https://github.com/gusleig/gusdotfiles.git ~/.dotfiles
```

2. Run the installation script:

```bash
cd ~/.dotfiles
chmod +x install.sh
./install.sh
```

The script will prompt you for:

- **Terminal:** iTerm2 or Ghostty
- **Sketchybar** (status bar): optional
- **AWS CLI** (includes S3): optional
- **Update now:** optionally update Homebrew, Oh My Zsh, and plugins right after install

To only update installed software later:

```bash
./install.sh update
```

For Sketchybar (if you chose to install it), disable the menu bar in **System Settings → Control Center**.

### Install context for AI (Cursor and Claude Code)

The install script makes the list of installed CLI tools visible to AI so it can suggest valid commands (eza, bat, rg, fd, lazygit, gwtree, etc.).

- **Cursor**  
  Symlinks `.cursor/rules/` to `~/.cursor/rules/`. The rule **installed-tools.mdc** applies when you work in this repo or in a workspace that includes `~/.cursor/rules/`.  
  For other projects: copy `~/.dotfiles/.cursor/rules/installed-tools.mdc` into that project’s `.cursor/rules/`, or add it via **Cursor → Settings → Rules → User Rules**.

- **Claude Code only (no Cursor)**  
  Claude Code loads context from **~/.claude/CLAUDE.md**. The install script:
  - Symlinks `~/.claude/dotfiles-tools.md` → this repo’s `claude/dotfiles-tools.md`.
  - If `~/.claude/CLAUDE.md` does not exist, creates it with the tools list.
  - If it already exists, appends the tools section once (skips if already present).

  So if you use Claude Code but not Cursor, the same tools list is still loaded from `~/.claude/CLAUDE.md`.

![alt text](image.png)

## Directory Structure

```
~/.dotfiles/
├── install.sh              # Main installation script
├── install_sketchybar.sh   # Sketchybar setup (optional, run via install.sh prompt)
├── README.md
├── .cursor/
│   └── rules/
│       └── installed-tools.mdc   # Cursor: rule listing available CLI tools
├── claude/
│   └── dotfiles-tools.md        # Claude Code: same tools list for ~/.claude/CLAUDE.md
├── dotfiles/
│   ├── skhdrc.symlink      # skhd hotkey config
│   └── yabairc.symlink     # yabai window manager config
├── borders/
│   └── bordersrc.symlink   # yabai borders config
└── sketchybar/            # sketchybar config (if used)
```

## Tools

Brief intro and examples for each tool installed by the script.

### Shell & navigation

- **eza** — Modern `ls` with icons and better defaults.  
  `ls` is aliased to `eza --icons=always`.  
  Examples: `ls`, `ls -la`, `ls -T` (tree).

- **zoxide** — Smarter `cd` using your history.  
  Examples: `z proj` (jump to a path containing “proj”), `z ~/code/foo`.

- **fzf** — Fuzzy finder.  
  **Ctrl+R** in the shell: fuzzy search command history.  
  Tab completion: type `**` and Tab to fuzzy-find files.

### Viewing & searching

- **bat** — Syntax-highlighted `cat`.  
  Examples: `bat install.sh`, `bat -l json package.json`.

- **ripgrep (rg)** — Fast search in files.  
  Examples: `rg "function_name"`, `rg -t py "import os"`, `rg --no-ignore "TODO"`.

- **fd** — Simple, fast `find`.  
  Examples: `fd "*.py"`, `fd -e json`, `fd config`.

- **watch** — Run a command repeatedly.  
  Examples: `watch -n 2 'git status'`, `watch -n 1 'ls -la'`.

### Git

- **lazygit** — TUI for git (commit, branches, stash, diff, logs).  
  Example: run `lazygit` in any repo.

- **delta** — Better git diffs (syntax highlighting, side-by-side).  
  Used automatically for `git diff` and inside LazyGit.

- **gh** — GitHub CLI.  
  Examples: `gh pr list`, `gh pr checkout 123`, `gh repo clone owner/repo`, `gh issue create`.

- **gwtree** — Custom worktree helper: create a worktree, set up uv + dbt, open LazyGit.  
  Usage: `gwtree <name> [branch]`  
  Examples:  
  `gwtree my-feature` → creates `../wt/my-feature` on branch `feature/my-feature`.  
  `gwtree hotfix main` → creates `../wt/hotfix` on branch `main`.

### Other

- **mole** — Reverse SSH tunnels.  
  Example: expose a local port or reach a remote host via tunnel.

- **tmux** — Terminal multiplexer (sessions, panes, windows).  
  Examples: `tmux new -s dev`, `tmux attach -t dev`.

- **tree** — Directory tree.  
  Example: `tree -L 2`.

- **AWS CLI** (optional) — If you chose to install it: S3, Lambda, and other AWS services from the terminal.  
  Examples: `aws s3 ls`, `aws s3 cp file.txt s3://bucket/`, `aws configure`.

### macOS-specific (when using Homebrew)

- **yabai** — Tiling window manager.
- **skhd** — Hotkey daemon (binds keys to yabai and other actions).
- **Sketchybar** (optional) — Status bar.
- **Alt-tab** — Cask for window switching.
- **Raycast** — Launcher and productivity app (Spotlight alternative). Open from terminal: `open -a Raycast`, or use its global shortcut after first launch.
- **iTerm2 or Ghostty** — Your chosen terminal.

## What the install script does

1. Installs packages (via Homebrew on macOS, or apt/yum on Linux where supported).
2. Installs Oh My Zsh and Powerlevel10k.
3. Installs plugins: zsh-autosuggestions, zsh-syntax-highlighting.
4. Creates symlinks from `dotfiles/*.symlink` to `~/.filename` (e.g. `~/.skhdrc`, `~/.yabairc`).
5. Configures fzf keybindings and delta as the git pager.
6. Adds to `.zshrc`: eza alias, zoxide init, and the `gwtree` function.
7. On macOS: starts yabai/skhd if present, installs fonts, Alt-tab, and Raycast; optionally Sketchybar and AWS CLI.

## Post-installation

1. Restart your terminal.
2. Set the terminal font to **MesloLGS NF**.
3. Run `p10k configure` to set up Powerlevel10k.
4. Check symlinks: `ls -la ~ | grep -E '\.(skhd|yabai)'`

## Adding new dotfiles

1. Put the file in `dotfiles/` with a `.symlink` extension (e.g. `dotfiles/myrc.symlink`).
2. Run `./install.sh` again; it will symlink to `~/.myrc`.

## Customization

- Edit any `*.symlink` file under `dotfiles/` or `borders/`; changes are in git.
- Adjust the `gwtree` function or other blocks in the section the install script appends to your `.zshrc`.

## Reloading configurations

After editing configs, restart the service:

```bash
# yabai
yabai --restart-service

# skhd
skhd --restart-service
```

## Updating

Update the repo and re-run the installer to refresh symlinks:

```bash
cd ~/.dotfiles
git pull
./install.sh
```

Update all installed tools (Homebrew, Oh My Zsh, Powerlevel10k, plugins):

```bash
./install.sh update
```

## Troubleshooting

### Symlinks

If symlinks are wrong, fix manually:

```bash
ln -sf ~/.dotfiles/dotfiles/skhdrc.symlink ~/.skhdrc
ln -sf ~/.dotfiles/dotfiles/yabairc.symlink ~/.yabairc
ln -sf ~/.dotfiles/borders/bordersrc.symlink ~/.config/borders/bordersrc
```

### skhd

- Service: `skhd --check-service`
- Logs: `tail -f ~/.skhd.log` and `tail -f ~/.skhd.err.log`
- Grant **Accessibility** in **System Settings → Privacy & Security → Accessibility**

### yabai

- Service: `yabai --check-service`
- Logs: `tail -f ~/.yabai.log` and `tail -f ~/.yabai.err.log`
- On Apple Silicon, yabai may require [disabling SIP](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection) (e.g. `csrutil enable --without fs --without debug --without nvram` in Recovery, then `sudo nvram boot-args=-arm64e_preview_abi` after reboot).

### Fonts / Powerlevel10k

If Powerlevel10k looks wrong:

1. Confirm **MesloLGS NF** is installed (install script installs it under `~/.local/share/fonts`).
2. Set your terminal font to MesloLGS NF.
3. Restart the terminal.
