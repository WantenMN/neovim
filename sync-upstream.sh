#!/usr/bin/env bash
# Sync release_fork with upstream master.
# It NEVER pushes: review the result, then push manually.
#
# Remote layout in this clone:
#   origin   = upstream (neovim/neovim)
#   fork     = WantenMN/neovim (push target)
#   upstream = neovim/neovim (added by this script if missing)
# If your clone uses origin = fork instead, the script still works;
# just push to origin (see final hint).
#
# Usage: ./sync-upstream.sh
set -euo pipefail

UPSTREAM_URL="https://github.com/neovim/neovim.git"
BRANCH="release_fork"

die() { echo "sync-upstream: $*" >&2; exit 1; }

# --- 0. sanity ---------------------------------------------------------------
[[ "$(git branch --show-current)" == "$BRANCH" ]] || die "not on $BRANCH, abort"
[[ -z "$(git status --porcelain)" ]] || die "worktree dirty, commit or stash first"

# --- 1. upstream -------------------------------------------------------------
git remote get-url upstream >/dev/null 2>&1 \
  || { echo "adding upstream remote"; git remote add upstream "$UPSTREAM_URL"; }
git fetch upstream

if git merge-base --is-ancestor upstream/master HEAD; then
  echo "already up to date with upstream/master"
else
  echo "== new upstream commits =="
  git log --oneline "HEAD..upstream/master"
fi

# --- 2. rebase ----------------------------------------------------------------
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse upstream/master)" ]]; then
  echo "== rebasing $BRANCH onto upstream/master =="
  if ! git rebase upstream/master; then
    echo "conflict during rebase, aborting (your branch is untouched)" >&2
    git rebase --abort
    exit 1
  fi
else
  echo "branch already on upstream/master tip, no rebase needed"
fi

# --- 3. version check ----------------------------------------------------------
echo
echo "== version check (CMakeLists.txt vs flake.nix) =="
grep -n "NVIM_VERSION_" CMakeLists.txt | head -n 5
grep -n "version = " flake.nix | head -n 5
echo "(if upstream bumped NVIM_VERSION_*, update flake.nix version accordingly; see FORK.md §2)"

# --- 4. summary -----------------------------------------------------------------
echo
echo "== result =="
git log --oneline -3
git status --short
echo
echo "next (manual): review, then push:"
if git remote get-url fork >/dev/null 2>&1; then
  echo "  git push --force-with-lease fork $BRANCH"
else
  echo "  git push --force-with-lease origin $BRANCH"
fi
echo "then in dotfiles/nixos: nix flake update neovim && rebuild"
