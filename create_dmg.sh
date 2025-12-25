#!/bin/bash

# Beautiful DMG Installer Script for Sangeet
# Usage: ./create_dmg.sh /path/to/Sangeet.app

set -e

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/Sangeet.app"
    exit 1
fi

APP_PATH="$1"
APP_NAME=$(basename "$APP_PATH")
DMG_NAME="Sangeet.dmg"
DMG_TEMP="Sangeet_temp.dmg"
SOURCE_DIR="dmg_source"
VOLUME_NAME="Sangeet"
BACKGROUND_IMG="docs/dmg_background.png"

# Clean up previous runs
rm -rf "$SOURCE_DIR"
rm -f "$DMG_NAME"
rm -f "$DMG_TEMP"

# Unmount any existing volume with same name
hdiutil detach "/Volumes/$VOLUME_NAME" 2>/dev/null || true

# Create source directory
mkdir "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR/.background"

# Copy the app to the source directory
echo "📦 Copying $APP_NAME to $SOURCE_DIR..."
cp -R "$APP_PATH" "$SOURCE_DIR/Sangeet.app"

# Copy background image if it exists
if [ -f "$BACKGROUND_IMG" ]; then
    echo "🎨 Adding custom background..."
    cp "$BACKGROUND_IMG" "$SOURCE_DIR/.background/background.png"
fi

# Create a symbolic link to /Applications
ln -s /Applications "$SOURCE_DIR/Applications"

# Calculate size needed (app size + 20MB buffer)
SIZE=$(du -sm "$SOURCE_DIR" | cut -f1)
SIZE=$((SIZE + 20))

echo "💿 Creating DMG ($SIZE MB)..."

# Create a writable DMG
hdiutil create -srcfolder "$SOURCE_DIR" -volname "$VOLUME_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size ${SIZE}m "$DMG_TEMP"

# Mount the DMG
echo "🔧 Configuring DMG appearance..."
hdiutil attach -readwrite -noverify "$DMG_TEMP"

# Wait for mount
sleep 3

# Check if mount succeeded
if [ ! -d "/Volumes/$VOLUME_NAME" ]; then
    echo "❌ Failed to mount DMG"
    exit 1
fi

echo "📍 Mounted at /Volumes/$VOLUME_NAME"

# Use AppleScript to configure the DMG window
osascript << EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        
        -- Set background if available
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        
        -- Position icons
        set position of item "Sangeet.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Sync and unmount
sync
sleep 2
hdiutil detach "/Volumes/$VOLUME_NAME"

# Convert to compressed DMG
echo "📀 Compressing final DMG..."
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"

# Cleanup
rm -rf "$SOURCE_DIR"
rm -f "$DMG_TEMP"

echo ""
echo "✅ Done! Created $DMG_NAME"
echo "   Size: $(du -h "$DMG_NAME" | cut -f1)"
