#!/bin/bash
# Baut Snip.app. Ein echtes Bundle ist Pflicht: macOS hängt die
# Bedienungshilfen-Freigabe ans Bundle – ein nacktes CLI-Binary würde die
# Berechtigung dem Terminal zuschreiben und sich sprunghaft verhalten.
set -euo pipefail

cd "$(dirname "$0")"
APP="Snip.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/snip "$APP/Contents/MacOS/Snip"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Snip</string>
    <key>CFBundleDisplayName</key>     <string>Snip</string>
    <key>CFBundleExecutable</key>      <string>Snip</string>
    <key>CFBundleIdentifier</key>      <string>io.moux.snip</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Prototyp</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo "Fertig: $(pwd)/$APP"
echo "Starten:  open $APP"
