# ClipStow release process

Public releases are built locally because the Developer ID private key and notarization credentials must never be committed or uploaded to GitHub Actions.

## Prerequisites

- Xcode 26 or later
- A valid `Developer ID Application` identity for team `6Z36689DMN`
- Hardened Runtime enabled for the app target
- A notarization credential stored in the login keychain, for example `ClipStow-Notary`

Verify the signing identity without printing private material:

```sh
security find-identity -v -p codesigning
```

## Build and submit the app

Use a clean version-specific output path. Do not overwrite a previous release archive.

```sh
xcodebuild \
  -project ClipStow.xcodeproj \
  -scheme ClipStow \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/ClipStow-v0.1.0-beta.3.xcarchive \
  -derivedDataPath .releaseDerivedData \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/ClipStow-v0.1.0-beta.3.xcarchive \
  -exportPath build/ClipStow-v0.1.0-beta.3-export \
  -exportOptionsPlist Release/ExportOptions.plist \
  -allowProvisioningUpdates
```

Package the Developer ID app, submit it with the stored notarytool profile, and staple the accepted ticket to the same app:

```sh
mkdir -p build/ClipStow-v0.1.0-beta.3

ditto -c -k --keepParent \
  build/ClipStow-v0.1.0-beta.3-export/ClipStow.app \
  build/ClipStow-v0.1.0-beta.3/ClipStow-0.1.0-beta.3-app.zip

xcrun notarytool submit \
  build/ClipStow-v0.1.0-beta.3/ClipStow-0.1.0-beta.3-app.zip \
  --keychain-profile ClipStow-Notary \
  --wait

xcrun stapler staple \
  build/ClipStow-v0.1.0-beta.3-export/ClipStow.app

xcrun stapler validate \
  build/ClipStow-v0.1.0-beta.3-export/ClipStow.app

spctl --assess --type execute --verbose=4 \
  build/ClipStow-v0.1.0-beta.3-export/ClipStow.app
```

## Create and notarize the DMG

```sh
scripts/create-release-dmg.sh \
  build/ClipStow-v0.1.0-beta.3-export/ClipStow.app \
  build/ClipStow-v0.1.0-beta.3/ClipStow-0.1.0-beta.3.dmg \
  ClipStow-Notary

scripts/verify-release.sh \
  build/ClipStow-v0.1.0-beta.3/ClipStow-0.1.0-beta.3.dmg
```

The DMG script refuses to overwrite an existing artifact, validates the app ticket, signs and notarizes the DMG, checks Gatekeeper, and prints its SHA-256 checksum.

## Publish

Create the annotated tag `v0.1.0-beta.3`, push it, and create a GitHub prerelease using the matching changelog entry. Attach only the notarized DMG and its checksum. Do not upload certificates, CSRs, private keys, archives, or notarization credentials.
