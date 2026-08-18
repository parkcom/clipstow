# Contributing to ClipStow

Thanks for helping improve ClipStow.

## Before opening an issue

- Search existing issues first.
- Include the macOS and Xcode versions you used.
- For bugs, provide concise reproduction steps, expected behavior, and actual behavior.
- Remove private note and clipboard content from screenshots and logs.

## Development setup

1. Fork and clone the repository.
2. Open `ClipStow.xcodeproj` in Xcode 26 or later.
3. Build the `ClipStow` scheme for `My Mac`.
4. Run the full test suite before submitting a pull request:

```sh
xcodebuild -project ClipStow.xcodeproj -scheme ClipStow -destination 'platform=macOS' test
```

## Pull requests

- Keep changes focused and explain user-visible behavior.
- Add or update tests for state, storage, clipboard, and localization behavior.
- Update all three localizations when adding user-facing text.
- Do not commit personal notes, clipboard contents, signing certificates, build products, or Xcode user state.
- Include screenshots for meaningful UI changes, with private content removed.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
