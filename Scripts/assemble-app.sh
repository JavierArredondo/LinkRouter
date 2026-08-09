#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_root/build/LinkRouter.app"

swift build --package-path "$project_root"
rm -rf "$build_dir"
mkdir -p "$build_dir/Contents/MacOS" "$build_dir/Contents/Resources"
cp "$project_root/.build/debug/LinkRouter" "$build_dir/Contents/MacOS/LinkRouter"
cp "$project_root/Sources/LinkRouter/App/Info.plist" "$build_dir/Contents/Info.plist"
# The icon is generated from source rather than checked in as a binary; see Scripts/generate-icon.swift.
swift "$project_root/Scripts/generate-icon.swift" "$project_root/build"
cp "$project_root/build/AppIcon.icns" "$build_dir/Contents/Resources/AppIcon.icns"
# The linker ad-hoc signs the bare executable before the Info.plist exists, leaving the bundle with
# "Info.plist=not bound" and the wrong signing identifier, which makes Launch Services registration
# unreliable. Re-sign the assembled bundle so the plist is sealed and the identity is com.linkrouter.app.
codesign --force --sign - "$build_dir"
echo "Created $build_dir"
