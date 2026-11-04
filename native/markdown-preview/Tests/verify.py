#!/usr/bin/env python3
"""Exercise the real AppKit process over Unix sockets and the real Neovim mapping."""
import json
import os
from pathlib import Path
import socket
import statistics
import struct
import subprocess
import tempfile
import time
import zlib

PACKAGE = Path(__file__).resolve().parents[1]
REPOSITORY = PACKAGE.parents[1]
EXECUTABLE = PACKAGE / "Markdown Preview.app/Contents/MacOS/MarkdownPreview"
ENVIRONMENT = dict(os.environ, MARKDOWN_PREVIEW_INSPECT="1")


class NativePreview:
    def __init__(self, directory):
        self.socket_path = directory / "test.sock"
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(self.socket_path))
        self.listener.listen(1)
        self.listener.settimeout(10)
        self.started = time.perf_counter()
        self.process = subprocess.Popen([str(EXECUTABLE), "--socket", str(self.socket_path)], env=ENVIRONMENT)
        self.connection, _ = self.listener.accept()
        self.connection.settimeout(10)
        self.reader = self.connection.makefile("rb")

    def receive(self):
        line = self.reader.readline(32 * 1024 * 1024)
        assert line, "native app closed IPC unexpectedly"
        return json.loads(line)

    def update(self, snapshot):
        self.connection.sendall(json.dumps(snapshot).encode() + b"\n")
        return self.receive()

    def disconnect(self):
        self.reader.close()
        self.connection.close()
        self.listener.close()
        self.process.wait(timeout=5)
        assert self.process.returncode == 0, self.process.returncode
        self.socket_path.unlink()


def snapshot(directory, text):
    return dict(source=str(directory / "first.md"), root=str(directory), text=text,
                opacity=0.65, activate=True)


def verify_native_ipc(directory):
    app = NativePreview(directory)
    try:
        initial = snapshot(directory, "# Initial unsaved 日本語\n\n**Native text**")
        frame = json.dumps(initial, ensure_ascii=False).encode() + b"\n"
        # Split in the middle of multibyte UTF-8, not merely on JSON boundaries.
        split = frame.index("日本語".encode()) + 1
        app.connection.sendall(frame[:split])
        app.connection.sendall(frame[split:])
        first = app.receive()
        assert first["rendered"] == "Initial unsaved 日本語\nNative text\n", first
        assert first["windows"] == 1 and first["windowAlpha"] == 1
        assert abs(first["backgroundAlpha"] - 0.65) < 0.01
        window = first["window"]
        assert abs(first["articleWidth"] - 680) < 1, first
        assert abs(first["articleGutter"] * 2 + first["articleWidth"] - first["viewportWidth"]) < 1, first
        for dark, background in [(True, "#1a1b26"), (False, "#fafafa")]:
            themed = snapshot(directory, "# Theme colors\n\nReadable body and `code`.")
            themed["theme"] = dict(dark=dark, colors=dict(background=background, foreground="#7aa2f7"))
            reply = app.update(themed)
            assert reply["darkAppearance"] == dark
            expected = [int(background[offset:offset + 2], 16) / 255 for offset in (1, 3, 5)]
            assert all(abs(actual - value) < 0.001 for actual, value in zip(reply["backgroundRGB"], expected))
            assert abs(reply["backgroundAlpha"] - 0.65) < 0.01
        # Coalesced frames, malformed frames, and in-process document reuse.
        app.connection.sendall(b'{"bad":true}\n' + json.dumps(snapshot(directory, "# Live edit")).encode() + b"\n")
        assert "error" in app.receive()
        assert "Live edit" in app.receive()["rendered"]
        # Navigation returns Foundation's /tmp spelling; libuv sends /private/tmp.
        alias = snapshot(directory, "# Navigated back")
        alias["source"] = alias["source"].removeprefix("/private")
        assert "Navigated back" in app.update(alias)["rendered"]
        live = snapshot(directory, "# Live after navigation")
        live["activate"] = False
        assert "Live after navigation" in app.update(live)["rendered"]
        assert app.update(live)["window"] == window
        second = snapshot(directory, "# Other buffer")
        second["source"] = str(directory / "second.md")
        reply = app.update(second)
        assert reply["window"] == window and reply["windows"] == 1
        for source in [directory / "escape.md", directory.parent / (directory.name + "-outside.md"), directory / "missing.md"]:
            invalid = snapshot(directory, "must not display")
            invalid["source"] = str(source)
            assert "error" in app.update(invalid), source
        reply = app.update(snapshot(directory, "| A | B |\n|---|---|\n| readable | table |\n\n```mermaid\ngraph TD; A-->B\n```"))
        assert "readable" in reply["rendered"] and "graph TD; A-->B" in reply["rendered"]
        assert reply["window"] == window
        # The image must be loaded AND reachable by scrolling, not merely present
        # as an off-screen NSTextAttachment in an unscrollable viewport-height view.
        image = directory / "colors.png"
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        row = b"\0" + bytes([255, 0, 0]) * 60 + bytes([0, 255, 0]) * 60
        image.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", 120, 70, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(row * 70)) + chunk(b"IEND", b""))
        long_document = "# Scroll to the image\n\n" + "Long paragraph.\n\n" * 150 + "![Red and green](colors.png)\n"
        reply = app.update(snapshot(directory, long_document))
        assert reply["attachments"] == 1, "local PNG did not render as a native image"
        assert reply["contentHeight"] > reply["viewportHeight"] * 2, (
            f"image below fold cannot be scrolled into view: {reply['contentHeight']} vs {reply['viewportHeight']}"
        )
    finally:
        app.disconnect()
    print("PASS: real native IPC, fragmented UTF-8, coalesced frames, invalid input, symlink/root rejection, window reuse, rendering, scrollable image below fold, EOF exit")

    # Closing/killing the app disconnects cleanly too, without touching the source file.
    app = NativePreview(directory)
    app.update(snapshot(directory, "# Read only"))
    app.process.terminate()
    app.process.wait(timeout=5)
    assert app.reader.read() == b""
    app.reader.close(); app.connection.close(); app.listener.close(); app.socket_path.unlink()
    assert (directory / "first.md").read_text() == "# Saved first\n"
    print("PASS: app termination disconnects IPC and leaves document untouched")


def verify_neovim(directory):
    before = set(Path("/tmp").glob("nvim-markdown-*"))
    result = subprocess.run(
        ["nvim", "--headless", "--cmd", "lua vim.opt.rtp:prepend(vim.env.MARKDOWN_PREVIEW_REPOSITORY)",
         "-u", str(REPOSITORY / "init.lua"), "-l", str(PACKAGE / "Tests/neovim-integration.lua")],
        cwd=REPOSITORY, env=dict(ENVIRONMENT, MARKDOWN_PREVIEW_TEST_DIRECTORY=str(directory),
                                MARKDOWN_PREVIEW_REPOSITORY=str(REPOSITORY)), timeout=40,
    )
    assert result.returncode == 0, result.returncode
    report = json.loads((directory / "neovim-result.json").read_text())
    deadline = time.monotonic() + 5
    while subprocess.run(["ps", "-p", str(report["pid"])], stdout=subprocess.DEVNULL).returncode == 0:
        assert time.monotonic() < deadline, "native app orphaned after Neovim disconnect"
        time.sleep(0.05)
    assert set(Path("/tmp").glob("nvim-markdown-*")) == before, "Neovim left its socket directory behind"
    print("PASS: Neovim exit leaves no native app or socket directory")


def measure_native_preview(directory):
    starts, memory = [], []
    for _ in range(5):
        app = NativePreview(directory)
        try:
            app.update(snapshot(directory, (PACKAGE / "Tests/representative.md").read_text()))
            starts.append((time.perf_counter() - app.started) * 1000)
            time.sleep(2)
            memory.append(int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(app.process.pid)]).strip()) / 1024)
        finally:
            app.disconnect()
    print(json.dumps(dict(
        measurement="fresh-process launch to first rendered IPC acknowledgement; warm filesystem cache; release arm64; RSS after 2 seconds idle",
        document_bytes=(PACKAGE / "Tests/representative.md").stat().st_size,
        startup_ms=[round(value, 1) for value in starts], median_startup_ms=round(statistics.median(starts), 1),
        idle_rss_mib=[round(value, 1) for value in memory], median_idle_rss_mib=round(statistics.median(memory), 1),
    ), indent=2))


if __name__ == "__main__":
    assert EXECUTABLE.exists(), "run ./build.sh first"
    with tempfile.TemporaryDirectory(prefix="markdown-verify-", dir="/tmp") as temporary:
        directory = Path(temporary).resolve()
        (directory / "first.md").write_text("# Saved first\n")
        (directory / "second.md").write_text("# Saved second\n")
        # A sibling outside the inferred root, with an inside-root symlink to it.
        outside = directory.parent / (directory.name + "-outside.md")
        outside.write_text("secret")
        (directory / "escape.md").symlink_to(outside)
        try:
            verify_native_ipc(directory)
            verify_neovim(directory)
            measure_native_preview(directory)
        finally:
            outside.unlink()
