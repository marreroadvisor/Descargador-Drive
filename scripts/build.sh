#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RCLONE_BINARY="${RCLONE_BINARY:-Resources/rclone}"
if [ ! -f "$RCLONE_BINARY" ]; then
  echo "Falta rclone. Descarga la versión oficial para tu arquitectura desde https://rclone.org/downloads/ y define RCLONE_BINARY con su ruta."
  exit 1
fi
STAGING="$(mktemp -d /tmp/descargador-drive.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Descargador Drive.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
xcrun swiftc -parse-as-library -O -target arm64-apple-macosx13.0 -module-cache-path build/module-cache Sources/DriveDownloaderApp.swift -o "$APP/Contents/MacOS/DescargadorDrive" -framework SwiftUI -framework AppKit
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/RCLONE-LICENSE.txt "$APP/Contents/Resources/"
cp "$RCLONE_BINARY" "$APP/Contents/Resources/rclone"
chmod +x "$APP/Contents/Resources/rclone"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
ditto --norsrc --noextattr "$APP" "build/Descargador Drive.app"
echo "Aplicación creada: build/Descargador Drive.app"
