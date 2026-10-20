#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp/}tinyshot-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp/}tinyshot-module-cache"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
frameworks="$developer_dir/Library/Developer/Frameworks"
if [[ -d "$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks" ]]; then
  frameworks="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
fi
swift test --disable-sandbox --disable-xctest \
  --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local \
  -Xswiftc -F -Xswiftc "$frameworks" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -rpath -Xlinker "$frameworks"
