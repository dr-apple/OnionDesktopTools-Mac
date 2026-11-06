#!/bin/zsh
# Builds a universal (Apple silicon + Intel) app for a GitHub release and zips it.
# Signed ad hoc on purpose: an Apple Development certificate would put your
# account email into a public download, and only a Developer ID can be notarized.
#
# Usage: tools/release.sh 0.1.0   -> dist/OnionDesktopTools-0.1.0.zip
set -euo pipefail
here=${0:A:h:h}
name="OnionDesktopTools"
version=${1:?usage: tools/release.sh <version>}
scratch="$HOME/Library/Developer/$name/universal"
dist="$here/dist"

swift build -c release --arch arm64 --arch x86_64 --package-path "$here" --scratch-path "$scratch" 2>&1 \
  | grep -E "error|Build complete" || true
bin="$scratch/out/Products/Release/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }

app="$dist/$name.app"
rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" \
    -e "s|<key>CFBundleShortVersionString</key><string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>$version</string>|" \
    "$here/Info.plist.in" > "$app/Contents/Info.plist"
"$here/tools/make_icon.sh" >/dev/null
cp -X "$here/Resources/Assets.car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
lipo -archs "$app/Contents/MacOS/$name"
ditto -c -k --keepParent "$app" "$dist/$name-$version.zip"
shasum -a 256 "$dist/$name-$version.zip"
