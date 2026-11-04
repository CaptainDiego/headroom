#!/bin/zsh
# Usage: ./build.sh           build Headroom.app
#        ./build.sh install   build, copy to /Applications and launch
set -e
cd "$(dirname "$0")"
APP=Headroom.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -Osize -parse-as-library -Xlinker -dead_strip main.swift -o $APP/Contents/MacOS/Headroom
strip -rSTx $APP/Contents/MacOS/Headroom
mkdir -p $APP/Contents/Resources
ICONSET=$(mktemp -d)/AppIcon.iconset
swift icon.swift $ICONSET
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns
rm -rf "$(dirname $ICONSET)"
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.captaindiego.headroom</string>
  <key>CFBundleName</key><string>Headroom</string>
  <key>CFBundleExecutable</key><string>Headroom</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $APP ($(du -sh $APP | cut -f1))"

if [[ "$1" == "install" ]]; then
  pkill -x Headroom 2>/dev/null || true
  rm -rf /Applications/$APP
  cp -R $APP /Applications/
  open /Applications/$APP
  echo "Installed /Applications/$APP"
fi
