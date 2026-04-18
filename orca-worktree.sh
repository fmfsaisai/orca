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
  create <id>   Create worktree at $ORCA_DIR/<id> on branch orca-<id>
  remove <id>   Remove worktree and delete branch orca-<id>
  list          List active orca worktrees
  clean         Remove all orca worktrees
EOF
}

cmd="${1:-}"

case "$cmd" in
  create)
    id="${2:?create requires an <id>}"
    dir="${ORCA_DIR}/${id}"
    branch="orca-${id}"
    mkdir -p "$(dirname "$dir")"
    git worktree add "$dir" -b "$branch"
    echo "$dir"
    ;;

  remove)
    id="${2:?remove requires an <id>}"
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
