#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# orca-worktree — manage git worktrees for orca workers
# ---------------------------------------------------------------------------

ORCA_DIR="${ORCA_ROOT:-.}/.orca/worktree"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  create <slug>   Create worktree at $ORCA_DIR/<slug> on branch orca-<slug>
  remove <slug>   Remove worktree and delete branch orca-<slug>
  list            List active orca worktrees
  clean           Remove all orca worktrees

<slug> rules: kebab-case, 3-40 chars, start with a letter.
Examples: auth-refactor, fix-login-bug, auth-refactor-1.
EOF
}

validate_slug() {
  local slug="$1"
  local len=${#slug}
  if [ "$len" -lt 3 ] || [ "$len" -gt 40 ] || ! [[ "$slug" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]; then
    echo "Error: invalid slug '$slug'. Must be kebab-case, 3-40 chars, start with a letter. Examples: auth-refactor, fix-login-bug, auth-refactor-1" >&2
    exit 2
  fi
}

cmd="${1:-}"

case "$cmd" in
  create)
    id="${2:?create requires a <slug>}"
    validate_slug "$id"
    dir="${ORCA_DIR}/${id}"
    branch="orca-${id}"
    mkdir -p "$(dirname "$dir")"
    git worktree add "$dir" -b "$branch"
    echo "$dir"
    ;;

  remove)
    id="${2:?remove requires a <slug>}"
    validate_slug "$id"
    dir="${ORCA_DIR}/${id}"
    branch="orca-${id}"
    git worktree remove "$dir" --force 2>/dev/null || true
    git branch -D "$branch" 2>/dev/null || true
    echo "Removed $dir"
    ;;

  list)
    if ! git worktree list | grep -q "\.orca/worktree"; then
      echo "No orca worktrees"
    else
      git worktree list | grep "\.orca/worktree"
    fi
    ;;

  clean)
    worktrees="$(git worktree list --porcelain | { grep "^worktree.*\.orca/worktree" || true; } | sed 's/^worktree //')"
    count=0
    while IFS= read -r wt_path; do
      [ -z "$wt_path" ] && continue
      git worktree remove --force "$wt_path" 2>/dev/null || true
      git branch -D "orca-$(basename "$wt_path")" 2>/dev/null || true
      count=$((count + 1))
    done <<< "$worktrees"
    echo "Cleaned ${count} worktree(s)"
    ;;

  "")
    usage
    exit 0
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
