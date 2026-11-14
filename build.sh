#!/bin/zsh
# Builds "Melcolm All-in-One.app" and (with --install) copies it to /Applications.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/Melcolm All-in-One.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MelcolmAIO "$APP/Contents/MacOS/MelcolmAIO"
cp Info.plist "$APP/Contents/Info.plist"
# Sign with the local certificate if it exists (run ./make-cert.sh once), so macOS
# remembers permissions between builds. Falls back to ad-hoc signing.
ID=$(security find-identity -p codesigning | grep "Melcolm Local Signing" | head -1 | awk '{print $2}')
codesign --force --deep --sign "${ID:--}" "$APP"
echo "Built $APP"
if [[ "$1" == "--install" ]]; then
  pkill -x MelcolmAIO || true
  rm -rf "/Applications/Melcolm All-in-One.app"
  cp -R "$APP" /Applications/
  open "/Applications/Melcolm All-in-One.app"
  echo "Installed and opened"
fi
