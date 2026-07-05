#!/bin/bash
#
# Builds a professional drag-to-Applications DMG for Sangeet.
#
# Usage: ./scripts/make_dmg.sh <path-to-Sangeet.app> <version>
# Example: ./scripts/make_dmg.sh /Applications/Sangeet.app 3.4.0
#
set -euo pipefail

APP_PATH="${1:?Usage: make_dmg.sh <path-to-Sangeet.app> <version>}"
VERSION="${2:?Usage: make_dmg.sh <path-to-Sangeet.app> <version>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VOLUME_NAME="Sangeet"
OUT_DMG="$REPO_ROOT/Sangeet_v${VERSION}.dmg"
BACKGROUND="$SCRIPT_DIR/dmg_background.png"

# 1. Render the background if missing
if [ ! -f "$BACKGROUND" ]; then
    swift "$SCRIPT_DIR/generate_dmg_background.swift" "$BACKGROUND"
fi

# 2. Stage the volume contents
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" /tmp/sangeet_rw.dmg' EXIT

cp -R "$APP_PATH" "$STAGE/Sangeet.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BACKGROUND" "$STAGE/.background/background.png"

# 3. Create a writable DMG and mount it
rm -f /tmp/sangeet_rw.dmg
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -fs HFS+ \
    -format UDRW -size 300m /tmp/sangeet_rw.dmg -quiet

MOUNT_DIR="/Volumes/$VOLUME_NAME"
# Detach any stale mount from a previous run
hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
hdiutil attach /tmp/sangeet_rw.dmg -readwrite -noverify -noautoopen -quiet
sleep 2

# 4. Lay out the Finder window (icon view, background, positions)
osascript <<EOF || echo "warning: Finder layout failed; DMG will use default view"
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 110
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Sangeet.app" of container window to {165, 200}
        set position of item "Applications" of container window to {495, 200}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
sleep 1

# 5. Finalize: detach, compress, checksum
hdiutil detach "$MOUNT_DIR" -quiet
rm -f "$OUT_DMG"
hdiutil convert /tmp/sangeet_rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -quiet

echo ""
echo "Created: $OUT_DMG"
echo "size:    $(du -h "$OUT_DMG" | cut -f1)"
echo "sha256:  $(shasum -a 256 "$OUT_DMG" | cut -d' ' -f1)"
