#!/bin/sh
# Launch this worktree's built preview with the larger comparison document.
set -eu
package=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export MARKDOWN_PREVIEW_TEST_EXECUTABLE="$package/Markdown Preview.app/Contents/MacOS/MarkdownPreview"
if [ ! -x "$MARKDOWN_PREVIEW_TEST_EXECUTABLE" ]; then
  printf '%s\n' 'Markdown preview test: run ./build.sh in this worktree first.' >&2
  exit 1
fi
exec nvim "${1:-$package/Tests/mermaid-comparison.md}" -c 'lua vim.schedule(function() vim.g.markdown_preview_executable = vim.env.MARKDOWN_PREVIEW_TEST_EXECUTABLE; require("custom.markdown-preview").start_markdown_preview() end)'
