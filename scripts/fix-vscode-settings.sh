#!/usr/bin/env bash
set -euo pipefail

# Requires Bash 4+ (associative arrays). Install via: brew install bash
if [[ -z "${BASH_VERSINFO[0]}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "This script requires Bash 4+. You have: $(bash --version | head -1)"
  echo "Install with: brew install bash (then ensure /opt/homebrew/bin is in PATH)"
  exit 1
fi

# Fix VS Code / Cursor / Windsurf editor behavior on macOS
# - Disables preview tabs (prevents files from "closing" when opening another)
# - Keeps side-by-side direction consistent
# - Ensures tabs are shown
#
# It edits the User settings.json, preserving existing settings.
# A timestamped backup is created before modifications.

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is intended for macOS (Darwin). Detected: $(uname -s)"
  exit 1
fi

# Settings we want to enforce
KEYS_JSON='{
  "workbench.editor.enablePreview": false,
  "workbench.editor.enablePreviewFromQuickOpen": false,
  "workbench.editor.openSideBySideDirection": "right",
  "workbench.editor.showTabs": true
}'

# Candidate settings.json paths
declare -a CANDIDATES=(
  "$HOME/Library/Application Support/Code/User/settings.json"           # VS Code (stable)
  "$HOME/Library/Application Support/Code - Insiders/User/settings.json" # VS Code Insiders
  "$HOME/Library/Application Support/Cursor/User/settings.json"         # Cursor
  "$HOME/Library/Application Support/Windsurf/User/settings.json"        # Windsurf (common)
  "$HOME/Library/Application Support/Windsurf - Insiders/User/settings.json" # Windsurf alt
)

# Build map of editor id -> settings.json path (Bash 4+ associative array)
declare -A FOUND=()
for p in "${CANDIDATES[@]}"; do
  if [[ -f "$p" ]]; then
    if [[ "$p" == *"/Code - Insiders/"* ]]; then
      FOUND[vscode-insiders]="$p"
    elif [[ "$p" == *"/Code/"* ]]; then
      FOUND[vscode]="$p"
    elif [[ "$p" == *"/Cursor/"* ]]; then
      FOUND[cursor]="$p"
    elif [[ "$p" == *"/Windsurf - Insiders/"* ]]; then
      FOUND[windsurf-insiders]="$p"
    elif [[ "$p" == *"/Windsurf/"* ]]; then
      FOUND[windsurf]="$p"
    fi
  fi
done

if [[ ${#FOUND[@]} -eq 0 ]]; then
  echo "No settings.json files found for VS Code, Cursor, or Windsurf in common locations."
  echo "If you know your settings.json path, you can edit it manually via:"
  echo "  Cmd+Shift+P → Preferences: Open User Settings (JSON)"
  exit 1
fi

echo "Found the following editors/settings:"
for k in "${!FOUND[@]}"; do
  echo "  - $k: ${FOUND[$k]}"
done
echo

echo "Which one do you want to update?"
echo "  - Type one of: ${!FOUND[*]}"
echo "  - Or type: all"
read -r -p "> " CHOICE

apply_fix() {
  local file="$1"

  # Backup
  local ts
  ts="$(date +"%Y%m%d-%H%M%S")"
  local backup="${file}.bak.${ts}"
  cp "$file" "$backup"
  echo "Backup created: $backup"

  # Ensure file is valid JSON or initialize it if empty
  if [[ ! -s "$file" ]]; then
    echo "{}" > "$file"
  fi

  # Use system python3 to merge JSON safely
  /usr/bin/python3 - <<PY
import json
from pathlib import Path

file_path = Path(r"$file")
keys = json.loads(r'''$KEYS_JSON''')

# Read current settings (tolerate comments? settings.json should be pure JSON)
try:
    current = json.loads(file_path.read_text(encoding="utf-8"))
    if not isinstance(current, dict):
        current = {}
except Exception:
    # If parse fails, don't destroy user's file; abort with a helpful message.
    raise SystemExit(f"ERROR: Could not parse JSON in {file_path}.\\n"
                     f"Open it and fix JSON syntax, then re-run.")

# Merge (overwrite only the keys we manage)
current.update(keys)

file_path.write_text(json.dumps(current, indent=2, ensure_ascii=False) + "\\n", encoding="utf-8")
print(f"Updated: {file_path}")
PY
}

if [[ "$CHOICE" == "all" ]]; then
  for k in "${!FOUND[@]}"; do
    echo
    echo "== Updating $k =="
    apply_fix "${FOUND[$k]}"
  done
else
  if [[ -z "${FOUND[$CHOICE]+x}" ]]; then
    echo "Invalid choice: $CHOICE"
    echo "Valid: ${!FOUND[*]} or all"
    exit 1
  fi
  echo
  echo "== Updating $CHOICE =="
  apply_fix "${FOUND[$CHOICE]}"
fi

echo
echo "Done."
echo "Tip: If the editor is open, changes usually apply immediately, but sometimes a restart helps."