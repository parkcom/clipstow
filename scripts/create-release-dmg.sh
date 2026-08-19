#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <notarized-app> <output-dmg> [notary-keychain-profile]" >&2
  exit 64
fi

app_path="$1"
output_path="$2"
notary_profile="${3:-}"
signing_identity="Developer ID Application: Jungsoo Park (6Z36689DMN)"

if [[ ! -d "$app_path" || "${app_path##*.}" != "app" ]]; then
  echo "Notarized app not found: $app_path" >&2
  exit 66
fi

if [[ -e "$output_path" ]]; then
  echo "Output already exists: $output_path" >&2
  exit 73
fi

if ! codesign --verify --deep --strict "$app_path"; then
  echo "The app does not have a valid code signature." >&2
  exit 65
fi

if ! xcrun stapler validate "$app_path"; then
  echo "The app does not have a valid notarization ticket." >&2
  exit 65
fi

stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipstow-dmg.XXXXXX")"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

cp -R "$app_path" "$stage_dir/ClipStow.app"
ln -s /Applications "$stage_dir/Applications"

mkdir -p "$(dirname "$output_path")"
hdiutil create \
  -volname "ClipStow" \
  -srcfolder "$stage_dir" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$output_path"

codesign --force --timestamp --sign "$signing_identity" "$output_path"
codesign --verify --verbose=2 "$output_path"

if [[ -n "$notary_profile" ]]; then
  xcrun notarytool submit "$output_path" \
    --keychain-profile "$notary_profile" \
    --wait
  xcrun stapler staple "$output_path"
  xcrun stapler validate "$output_path"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$output_path"
else
  echo "DMG created and signed. Notarization was skipped because no keychain profile was supplied."
fi

shasum -a 256 "$output_path"
