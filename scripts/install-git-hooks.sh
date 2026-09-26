#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
git -C "$repo_root" config --local core.hooksPath .githooks
printf 'Azalea Git hooks enabled for this repository and its worktrees.\n'
