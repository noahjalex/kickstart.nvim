# Native Markdown preview

[Image below the fold after scrolling the native preview](../../doc/images/native-markdown-image-scroll.jpg)

A local, read-only macOS app using AppKit, `NSTextView`/TextKit 1, and Apple's
[`swift-markdown`](https://github.com/swiftlang/swift-markdown). No web view,
HTML rendering, JavaScript, HTTP server, syntax highlighter, or diagram engine.

## Build and install

Requirements: macOS 13+, Xcode or Command Line Tools with Swift 5.9+, Git, and
this repository's Neovim configuration (Neovim 0.11+ with the `markdown` and
`markdown_inline` Tree-sitter parsers). Tested with Neovim 0.12.3. Python 3.9+
is needed only for integration tests.

From the Neovim repository root:

```sh
./native/markdown-preview/build.sh
```

This fetches the revisions in `Package.resolved`, builds a release executable,
and installs an ad-hoc-signed `native/markdown-preview/Markdown Preview.app`
**inside this checkout**. No global installation or background service is needed.
The package pins swift-markdown 0.6.0 and locks its transitive swift-cmark revision.
Keep `Package.resolved` checked in; normal builds disable automatic resolution.
The first build needs network access. Subsequent builds reuse SwiftPM's cache.
Build output and the app bundle are ignored by Git. Delete them to uninstall.

The script honors a valid `DEVELOPER_DIR`, then uses `xcode-select -p`, with a
fallback to `/Applications/Xcode.app/Contents/Developer` if the selected Xcode
was removed. To choose a toolchain explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./native/markdown-preview/build.sh
```

Restart Neovim after updating this configuration. Open a saved Markdown file and
press **`<leader>rm`** (space, r, m with this configuration). The flow is:

```
<leader>rm → custom.markdown-preview.start_markdown_preview()
            → validate saved path → markdown_preview_root()
            → launch/reuse native app → send current buffer snapshot
```

The launcher resolves its own Lua file's symlinks, so individually stowed config
files still locate the app in the checkout. The LivePreview plugin is configured
at startup and remains available through its explicit command, but its HTTP server
is not started by this mapping. No working-directory change is made.

## Configuration

At launch, the preview captures Neovim's resolved highlight colors and `background`
setting, rather than following macOS's theme. The window, headings, links, code,
quotes, table borders, and selection use that palette (including linked highlight
groups). Transparent `Normal` backgrounds fall back to a light/dark canvas.
Close and reopen the preview to pick up a changed colorscheme.

The article is centered in a maximum 680-point reading column, with responsive
side gutters (at least 24 points) and 48-point top/bottom breathing room. Body
text uses Apple's native New York serif at 18 pt with 30-point leading and
24-point paragraph gaps. SF headings use a 40/30/24/20-point hierarchy, tighter
leading, and more space above sections than below. These proportions are informed
by [Tailwind Typography's web prose styles](https://github.com/tailwindlabs/tailwindcss-typography/blob/main/src/styles.js),
not a browser or CSS dependency.

SF Mono code has padded shaded blocks and 24-point leading; quotes use an inset
border and italic text. Tables use smaller sans-serif text, subtle row separators,
alternating backgrounds, and Markdown column alignment. Images shrink to fit the
reading column when the window narrows. No fonts or dependencies need installing.
Fenced code uses the theme's foreground, not language-specific syntax highlighting.

Optional settings in `init.lua`, before using the mapping:

```lua
vim.g.markdown_preview_opacity = 0.85 -- 0–1 background alpha; default 0.96
-- Only needed to move the built app elsewhere:
vim.g.markdown_preview_executable = '/absolute/path/Markdown Preview.app/Contents/MacOS/MarkdownPreview'
```

The app's **View → Background 65% / 85% / 100%** changes opacity for its remaining
lifetime, overriding the editor setting. Text and links retain alpha 1. The
window's `alphaValue` is always 1; only `backgroundColor` has adjustable alpha.
There is no blur/material layer. Very low opacity naturally reduces contrast.

## Documents, links, and lifetime

- One preview window and process **per Neovim instance**. Repeating the mapping
  switches that window to the selected buffer. Independent editor instances have
  independent previews and lifetimes; there is no global daemon.
- The initial snapshot comes from the buffer, not disk. Further edits (including
  insert-mode changes, undo, API changes, and reloads) send complete snapshots
  after an 80 ms debounce, without saving. Writes are asynchronous and coalesce
  under socket backpressure. The app never writes source files.
- The existing `markdown_preview_root()` infers the common directory containing
  the source and its initial local link/image destinations. This can intentionally
  be a parent directory, even `/` for widely separated links. It is a convenience
  boundary, not a sandbox against a malicious Markdown author choosing the initial
  root. It stays fixed for subsequent edits and link navigation. Explicitly
  pressing the mapping again infers a fresh root from that buffer.
- The source, inferred root, local links, and images are canonicalized after
  symlink resolution. A component-wise boundary check rejects sibling-prefix
  paths, `..` escapes, and symlinks whose targets lie outside that root. A symlink
  does not widen the root. Missing/unreadable paths are rejected too. These are
  filesystem checks, not protection against another process racing filesystem
  mutations.
- Relative links/images resolve against the displayed source file's directory,
  **not** the root or editor working directory. Percent-encoded paths and local
  absolute/file URLs work inside the boundary. Markdown links (`.md`, `.markdown`,
  `.mdown`, `.mkd`) navigate in the same window. Already-previewed buffers use
  their latest unsaved snapshots; other Markdown files load as UTF-8 from disk.
  Subsequent edits to a different document update its cached snapshot without
  stealing the displayed document. Press the mapping to return explicitly.
- HTTPS links open in the default browser **only when clicked**. Other external
  schemes, network file URLs, and non-Markdown local links are rejected with a
  native alert. Fragment navigation uses a best-effort case-insensitive heading
  text search; duplicate/generated heading IDs are not fully implemented.
- Images are local native `NSImage` attachments, scaled to at most 640×480, with
  a 20 MiB encoded-file limit. Remote, rejected, missing, or unsupported images
  show their alt text and source instead of disappearing. No remote image fetches.
- Headings, paragraphs, nested emphasis, links, nested/task/ordered lists,
  blockquotes, plain fenced code, and wrapping native `NSTextTable` tables render
  as attributed text. Unhandled markup stays readable; literal HTML stays literal
  text, and diagram fences stay plain code. No syntax colors or diagram output.
  Exact GitHub layout is not reproduced. The native
  document view grows with text and image layout so images below the first screen
  can be reached using the scrollbar.
- Closing the preview exits its process. Further edits do not reopen it; press
  the mapping to reopen. Closing/disconnecting Neovim closes the socket and exits
  the app. Unsaved edits remain Neovim's responsibility, unchanged by the app.
  A normal exit removes the socket directory; forcibly killing Neovim can leave
  an inert `/tmp/nvim-markdown-*` directory, but no helper process.

## IPC

Neovim listens on `editor.sock` inside a fresh mode-0700 directory under `/tmp`.
It launches the app directly as a managed child, passing `--socket PATH`. The app
connects once; Neovim closes the listener after accepting it. There is no shell,
HTTP/TCP port, polling helper, or browser involved. A 10-second startup timeout
cleans up a failed launch. Frames are newline-delimited UTF-8 JSON, limited to
16 MiB each:

```json
{"source":"/absolute/doc.md","root":"/absolute","text":"# Unsaved text","opacity":0.96,"activate":true}
```

Snapshots from Neovim also include `theme`, an object with `dark` (boolean) and
`colors` (role-to-`#rrggbb` map). Roles are `background`, `foreground`, `heading1`
through `heading6`, `link`, `code`, `codeBackground`, `quote`, `border`, and
`selection`. The launch theme is retained through edits and local link navigation.
Omitting `theme` preserves native system-color defaults for standalone IPC clients.

`activate` selects/focuses a document for an explicit preview request. Live edits
use `false` and do not focus the window. Replies report the source, root, byte
count, process/window IDs, and errors. Neovim emits `User MarkdownPreviewUpdated`
with each successful reply as `event.data`. `MARKDOWN_PREVIEW_INSPECT=1` also
includes the actual displayed text/window alpha in replies, for tests only.
Malformed frames receive an error; oversized/incomplete frames at EOF disconnect.
EOF terminates the app. Snapshots are cached in memory until the app exits.

Full parsing/rendering and snapshot caching are deliberate small-document
tradeoffs. Large documents may lag and cached documents consume memory; there
is no incremental renderer or unbounded history of revisions.

## Automated verification

Run in a logged-in macOS GUI session (the integration tests open native windows):

```sh
cd native/markdown-preview
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer # adjust for your installation
./build.sh
swift test --disable-automatic-resolution
python3 Tests/verify.py
```

`swift test` checks representative output and font/paragraph attributes, performs
actual native text layout, loads an image, and tests canonical path boundaries.
`verify.py` launches the real release app and uses real Unix sockets: fragmented
UTF-8, coalesced/malformed frames, rendering, source validation, symlink rejection,
`/tmp` versus `/private/tmp` document identity, window reuse, opacity, a real
PNG image below the fold in a scrollable document view, process termination, and
EOF cleanup. It also starts **the real `init.lua`**, executes the
actual buffer-local mapping, checks initial unsaved contents and subsequent live
edits, switches buffers, and verifies that exiting Neovim leaves no app/socket.
It does not replace the app or IPC with mocks. It finishes with five measured
fresh-process launches and idle RSS samples. Existing config/plugins must already
be installed; the test is not a plugin bootstrapper.

## Manual end-to-end check

Use a disposable document so closing the test editor cannot discard real work:

```sh
work=$(mktemp -d /tmp/native-markdown-check.XXXXXX)
cp native/markdown-preview/Tests/representative.md "$work/first.md"
printf '# Second document\n\n[Back](first.md)\n\n[Rejected](escape.md)\n\n[External](https://example.com)\n' > "$work/second.md"
outside=$(mktemp -d /tmp/native-markdown-outside.XXXXXX)
printf '# Must not be displayed\n' > "$outside/secret.md"
ln -s "$outside/secret.md" "$work/escape.md"
sips -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns --out "$work/local.png"
printf '\n\n![Local image](local.png)\n' >> "$work/first.md"
nvim "$work/first.md"
```

1. Insert text without saving, then press `<leader>rm`. Verify the native preview
   contains it and no browser window/tab opens. Inspect headings, nested lists,
   code, tables, literal unsupported markup, and the local image.
2. Edit again in insert mode without saving. Check that the existing preview
   updates and does not take keyboard focus. Undo and check again.
3. Click **Next document**, then **Back**. Check that Back shows the unsaved buffer
   snapshot. Edit again after navigating back and verify the live update.
4. On the second document, click **Rejected**. Expect an outside-root alert and
   no secret text. Dismiss it. Click **External**; only this action should open
   the default browser to `https://example.com`.
5. In Neovim, `:set hidden`, `:edit <the second.md path>`, then `<leader>rm`.
   Check it switches the same window. Return to the first buffer and repeat.
6. Choose **View → Background 65%**. Put the window over another window or wallpaper.
   Check the background is translucent while the text remains solid; edit again
   and confirm the chosen opacity persists.
7. Close the preview using its close button. Verify Neovim still edits normally
   and does not reopen it on typing. Press the mapping to reopen, then exit the
   disposable editor with `:qa!`; confirm the preview also exits.
8. In another editor, try an unnamed Markdown buffer and a named nonexistent `.md`
   file. Both must warn without launching anything.

Remove the disposable directories after exiting: `rm -rf "$work" "$outside"`.

### Verification recorded on 2026-11-03

- Release build and two XCTest cases passed; real native IPC and real-Neovim
  integration checks passed, including the path-identity regression and EOF exit.
- GUI check through Ghostty and macOS accessibility: entered the real mapping
  with unsaved edits; observed a native window without a browser; inspected
  headings, lists, plain code, readable tables, unsupported markup, and a local
  PNG attachment; clicked Next and Back, verified cached unsaved contents and
  **live updates after navigation** on the final build; opened a second buffer
  into the same window; clicked a symlink outside the inferred root and observed
  a rejection alert; clicked External HTTPS and observed the default browser
  (Chrome) open only then; set View → Background 65% and visually confirmed
  solid text over a translucent background; closed the app, kept editing, reopened
  explicitly, and exited Neovim with no orphaned preview.
- The first GUI pass found a `/private/tmp` versus `/tmp` identity bug. It was
  fixed, covered with real IPC, and rechecked in the final GUI pass.
- A later screenshot of multiple local images found that the text view had been
  capped at viewport height: images below the first screen were unreachable.
  The text view now sizes to its laid-out content (and reflows on window resize).
  The actual-IPC test asserts that a local PNG attachment is present **and** its
  document view is taller than the viewport; a GUI scroll to the bottom showed
  the image. The screenshot above is cropped to the preview content.

### Measurements

Apple M2 Max, arm64 release build, macOS 27.0.1 (26A434), Swift 6.4.2,
Neovim 0.12.3. Five fresh app processes; 823-byte `Tests/representative.md`.
Time runs from process launch to first acknowledgement **after rendering into
NSTextView**, not to the first display-server-presented frame. The filesystem and
OS caches were warm; these are process-cold starts, not reboot-cold measurements.
RSS is sampled using `ps -o rss=` two seconds after rendering, including the
inspection/test path, without forcing GC/cache eviction.

| Sample | Launch → rendered acknowledgement | Idle RSS |
| --- | ---: | ---: |
| 1 | 156.2 ms | 118.2 MiB |
| 2 | 178.8 ms | 118.3 MiB |
| 3 | 186.0 ms | 118.1 MiB |
| 4 | 180.4 ms | 118.2 MiB |
| 5 | 181.8 ms | 118.4 MiB |
| Median | **180.4 ms** | **118.2 MiB** |

No browser/Electron baseline was measured. These numbers establish no comparative
performance advantage. Re-run `python3 Tests/verify.py` to measure your machine.
