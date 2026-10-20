#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp/}tinyshot-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp/}tinyshot-module-cache"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local
mkdir -p dist/TinyShot.app/Contents/MacOS dist/TinyShot.app/Contents/Resources
cp .build/release/TinyShot dist/TinyShot.app/Contents/MacOS/TinyShot.next
mv dist/TinyShot.app/Contents/MacOS/TinyShot.next dist/TinyShot.app/Contents/MacOS/TinyShot
cp Resources/Info.plist dist/TinyShot.app/Contents/Info.plist
swift scripts/make-icon.swift dist/AppIcon.iconset dist/TinyShot.app/Contents/Resources/AppIcon.icns
codesign --force --sign - dist/TinyShot.app
echo "Built: $PWD/dist/TinyShot.app"
