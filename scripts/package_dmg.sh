#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
arm_binary="$project_root/.build/bytetrail-release-arm64/arm64-apple-macosx/release/ByteTrail"
x86_binary="$project_root/.build/bytetrail-release-x86_64/x86_64-apple-macosx/release/ByteTrail"
app_resource_bundle="$project_root/.build/bytetrail-release-arm64/arm64-apple-macosx/release/ByteTrail_ByteTrailApp.bundle"
app_output="$project_root/outputs/ByteTrail.app"
dmg_output="$project_root/outputs/ByteTrail.dmg"

if [[ ! -f "$arm_binary" || ! -f "$x86_binary" ]]; then
  print -u2 "Both arm64 and x86_64 Release binaries are required."
  exit 1
fi

if [[ ! -d "$app_resource_bundle" ]]; then
  print -u2 "The ByteTrail localization resource bundle is required."
  exit 1
fi

if [[ -e "$app_output" || -e "$dmg_output" ]]; then
  print -u2 "Refusing to overwrite an existing ByteTrail app or DMG in outputs/."
  exit 1
fi

packaging_root="$(mktemp -d "${TMPDIR:-/tmp}/ByteTrailPackaging.XXXXXX")"
staged_app="$packaging_root/ByteTrail.app"
dmg_root="$(mktemp -d "${TMPDIR:-/tmp}/ByteTrailDMG.XXXXXX")"

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
lipo -create "$arm_binary" "$x86_binary" -output "$staged_app/Contents/MacOS/ByteTrail"
chmod 755 "$staged_app/Contents/MacOS/ByteTrail"
cp "$project_root/Configuration/Packaged-Info.plist" "$staged_app/Contents/Info.plist"
cp "$project_root/.build/ByteTrail.icns" "$staged_app/Contents/Resources/AppIcon.icns"
cp "$project_root/Sources/ByteTrailCore/Resources/CleanupRules.json" "$staged_app/Contents/Resources/CleanupRules.json"
cp "$project_root/PRIVACY.md" "$staged_app/Contents/Resources/PRIVACY.md"
cp "$project_root/SAFETY_MODEL.md" "$staged_app/Contents/Resources/SAFETY_MODEL.md"
cp "$project_root/Configuration/PkgInfo" "$staged_app/Contents/PkgInfo"
ditto "$app_resource_bundle" "$staged_app/Contents/Resources/ByteTrail_ByteTrailApp.bundle"

plutil -lint "$staged_app/Contents/Info.plist"
codesign --force --deep --options runtime --timestamp=none --sign - "$staged_app"
codesign --verify --deep --strict --verbose=2 "$staged_app"

ditto "$staged_app" "$app_output"
ditto "$staged_app" "$dmg_root/ByteTrail.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -volname "ByteTrail" -srcfolder "$dmg_root" -ov -format UDZO "$dmg_output"

print "Packaged app: $app_output"
print "Packaged DMG: $dmg_output"
