#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PLIP_VERSION="$(tr -d '[:space:]' < VERSION)"
if ! [[ "$PLIP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'VERSION must contain a version such as 1.0.1.' >&2; exit 1; fi
APP="$PWD/dist/Plip.app"
mkdir -p dist .build
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/Plip.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
xcrun swiftc -O -whole-module-optimization -target arm64-apple-macos13.0 \
  -file-prefix-map "$PWD"=. -debug-prefix-map "$PWD"=. \
  -module-cache-path "$PWD/.build/ModuleCache" -module-name Plip \
  Sources/Plip/*.swift -o "$BUNDLE/Contents/MacOS/Plip" -framework AppKit
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PLIP_VERSION" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PLIP_VERSION" "$BUNDLE/Contents/Info.plist"
# A missing icon is a build error, never a silently shipped generic app icon.
cp Resources/PlipIcon.icns "$BUNDLE/Contents/Resources/PlipIcon.icns"
if [ "${CODESIGN_IDENTITY:--}" = "-" ]; then
  /usr/bin/codesign --force --sign - "$BUNDLE"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$BUNDLE"
# Replace only the generated application so stale resource names cannot survive.
rm -rf "$APP"
ditto --norsrc --noextattr --noacl "$BUNDLE" "$APP"
echo "Built dist/Plip.app ($PLIP_VERSION, Apple Silicon)"
if [ "${1:-}" = "--pkg" ]; then
  PKG_ARGS=(--root "$STAGING" --identifier com.plip.editor --version "$PLIP_VERSION"
    --ownership recommended --component-plist Resources/Components.plist --install-location /Applications)
  if [ -n "${INSTALLER_SIGN_IDENTITY:-}" ]; then PKG_ARGS+=(--sign "$INSTALLER_SIGN_IDENTITY" --timestamp); fi
  COPYFILE_DISABLE=1 pkgbuild "${PKG_ARGS[@]}" "$PWD/dist/Plip-$PLIP_VERSION-arm64.pkg"
  cp "dist/Plip-$PLIP_VERSION-arm64.pkg" dist/Plip-arm64.pkg
  ditto --norsrc --noextattr --noacl -c -k --keepParent "$BUNDLE" dist/Plip-arm64.zip
  (cd dist && shasum -a 256 Plip-arm64.pkg Plip-arm64.zip > SHA256SUMS.txt)
fi
