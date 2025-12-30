#!/bin/bash
set -e

# Configuration
APP_NAME="Sangeet"
DMG_NAME="Sangeet_Installer.dmg"
APP_PATH="build/Export/Sangeet3.app"
BACKGROUND_IMG="installer_assets/background.png"
VOL_NAME="Sangeet Installer"

# Cleanup
rm -f "$DMG_NAME"
rm -f "pack.temp.dmg"
rm -rf "dmg_temp"

echo "Creating temporary DMG..."
# Create a folder for the DMG content
mkdir -p dmg_temp
cp -r "$APP_PATH" "dmg_temp/$APP_NAME.app"
ln -s /Applications "dmg_temp/Applications"
mkdir -p "dmg_temp/.background"
cp "$BACKGROUND_IMG" "dmg_temp/.background/background.png"

# Create the Read-Write DMG
hdiutil create -srcfolder "dmg_temp" -volname "$VOL_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 200m "pack.temp.dmg"

echo "Mounting DMG..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "pack.temp.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')

echo "Applying styles via AppleScript..."
# AppleScript to set window size, background, and icon positions
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1000, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 72
        delay 2
        -- set background picture of theViewOptions to file "Sangeet Installer:.background:background.png"
        make new alias file at container window to POSIX file "/Applications" with properties {name:"Applications"}
        set position of item "$APP_NAME.app" of container window to {160, 200}
        set position of item "Applications" of container window to {440, 200}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

echo "Finalizing DMG..."
hdiutil detach "$DEVICE"
echo "Compressing..."
hdiutil convert "pack.temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"

# Cleanup
rm -f "pack.temp.dmg"
rm -rf "dmg_temp"

echo "Done! Created $DMG_NAME"
