#!/usr/bin/env bash
# Builds a downloadable DMG of this fork (czubaker/kaset).
#
# The fork has no Developer ID, so the app is ad-hoc signed and not notarized.
# Sparkle points at the fork's own empty feed (appcast-fork.xml) with automatic
# checks off, so the app never offers to replace itself with an upstream release.
#
# Usage: Scripts/release-fork.sh VERSION BUILD_NUMBER
#   e.g. Scripts/release-fork.sh 0.14.2-fork.1 28
# Writes .build/release/kaset-VERSION.dmg and prints its SHA-256.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ $# -ne 2 ]]; then
  echo "Usage: Scripts/release-fork.sh VERSION BUILD_NUMBER" >&2
  exit 1
fi
VERSION=$1
BUILD_NUMBER=$2

# build-app.sh reads the version from version.env; restore it afterwards.
VERSION_BACKUP=$(mktemp)
cp version.env "$VERSION_BACKUP"
trap 'cp "$VERSION_BACKUP" version.env; rm -f "$VERSION_BACKUP"' EXIT
printf 'MARKETING_VERSION=%s\nBUILD_NUMBER=%s\n' "$VERSION" "$BUILD_NUMBER" > version.env

KASET_SIGNING=adhoc \
ARCHES="arm64 x86_64" \
KASET_SPARKLE_FEED_URL="https://raw.githubusercontent.com/czubaker/kaset/main/appcast-fork.xml" \
KASET_SPARKLE_AUTOMATIC_UPDATES=false \
  Scripts/build-app.sh release

APP=".build/app/Kaset.app"
Scripts/verify-release-app.sh "$APP"

ARCHS=$(lipo -archs "$APP/Contents/MacOS/Kaset")
if [[ "$ARCHS" != *x86_64* || "$ARCHS" != *arm64* ]]; then
  echo "ERROR: not a universal binary (found: $ARCHS)" >&2
  exit 1
fi
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "ERROR: built version $BUILT_VERSION, expected $VERSION" >&2
  exit 1
fi

OUT=".build/release"
STAGING="$OUT/dmg"
DMG="$OUT/kaset-$VERSION.dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Kaset.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Kaset" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "DMG: $DMG"
echo "Architectures: $ARCHS"
shasum -a 256 "$DMG"
