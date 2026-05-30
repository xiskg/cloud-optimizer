#!/bin/bash

APP_NAME="CloudOptimizer"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Building ${APP_NAME}..."

# Clean up
rm -rf "$BUNDLE_NAME"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile Swift code
swiftc -o "${MACOS_DIR}/${APP_NAME}" main.swift -framework AppKit

# Copy icon if it exists
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    ICON_LINE=""
fi

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.xiskg.cloudoptimizer</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    ${ICON_LINE}
</dict>
</plist>
EOF

echo "✅ App bundle created: ${BUNDLE_NAME}"
