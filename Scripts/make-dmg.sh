#!/bin/bash
set -euo pipefail

# Builds a distributable disk image at build/LinkRouter-<version>.dmg.
#
#   bash Scripts/make-dmg.sh
#
# Signing and notarisation are applied only when the corresponding environment variables are set, so
# this produces a working (if Gatekeeper-blocked) image without an Apple Developer account:
#
#   SIGNING_IDENTITY   "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE     a profile stored with `xcrun notarytool store-credentials`
#
# Without notarisation macOS reports the app as damaged on another machine. That message means
# "unnotarised and quarantined", not corrupt — see the README.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
plist="$project_root/Sources/LinkRouter/App/Info.plist"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")"
stage="$project_root/build/dmg"
dmg="$project_root/build/LinkRouter-$version.dmg"

CONFIGURATION=release bash "$project_root/Scripts/assemble-app.sh"

rm -rf "$stage"
mkdir -p "$stage"
cp -R "$project_root/build/LinkRouter.app" "$stage/LinkRouter.app"
# The conventional drag-to-install target. Without it the user has to know to move the app themselves,
# and an app run from the mounted image cannot be registered as a URL handler.
ln -s /Applications "$stage/Applications"

rm -f "$dmg"
hdiutil create -volname "LinkRouter $version" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$stage"

if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$dmg"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    # Stapling lets the image validate offline; without it Gatekeeper needs a network round-trip.
    xcrun stapler staple "$dmg"
fi

hdiutil verify "$dmg" >/dev/null
echo "Created $dmg"
[ -n "${NOTARY_PROFILE:-}" ] || echo "note: not notarised — recipients must clear the quarantine attribute"
