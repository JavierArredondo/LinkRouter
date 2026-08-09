#!/bin/bash
set -euo pipefail

# Assembles build/LinkRouter.app.
#
#   bash Scripts/assemble-app.sh              # debug, host architecture — fast local iteration
#   CONFIGURATION=release bash Scripts/…      # optimised universal binary, for distribution
#
# SIGNING_IDENTITY selects the codesigning identity; it defaults to "-" (ad-hoc), which is enough to
# run locally but not to distribute. Pass a Developer ID to produce a notarisable bundle.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_root/build/LinkRouter.app"
configuration="${CONFIGURATION:-debug}"
signing_identity="${SIGNING_IDENTITY:--}"

if [ "$configuration" = "release" ]; then
    # Both architectures, because an arm64-only build simply will not launch on an Intel Mac.
    swift build -c release --arch arm64 --arch x86_64 --package-path "$project_root"
    binary="$project_root/.build/apple/Products/Release/LinkRouter"
else
    swift build --package-path "$project_root"
    binary="$project_root/.build/debug/LinkRouter"
fi

rm -rf "$build_dir"
mkdir -p "$build_dir/Contents/MacOS" "$build_dir/Contents/Resources"
cp "$binary" "$build_dir/Contents/MacOS/LinkRouter"
cp "$project_root/Sources/LinkRouter/App/Info.plist" "$build_dir/Contents/Info.plist"
# The icon is rasterised from Resources/AppIcon.svg rather than checked in; see Scripts/generate-icon.swift.
swift "$project_root/Scripts/generate-icon.swift" "$project_root/build"
cp "$project_root/build/AppIcon.icns" "$build_dir/Contents/Resources/AppIcon.icns"

# The linker ad-hoc signs the bare executable before the Info.plist exists, leaving the bundle with
# "Info.plist=not bound" and the wrong signing identifier, which makes Launch Services registration
# unreliable. Re-sign the assembled bundle so the plist is sealed and the identity is com.linkrouter.app.
if [ "$signing_identity" = "-" ]; then
    codesign --force --sign - "$build_dir"
else
    # Notarisation requires the hardened runtime and a secure timestamp; both are rejected for ad-hoc.
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$build_dir"
fi

echo "Created $build_dir ($configuration, $(lipo -archs "$build_dir/Contents/MacOS/LinkRouter"))"
