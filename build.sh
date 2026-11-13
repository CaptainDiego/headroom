#!/bin/zsh
# Usage: ./build.sh           build Headroom.app (universal: Apple Silicon + Intel)
#        ./build.sh install   build, copy to /Applications and launch
#        ./build.sh dmg       build Headroom-<version>.dmg for a release
# VERSION env var sets the app version (default 1.0), e.g. VERSION=1.1 ./build.sh dmg
set -e
cd "$(dirname "$0")"
APP=Headroom.app
VERSION=${VERSION:-1.0}
rm -rf $APP
mkdir -p $APP/Contents/MacOS
BUILD=$(mktemp -d)
for ARCH in arm64 x86_64; do
  swiftc -Osize -parse-as-library -target $ARCH-apple-macos13.0 -Xlinker -dead_strip main.swift -o $BUILD/Headroom-$ARCH
done
lipo -create $BUILD/Headroom-arm64 $BUILD/Headroom-x86_64 -output $APP/Contents/MacOS/Headroom
rm -rf $BUILD
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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <!-- Trades a little malloc speed for ~1.5-2 MB less memory; irrelevant for an idle menu bar app. -->
  <key>LSEnvironment</key><dict><key>MallocSpaceEfficient</key><string>1</string></dict>
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

if [[ "$1" == "dmg" ]]; then
  DMG=Headroom-$VERSION.dmg
  STAGE=$(mktemp -d)
  cp -R $APP $STAGE/
  ln -s /Applications $STAGE/Applications
  rm -f $DMG
  hdiutil create -volname Headroom -srcfolder $STAGE -fs HFS+ -format UDZO -ov $DMG >/dev/null
  rm -rf $STAGE
  echo "Built $DMG ($(du -sh $DMG | cut -f1))"
fi
