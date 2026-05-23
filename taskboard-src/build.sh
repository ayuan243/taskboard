#!/bin/bash
# Build 任务板.app
set -e
DEST="$HOME/Desktop/任务板.app"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

# Compile Swift
swiftc main.swift -o "$DEST/Contents/MacOS/TaskBoard"

# Info.plist
cat > "$DEST/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TaskBoard</string>
  <key>CFBundleName</key><string>任务板</string>
  <key>CFBundleIdentifier</key><string>com.user.taskboard</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

# Generate icon
python3 make_icon.py
if [ -f /tmp/taskboard_icon.png ]; then
  mkdir -p /tmp/taskboard.iconset
  for sz in 16 32 64 128 256 512; do
    sips -z $sz $sz /tmp/taskboard_icon.png --out /tmp/taskboard.iconset/icon_${sz}x${sz}.png 2>/dev/null
  done
  iconutil -c icns /tmp/taskboard.iconset -o "$DEST/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

# Copy HTML
cp ../日历任务板.html "$HOME/软件/日历任务板.html" 2>/dev/null || true

# Sign
codesign --force --sign - "$DEST"
echo "✅ Build complete → $DEST"
