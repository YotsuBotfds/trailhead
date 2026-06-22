#!/usr/bin/env bash
# worktree-gc.sh — prune git worktrees + branches fully merged into the base branch.
#
# SAFE BY CONSTRUCTION:
#   * `git worktree remove` (no --force) refuses any worktree with uncommitted
#     changes  -> dirty worktrees are SKIPPED and surfaced, never destroyed.
#   * `git branch -d` (lowercase) refuses any branch not merged into the base
#     -> unmerged work is NEVER deleted.
# Merged work is preserved in the base branch's history, so removals are
# recoverable (re-create the worktree/branch from the commit in main).
#
# Usage:  bash tools/worktree-gc.sh [base-branch]   (default: main)
#         bash tools/worktree-gc.sh --dry-run [base-branch]
set -uo pipefail

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
cd "$(git rev-parse --show-toplevel)" || exit 1
MAIN="${1:-main}"

LABEL=""; [ "$DRY" = 1 ] && LABEL=", DRY-RUN"
echo "== worktree-gc (base=$MAIN$LABEL)  $(git rev-parse --short "$MAIN") =="
merged="$(git branch --merged "$MAIN" | sed 's/^[ *+]*//' | grep -vxF "$MAIN")"

removed=0; skipped=0; delbr=0

# 1. Remove worktrees whose branch is fully merged (skip the main worktree).
while IFS=$'\t' read -r br wt; do
	[ -z "$br" ] && continue
	[ "$br" = "$MAIN" ] && continue
	if echo "$merged" | grep -qxF "$br"; then
		if [ "$DRY" = 1 ]; then
			echo "would remove worktree: $wt ($br)"; removed=$((removed + 1)); continue
		fi
		if git worktree remove "$wt" 2>/dev/null; then
			echo "removed worktree:  $wt ($br)"; removed=$((removed + 1))
		else
			# Dirty. If the ONLY dirt is regenerable .import / .godot cache, force it;
			# otherwise preserve (real uncommitted work) and surface it.
			realdirt="$(git -C "$wt" status --porcelain 2>/dev/null | awk '{p=substr($0,4)} p !~ /\.import$/ && p !~ /(^|\/)\.godot\// {print}')"
			if [ -z "$realdirt" ] && git worktree remove --force "$wt" 2>/dev/null; then
				echo "removed worktree:  $wt ($br)  [forced: import-cache cruft only]"; removed=$((removed + 1))
			else
				echo "SKIPPED (real uncommitted work): $wt ($br)"; skipped=$((skipped + 1))
				git -C "$wt" status --porcelain 2>/dev/null | awk '{p=substr($0,4)} p !~ /\.import$/ && p !~ /(^|\/)\.godot\// {print "      " $0}'
			fi
		fi
	fi
done < <(git worktree list --porcelain | awk '/^worktree /{wt=$2} /^branch /{gsub("refs/heads/","",$2); print $2"\t"wt}')

# 2. Prune orphaned worktree admin entries (directories already deleted).
[ "$DRY" = 1 ] || git worktree prune -v

# 3. Delete merged branches (safe -d refuses unmerged / currently-checked-out).
while IFS= read -r br; do
	[ -z "$br" ] && continue
	if [ "$DRY" = 1 ]; then
		echo "would delete branch: $br"; delbr=$((delbr + 1)); continue
	fi
	if git branch -d "$br" >/dev/null 2>&1; then
		echo "deleted branch:    $br"; delbr=$((delbr + 1))
	fi
done <<< "$merged"

echo "== done: $removed worktrees, $skipped skipped(dirty), $delbr branches =="
echo "-- unmerged branches kept (decide keep/merge/abandon) --"
git branch --no-merged "$MAIN" | sed 's/^[ *+]*//'
echo "-- worktrees remaining --"
git worktree list
