#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build docs
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" Scripts/make-icon.swift -o .build/make-icon
.build/make-icon .build/PlipIcon.iconset
cp .build/PlipIcon.iconset/PlipIcon.icns Resources/PlipIcon.icns
cp .build/PlipIcon.iconset/icon_256x256@2x.png docs/icon.png
sips -g pixelWidth -g pixelHeight Resources/PlipIcon.icns >/dev/null
