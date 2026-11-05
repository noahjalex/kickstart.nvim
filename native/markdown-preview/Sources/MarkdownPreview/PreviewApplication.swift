import AppKit
import Darwin
import PreviewCore

/// One read-only preview window. The Neovim socket owns its lifetime; no document is ever written.
final class PreviewApplication: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var connection: Int32 = -1
    private var current: PreviewSnapshot?
    private var chosenOpacity: Double?
    private var snapshots: [String: PreviewSnapshot] = [:]
    private let replyQueue = DispatchQueue(label: "local.dotfiles.MarkdownPreview.replies")
    private let socketPath: String
    private var style = PreviewStyle()
    private let inspect = ProcessInfo.processInfo.environment["MARKDOWN_PREVIEW_INSPECT"] == "1"

    init(socketPath: String) { self.socketPath = socketPath }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let config = ProcessInfo.processInfo.environment["MARKDOWN_PREVIEW_CONFIG"]
            ?? ((ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? NSHomeDirectory() + "/.config") + "/nvim/markdown-preview.json")
        if FileManager.default.fileExists(atPath: config) {
            do { style = try PreviewStyle.load(from: URL(fileURLWithPath: config)) }
            catch {
                let alert = NSAlert()
                alert.messageText = "Markdown preview: invalid style configuration"
                alert.informativeText = "\(config)\n\(error.localizedDescription)\nUsing default styles."
                alert.runModal()
            }
        }
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Markdown Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: ""); menu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        for (title, percent) in [("Background 65%", 65), ("Background 85%", 85), ("Background 100%", 100)] {
            let item = viewMenu.addItem(withTitle: title, action: #selector(changeOpacity(_:)), keyEquivalent: "")
            item.target = self; item.tag = percent
        }
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 360, height: 300)
        window.title = "Markdown Preview"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.alphaValue = 1
        window.titlebarAppearsTransparent = true
        window.center()
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        // Explicit TextKit 1 stack supports native NSTextTable layout.
        let storage = NSTextStorage()
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        textView = NSTextView(frame: scroll.bounds, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 48, height: 48)
        textView.delegate = self
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor.withAlphaComponent(1),
                                       .underlineStyle: NSUnderlineStyle.single.rawValue]
        scroll.documentView = textView
        window.contentView!.addSubview(scroll)

        DispatchQueue.global(qos: .userInitiated).async { self.readSnapshots() }
    }

    private func layoutArticle() {
        guard let textView, let scroll = textView.enclosingScrollView else { return }
        let width = scroll.contentSize.width
        // A web-style reading measure, centered on wide windows with mobile-sized gutters on narrow ones.
        let gutter = max(24, (width - style.readingWidth) / 2)
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        textView.textContainerInset = NSSize(width: gutter, height: 48)
        let imageWidth = max(1, min(640, width - 2 * gutter))
        let storage = textView.textStorage!
        storage.beginEditing()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment, let image = attachment.image else { return }
            let scale = min(1, imageWidth / image.size.width, 480 / image.size.height)
            attachment.bounds = NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        }
        storage.endEditing()
        textView.layoutManager!.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        textView.sizeToFit() // Grow vertically, never stretch the article's reading width.
    }

    @objc private func changeOpacity(_ sender: NSMenuItem) {
        chosenOpacity = Double(sender.tag) / 100
        let theme = current?.theme ?? PreviewTheme()
        window.backgroundColor = theme.color("background", fallback: .windowBackgroundColor).withAlphaComponent(CGFloat(chosenOpacity!))
    }

    private func displaySnapshot(_ snapshot: PreviewSnapshot) throws {
        let paths = try PreviewPaths(source: snapshot.source, root: snapshot.root)
        let scrollOrigin = textView.enclosingScrollView!.contentView.bounds.origin
        let sameFile = current?.source == snapshot.source
        let theme = snapshot.theme ?? PreviewTheme()
        if let launchTheme = snapshot.theme {
            window.appearance = NSAppearance(named: launchTheme.dark ? .darkAqua : .aqua)
        }
        textView.linkTextAttributes = [.foregroundColor: theme.color("link", fallback: .linkColor),
                                       .underlineStyle: NSUnderlineStyle.single.rawValue]
        textView.selectedTextAttributes = [.backgroundColor: theme.color("selection", fallback: .selectedTextBackgroundColor),
                                           .foregroundColor: theme.color("foreground", fallback: .textColor)]
        textView.textStorage!.setAttributedString(MarkdownRenderer(paths: paths, theme: theme, style: style, highlights: snapshot.highlights ?? []).render(snapshot.text))
        layoutArticle()
        current = snapshot
        window.title = paths.source.lastPathComponent + " — Markdown Preview"
        window.representedURL = paths.source
        window.backgroundColor = theme.color("background", fallback: .windowBackgroundColor).withAlphaComponent(CGFloat(min(1, max(0, chosenOpacity ?? snapshot.opacity))))
        if sameFile {
            textView.enclosingScrollView!.contentView.scroll(to: scrollOrigin)
        } else {
            textView.scrollToBeginningOfDocument(nil)
        }
        if snapshot.activate || !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let snapshot = current else { return true }
        let destination = (link as? String) ?? (link as? URL)?.absoluteString ?? ""
        do {
            if let url = URL(string: destination), url.scheme?.lowercased() == "https", url.host != nil {
                NSWorkspace.shared.open(url)
                return true
            }
            let paths = try PreviewPaths(source: snapshot.source, root: snapshot.root)
            let target = try paths.localResource(destination)
            guard ["md", "markdown", "mdown", "mkd"].contains(target.pathExtension.lowercased()) else {
                throw PreviewError.rejected("local links must point to Markdown files")
            }
            let cached = snapshots[target.path]
            let text = try cached?.text ?? String(contentsOf: target, encoding: .utf8)
            let next = PreviewSnapshot(source: target.path, root: snapshot.root, text: text, opacity: snapshot.opacity, theme: snapshot.theme, highlights: cached?.highlights)
            try displaySnapshot(next)
            if cached == nil {
                // Let the owning editor supply its installed parsers for a newly navigated document too.
                sendReply(["highlightRequest": true, "source": target.path, "root": snapshot.root, "text": text, "opacity": snapshot.opacity])
            }
            // Fragment-only links remain in this document. Native text stays readable if no heading matches.
            if let fragment = URLComponents(string: destination)?.fragment {
                let words = fragment.replacingOccurrences(of: "-", with: " ")
                let range = (textView.string as NSString).range(of: words, options: .caseInsensitive)
                if range.location != NSNotFound { textView.scrollRangeToVisible(range) }
            }
        } catch { showPreviewError(error) }
        return true // Never let NSTextView open unvalidated file URLs itself.
    }

    private func showPreviewError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Markdown preview"
        alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }

    private func receiveSnapshot(_ data: Data) {
        do {
            let snapshot = try JSONDecoder().decode(PreviewSnapshot.self, from: data)
            let paths = try PreviewPaths(source: snapshot.source, root: snapshot.root)
            // Foundation and libuv may spell the same file as /tmp/... and /private/tmp/....
            let normalized = PreviewSnapshot(source: paths.source.path, root: paths.root.path, text: snapshot.text,
                                             opacity: snapshot.opacity, activate: snapshot.activate, theme: snapshot.theme, highlights: snapshot.highlights)
            snapshots[paths.source.path] = normalized
            if snapshot.activate || current?.source == normalized.source { try displaySnapshot(normalized) }
            var reply: [String: Any] = ["source": snapshot.source, "root": snapshot.root, "bytes": snapshot.text.utf8.count,
                                        "pid": getpid(), "window": window.windowNumber, "opacity": snapshot.opacity]
            if inspect {
                reply["rendered"] = textView.string
                reply["syntaxSpans"] = current?.highlights?.reduce(0) { $0 + $1.spans.count } ?? 0
                reply["bodyFont"] = style.body?.family
                reply["readingWidth"] = style.readingWidth
                let background = window.backgroundColor.usingColorSpace(.sRGB)!
                reply["backgroundRGB"] = [background.redComponent, background.greenComponent, background.blueComponent]
                reply["darkAppearance"] = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                reply["theme"] = current?.theme?.colors
                reply["windowAlpha"] = window.alphaValue
                reply["backgroundAlpha"] = window.backgroundColor.alphaComponent
                reply["windows"] = NSApp.windows.filter { $0.isVisible && $0 === window }.count
                reply["articleWidth"] = textView.textContainer!.containerSize.width
                reply["articleGutter"] = textView.textContainerInset.width
                reply["viewportWidth"] = textView.enclosingScrollView!.contentView.bounds.width
                reply["contentHeight"] = textView.frame.height
                reply["viewportHeight"] = textView.enclosingScrollView!.contentView.bounds.height
                reply["attachments"] = textView.textStorage!.string.filter { $0 == "\u{fffc}" }.count
            }
            sendReply(reply)
        } catch { sendReply(["error": error.localizedDescription]) }
    }

    private func sendReply(_ reply: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: reply) else { return }
        // Replies are diagnostic only; a slow or gone editor must never block the UI thread.
        let frame = data + Data([10])
        replyQueue.async {
            frame.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(self.connection, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if written <= 0 { break }
                    offset += written
                }
            }
        }
    }

    private func readSnapshots() {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { terminatePreview(); return }
        connection = fd
        defer { close(fd) }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        // Bound diagnostic writes even if a connected peer stops reading.
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { terminatePreview(); return }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: path.map { UInt8(bitPattern: $0) }) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { terminatePreview(); return }
        var pending = Data()
        var bytes = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { break }
            pending.append(contentsOf: bytes.prefix(count))
            while let newline = pending.firstIndex(of: 10) {
                guard newline - pending.startIndex < 16 * 1024 * 1024 else { terminatePreview(); return }
                let frame = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                DispatchQueue.main.sync { self.receiveSnapshot(frame) }
            }
            guard pending.count <= 16 * 1024 * 1024 else { break }
        }
        terminatePreview()
    }

    private func terminatePreview() { DispatchQueue.main.async { NSApp.terminate(nil) } }
    func windowDidResize(_ notification: Notification) { layoutArticle() }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        if connection >= 0 { shutdown(connection, SHUT_RDWR) }
    }
}

let arguments = CommandLine.arguments
if arguments.count != 3 || arguments[1] != "--socket" {
    fputs("Usage: MarkdownPreview --socket /private/path/to/editor.sock\n", stderr)
    exit(2)
}
let application = NSApplication.shared
let delegate = PreviewApplication(socketPath: arguments[2])
application.delegate = delegate
application.run()
