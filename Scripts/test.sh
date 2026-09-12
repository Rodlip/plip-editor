#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -D TESTING -module-cache-path "$PWD/.build/ModuleCache" \
  Sources/Plip/*.swift Tests/PlipTests.swift -o .build/PlipTests -framework AppKit
.build/PlipTests
