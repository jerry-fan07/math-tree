#!/usr/bin/env bash
# Assemble MathTree.app around the SwiftPM `MathTree` executable.
# Usage: Scripts/bundle-app.sh [debug|release]   (default: debug)
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product MathTree
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# Compile content into the artifacts the app consumes. graph.json and
# layout.json are build outputs, never sources (implementation-plan §0).
swift run -c "$CONFIG" ContentBuild build --out "$ROOT/build/content"
swift run -c "$CONFIG" ContentBuild layout --out "$ROOT/build/content"

APP="$ROOT/build/MathTree.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/MathTree" "$APP/Contents/MacOS/MathTree"

# SwiftPM emits resource bundles next to the binary; carry them into the app.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

cp "$ROOT/build/content/graph.json" "$ROOT/build/content/layout.json" \
   "$ROOT/build/content/problems.json" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>MathTree</string>
    <key>CFBundleDisplayName</key>     <string>Knowledge Tree</string>
    <key>CFBundleIdentifier</key>      <string>com.mathtree.app</string>
    <key>CFBundleExecutable</key>      <string>MathTree</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>15.0</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $APP"
