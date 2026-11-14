#!/bin/zsh
# Builds "Melcolm All-in-One.app" and (with --install) copies it to /Applications.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/Melcolm All-in-One.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MelcolmAIO "$APP/Contents/MacOS/MelcolmAIO"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
if [[ "$1" == "--install" ]]; then
  pkill -x MelcolmAIO || true
  rm -rf "/Applications/Melcolm All-in-One.app"
  cp -R "$APP" /Applications/
  open "/Applications/Melcolm All-in-One.app"
  echo "Installed and opened"
fi
