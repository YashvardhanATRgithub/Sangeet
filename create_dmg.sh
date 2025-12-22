#!/bin/bash

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/Sangeet.app"
    exit 1
fi

APP_PATH="$1"
APP_NAME=$(basename "$APP_PATH")
DMG_NAME="Sangeet.dmg"
SOURCE_DIR="dmg_source"

# Clean up previous runs
rm -rf "$SOURCE_DIR"
rm -f "$DMG_NAME"

# Create source directory
mkdir "$SOURCE_DIR"

# Copy the app to the source directory
echo "Copying $APP_NAME to $SOURCE_DIR..."
cp -R "$APP_PATH" "$SOURCE_DIR/"

# Create a symbolic link to /Applications
ln -s /Applications "$SOURCE_DIR/Applications"

# Create the DMG
echo "Creating $DMG_NAME..."
hdiutil create -volname "Sangeet Installer" -srcfolder "$SOURCE_DIR" -ov -format UDZO "$DMG_NAME"

# Cleanup
rm -rf "$SOURCE_DIR"

echo "Done! Created $DMG_NAME"
