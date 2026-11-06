# Handoff: Finish MermaidKit floating diagram preview

**Scope:** Keep MermaidKit as the selected native Markdown renderer and implement the user's revised diagram interaction. Stop developing the swift-mermaid alternative; do not delete its worktree or unrelated user files.
**Status:** Both prototypes build, but latest requested behavior is NOT implemented. User explicitly requested a fresh session to resolve it accurately. No background agents remain active.

## Latest user request (authoritative)

“Let's just keep MermaidKit as the way to go.

The floating window should be:
* floating, not a full window
* clicking outside of the window closes it
* scrolling with the mouse scrolls in, panning is click and drag
* esc or clicking outside closes it,

The mermaid diagram in the mardkwon doc should be centered and clearly bounded (perahps with rounded corners if possible. Also Im seeing both the displaying image and the mermaid code below it.

START A FRESH SESSION TO RESOLVE THESE ACCURATELY.”

Interpret mouse scrolling as zooming in/out (instead of moving the viewport); panning is click-drag. Successful diagrams should not display duplicate source by default. Preserve access to exact copyable Mermaid source via an explicit Copy Source control or equivalent; source-only fallback for invalid/guarded diagrams remains readable. Ordinary fenced code must still be selectable/copyable. Choose simple native AppKit mechanisms, not a new framework.

## Branches & worktrees

- Main checkout: `/Users/nalexander/dotfiles/nvim/.config/nvim`, branch `master`, HEAD `55b5347`. Current package cwd: `native/markdown-preview`.
- Selected prototype: `/Users/nalexander/.pi/agent/worktrees/nvim-mermaidkit`, branch `preview/mermaidkit`, HEAD `55b5347`; created directly from that main HEAD. All implementation lives in UNCOMMITTED and partly UNTRACKED changes, so git merge/cherry-pick alone will NOT transfer it.
- Rejected alternative: `/Users/nalexander/.pi/agent/worktrees/nvim-swift-mermaid`, branch `preview/swift-mermaid`. Preserve but do not continue developing.
- No commits/pushes/PRs were created in this task; no remote status queried. Parent/upstream beyond the known creation HEAD is unverified.

## Local uncommitted state

Main has three pre-existing changes which must be preserved: `native/markdown-preview/Sources/MarkdownPreview/PreviewApplication.swift` (Edit Copy/Select All menu), `Sources/PreviewCore/PreviewStyle.swift` (0.5-point inset fixes clipped table right border), and `Tests/PreviewCoreTests/MarkdownRendererTests.swift` (copy/table regressions). User also has untracked `native/markdown-preview/tester.md`; DO NOT overwrite it.

Selected MermaidKit worktree has those baseline fixes plus modified Package.swift/Package.resolved, README.md, PreviewDocument.swift, PreviewApplication.swift, tests and build.sh; new UNTRACKED DiagramViewer.swift, DiagramViewerTests.swift, MermaidRenderingTests.swift, MermaidComparisonTests.swift, Tests/mermaid-comparison.md, and test-preview.sh. Never discard, reset or omit untracked files during integration.

Baseline patch: `/Users/nalexander/.pi/agent/worktrees/markdown-mermaid-comparison-baseline.patch`. Reverse-applying it no longer cleanly checks the selected lane because later viewer menu changes touch adjacent context; baseline additions remain intact and regression-tested. Read actual changes before promoting the selected implementation into main. User's choice authorizes selecting MermaidKit, not destructive cleanup or publication.

## Current implementation anchors

All selected-lane paths below are relative to `native/markdown-preview`:
- `Sources/PreviewCore/DiagramViewer.swift` (~267 lines): DiagramAttachment holds original native image and bounded vector PDF; DiagramArticleTextView hit-tests typed diagram attachment glyphs; DiagramViewerView uses NSScrollView/PDF canvas, drag pan, native pinch, zoom/fit buttons and shortcuts; DiagramViewerController currently creates a standard resizable window. THIS needs a floating transient panel rather than a normal full window, outside-click and Escape dismissal, and wheel-to-zoom behavior.
- `Sources/PreviewCore/PreviewDocument.swift`: Mermaid CodeBlock branch inserts a diagram attachment then ALWAYS appends source below. Change successful-diagram presentation to centered, clearly bounded (rounded if feasible) image with explicit source-copy access; invalid/unsupported/guarded fallback should still show source. Preserve syntax offsets and normal images/code.
- `Sources/MarkdownPreview/PreviewApplication.swift`: uses DiagramArticleTextView; on diagram click retains/opens controller; menu zoom/fit/close selectors and app termination cleanup. Review panel focus, lifecycle, dismissal event monitors and cleanup together.
- `Tests/PreviewCoreTests/DiagramViewerTests.swift`: 3 offscreen tests for actual glyph click routing, vector PDFs for all four large fixtures, fit/zoom/pan/resize/keys/unshown lifecycle. Update previous expectations to revised UX, not merely add passing tests around old behavior.
- `Tests/PreviewCoreTests/MermaidRenderingTests.swift`: exact source copy, fallback, theme, dimensions and crash guard; previously expects always-visible source and needs deliberate updates preserving copy capability.
- `Tests/PreviewCoreTests/MermaidComparisonTests.swift`, `Tests/mermaid-comparison.md`: four larger real diagrams (branching flowchart, seven-participant sequence, state machine, wide graph). All fit existing limits. Reuse these to verify larger diagrams, not just two-node examples.
- `test-preview.sh`: one command for HUMAN testing, already executable. Opens fixture in normal nvim and schedules selecting lane-local executable. Do not run it during automated validation.

## Load-bearing constraints and decisions

- DESKTOP SAFETY: User explicitly forbids test focus-stealing/windows/desktop automation. Do not launch preview/nvim/scripts, open/order/show windows, activate apps, run app event loops, use AppleScript/CGEvent input injection, change Spaces/workspaces, or touch general pasteboard. Do not run Tests/verify.py or Tests/neovim-integration.lua. Build-only ./build.sh and offscreen XCTest (unshown windows/views, direct synthetic-event method calls, unique private pasteboards) are allowed. Production may present/dismiss a panel only on the actual user's click. Hardware/global outside-click behavior must be honestly labeled unverified if not verifiable offscreen; do not violate safety to claim success.
- MermaidKit exact 2.9.1 pin, commit `64c19fbddf5604122b01563b3ab727dbadf0ee95`; module MermaidRender. macOS 14+, Swift tools 6.2+, host Swift 5 language mode intentionally avoids an unrelated concurrency migration. Actual local compiler Swift 6.4.2.
- CRASH GUARD: any case-insensitive raw `autonumber` substring is source-only BEFORE invoking MermaidKit; pinned upstream increments arbitrary Int counters unchecked and tiny inputs can trap. Keep this conservative guard. Limits: first 8 fences/snapshot, <=2048 UTF-8 bytes and <=64 newlines per fence. Synchronous bounds are not a full hostile-input sandbox; don't claim otherwise.
- Viewer exports actual vector PDF once through MermaidRenderer.pdfData using exact eligible source/theme. Never zoom only the small preview bitmap or bypass guards for expansion. Existing metadata validates one finite PDF page <=8 MiB, <=4096 points/dimension; canvas draws original CGPDFPage without huge zoomed bitmap allocations. Preserve crisp vector zoom.
- Original PDF sizes of 4 manual diagrams are roughly 575×1458, 989×798, 840×930, 2529×270 points. Inline cap currently 640×480; larger vector viewer is essential.
- Current center/fit/keyboard behavior: Cmd+/= and Cmd-minus zoom, Cmd0 fit, Esc/CmdW close, 2.5–800% zoom; retain useful shortcuts unless conflict with revised panel design. Don't guess unrelated “key fixes”; user's new explicit list is the scope.
- Simplicity: use native AppKit panel/scroll/text mechanisms. No WebKit, JS, extra dependency, renderer-switching framework, unrelated refactor, commits or PRs unless asked.

## Evidence and artifacts

Latest selected-lane full suite: 14 tests passed, release build/ad-hoc signing succeeded, fresh independent review found no P0/P1/P2 at the OLD behavior. That does not validate the NEW request.
- Selected logs, PDF/PNG artifacts: `/Users/nalexander/.pi/agent/worktrees/nvim-mermaidkit/native/markdown-preview/.build/lane-artifacts/` (`viewer-full.log`, `viewer-release.log`, expanded-1..4.pdf/png).
- Old implementation report: `/Users/nalexander/.pi/agent/sessions/--Users-nalexander-dotfiles-nvim-.config-nvim-native-markdown-preview--/subagent-artifacts/outputs/87659dde-d552-4d07-b453-60296460b954/mermaidkit/viewer.md`.
- Old fresh review: `/Users/nalexander/.pi/agent/sessions/--Users-nalexander-dotfiles-nvim-.config-nvim-native-markdown-preview--/subagent-artifacts/outputs/a71017bc-eb51-43d0-a34d-9fa4cc8dcc95/mermaidkit/viewer-review.md`.
- Previous mission `a9021852-aa4e-4f50-aa33-8e156740000f` is completed; no live child needs managing.

## Next action

Read current selected-lane DiagramViewer.swift, its click integration, CodeBlock rendering, and tests end-to-end. Implement the latest request in that chosen lane first; verify offscreen and rebuild, then safely promote MermaidKit to the main app without losing the main baseline/user tester.md or untracked chosen-lane files. If promotion would conflict with newly changed main work, stop and ask rather than overwrite. Leave rejected worktree alone. End with truthful test evidence and one short command to launch the updated chosen app; do not describe unimplemented behavior as already available.
