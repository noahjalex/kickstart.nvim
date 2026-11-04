#!/bin/sh
# Install and test only in a disposable copy, never the live Neovim directories.
set -eu
repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d /tmp/kickstart-vim-pack.XXXXXX)
export XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data"
export XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache" NVIM_APPNAME=nvim
unset VIMINIT EXINIT
mkdir -p "$XDG_CONFIG_HOME/nvim" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
rsync -a --exclude=.git --exclude=.handoffs --exclude=.build --exclude='*.app' "$repository/" "$XDG_CONFIG_HOME/nvim/"
printf 'Isolated test directories (retained for inspection): %s\n' "$root"
# As with upstream, a C compiler, make, and tree-sitter CLI must be on PATH.
command -v tree-sitter >/dev/null
"${NVIM:-nvim}" --headless \
  --cmd "lua _G.migration_errors = {}; local notify = vim.notify; vim.notify = function(m, l, o) if l == vim.log.levels.ERROR then table.insert(_G.migration_errors, m) end; return notify(m, l, o) end; local add = vim.pack.add; vim.pack.add = function(s, o) return add(s, vim.tbl_extend('force', o or {}, { confirm = false })) end" \
  -u "$XDG_CONFIG_HOME/nvim/init.lua" -l "$XDG_CONFIG_HOME/nvim/tests/migration-smoke.lua"
