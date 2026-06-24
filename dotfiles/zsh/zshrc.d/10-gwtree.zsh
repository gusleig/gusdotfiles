# ---- Git worktree helper (gwtree = git worktree; avoids conflict with git plugin's gwt) ----
# Usage:
#   gwtree <name> [-f] [-y]
#       → ../wt/<name>, branch <name>
#       -f / --feature   Prefix branch with 'feature/' (→ feature/<name>).
#       -y / --yes       Skip the confirmation prompt.
#   gwtree feat <ticket> <description> [-y]
#       → ../wt/<description>, branch feature/<ticket>/<description>
#   gwtree from <branch> [<name>] [-y]
#       → ../wt/<name|basename(branch)>, checks out existing <branch>
#   gwtree -h | --help
gwtree() {
  local use_feature=0 skip_confirm=0
  local args=()
  local a

  for a in "$@"; do
    case "$a" in
      -h|--help)
        cat <<'USAGE'
gwtree — create a git worktree, set up uv + dbt, open lazygit.

Usage:
  gwtree <name> [-f] [-y]
      Folder ../wt/<name>, branch <name>.
      -f / --feature   Prefix branch with 'feature/' (→ feature/<name>).
      -y / --yes       Skip the confirmation prompt.

  gwtree feat <ticket> <description> [-y]
      Folder ../wt/<description>, branch feature/<ticket>/<description>.

  gwtree from <branch> [<name>] [-y]
      Folder ../wt/<name> (default: basename of <branch>),
      checks out existing <branch> in the new worktree.

  gwtree -h | --help     Show this help.
USAGE
        return 0
        ;;
      -f|--feature) use_feature=1 ;;
      -y|--yes)     skip_confirm=1 ;;
      -*)
        echo "gwtree: unknown flag: $a (try 'gwtree --help')" >&2
        return 1
        ;;
      *) args+=("$a") ;;
    esac
  done

  if [[ ${#args[@]} -eq 0 ]]; then
    echo "gwtree: missing argument. See 'gwtree --help'." >&2
    return 1
  fi

  local wt_name branch new_branch=1

  case "${args[1]}" in
    feat)
      local ticket="${args[2]:-}" desc="${args[3]:-}"
      if [[ -z "$ticket" || -z "$desc" ]]; then
        echo "usage: gwtree feat <ticket> <description>" >&2
        return 1
      fi
      wt_name="$desc"
      branch="feature/${ticket}/${desc}"
      ;;
    from)
      branch="${args[2]:-}"
      if [[ -z "$branch" ]]; then
        echo "usage: gwtree from <branch> [<name>]" >&2
        return 1
      fi
      wt_name="${args[3]:-${branch##*/}}"
      new_branch=0
      ;;
    *)
      wt_name="${args[1]}"
      if [[ $use_feature -eq 1 ]]; then
        branch="feature/${wt_name}"
      else
        branch="$wt_name"
      fi
      ;;
  esac

  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "gwtree: not inside a git repository" >&2
    return 1
  }

  local wt_base="${root%/*}/wt"
  local wt_path="${wt_base}/${wt_name}"

  if [[ $new_branch -eq 1 ]]; then
    echo "gwtree: will create worktree '${wt_path}' on NEW branch '${branch}'"
  else
    echo "gwtree: will create worktree '${wt_path}' from existing branch '${branch}'"
  fi

  if [[ $skip_confirm -eq 0 ]]; then
    printf 'Continue? [Y/n] '
    local reply
    read -r reply
    case "$reply" in
      n|N|no|NO|No) echo "gwtree: cancelled"; return 1 ;;
    esac
  fi

  mkdir -p "$wt_base" || return 1

  if [[ $new_branch -eq 1 ]]; then
    git -C "$root" worktree add -b "$branch" "$wt_path" || return 1
  else
    git -C "$root" worktree add "$wt_path" "$branch" || return 1
  fi
  cd "$wt_path" || return 1

  [ -f "$root/CLAUDE.md" ] && cp "$root/CLAUDE.md" "$wt_path/"
  [ -d "$root/.claude" ] && cp -r "$root/.claude" "$wt_path/"

  export UV_PROJECT_ENVIRONMENT=".venv"
  if command -v uv >/dev/null 2>&1; then
    uv venv --quiet || return 1
    uv sync || return 1
    source .venv/bin/activate || return 1
  fi

  export DBT_PROFILES_DIR="${DBT_PROFILES_DIR:-$wt_path/dbt}"
  export DBT_TARGET_PATH="target"
  export DBT_LOG_PATH="logs"
  mkdir -p "$DBT_LOG_PATH"
  if command -v dbt >/dev/null 2>&1; then
    if [ -f dbt/dbt_project.yml ]; then
      (cd dbt && dbt deps) || echo "gwtree: warning: 'dbt deps' failed (you can rerun it manually from dbt/)"
    elif [ -f dbt_project.yml ]; then
      if ! dbt deps; then
        echo "gwtree: warning: 'dbt deps' failed (you can rerun it manually)"
      fi
    fi
  fi

  command -v lazygit >/dev/null 2>&1 && lazygit
}
