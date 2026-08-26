# Changelog

All notable user-facing changes to ClipStow are documented here.

## [Unreleased]

### Added

- Added a Folder section alongside Notes and Scratchpad with user-selected folder access.
- Added Finder-style folder navigation, automatic file-list refresh, ascending/descending sorting by name, modified date, or size, file metadata, inline and full Quick Look previews, and file dragging into other apps.
- Added Command-click multi-selection, `Command+A` Select All, and Finder-style context-menu actions for opening, Quick Look, revealing, renaming, duplicating, copying, getting info, and confirmed moves to the macOS Trash.
- Restored selected-folder access across launches with a removable security-scoped bookmark.

## [0.1.0-beta.2] - 2026-08-22

### Improved

- Reduced typing latency by keeping editor drafts separate from persisted note state and debouncing commits.
- Cached Markdown preview content and reduced unnecessary note-list recomputation.
- Remembered the Edit or Preview selection across note changes, popover reopen, and app relaunch.
- Isolated Scratchpad updates so they no longer refresh the Notes interface.
- Stopped clipboard polling while Copy Capture is off.
- Added bounded previews with Show More and Show Less for long Scratchpad entries while preserving their full original text.
- Reduced repeated formatting, allocation, and row rendering work in Scratchpad.

[0.1.0-beta.2]: https://github.com/parkcom/clipstow/releases/tag/v0.1.0-beta.2

## [0.1.0-beta.1] - 2026-08-19

First public beta.

### Added

- Native macOS menu bar notes with Markdown editing and preview.
- Categories with collapse, rename, deactivate, and confirmed deletion.
- Memory-only Scratchpad with clipboard capture and per-item actions.
- Customizable global shortcut with conflict feedback.
- Resizable and pinnable popover.
- English, Korean, and Japanese interfaces.
- Launch at login and adjustable interface, note, and Scratchpad font sizes.
- Single-instance protection.

[0.1.0-beta.1]: https://github.com/parkcom/clipstow/releases/tag/v0.1.0-beta.1
