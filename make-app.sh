#!/bin/zsh
# Packages Quilland as Quilland.app: a real application bundle (Dictation and other system services need one), signed ad hoc.
# Usage: ./make-app.sh   then   open Quilland.app
set -e
cd "$(dirname "$0")"
swift build -c release --product Quilland
APP=Quilland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Quilland "$APP/Contents/MacOS/Quilland"
# The icon (made by ./make-icon.sh from Resources/AppIcon.svg).
[ -f Resources/AppIcon.icns ] || ./make-icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The languages of the interface (JSON files) and the template for a new one.
python3 make-languages.py >/dev/null
mkdir -p "$APP/Contents/Resources/Languages"
cp Resources/Languages/*.json "$APP/Contents/Resources/Languages/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
  <key>CFBundleIdentifier</key><string>com.quilland.app</string>
  <key>CFBundleName</key><string>Quilland</string>
  <key>CFBundleDisplayName</key><string>Quilland</string>
  <key>CFBundleExecutable</key><string>Quilland</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Dictation in the editor.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Dictation in the editor.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP"
echo "built $APP"
