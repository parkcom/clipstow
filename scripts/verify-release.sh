#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <notarized-dmg>" >&2
  exit 64
fi

dmg_path="$1"

if [[ ! -f "$dmg_path" ]]; then
  echo "DMG not found: $dmg_path" >&2
  exit 66
fi

codesign --verify --verbose=2 "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"
shasum -a 256 "$dmg_path"
