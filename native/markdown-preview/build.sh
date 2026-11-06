#!/bin/sh
set -eu
cd "$(dirname "$0")"
# Honor a valid explicit toolchain, otherwise use the installed Xcode/CLT selection.
if [ ! -d "${DEVELOPER_DIR:-/nonexistent}" ]; then
  DEVELOPER_DIR="$(xcode-select -p)"
  if [ ! -d "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
  export DEVELOPER_DIR
fi
swift build -c release --disable-automatic-resolution
app="Markdown Preview.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/MarkdownPreview "$app/Contents/MacOS/MarkdownPreview"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MarkdownPreview</string>
<key>CFBundleIdentifier</key><string>local.dotfiles.MarkdownPreview</string>
<key>CFBundleName</key><string>Markdown Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf 'Installed locally: %s/%s\n' "$PWD" "$app"
