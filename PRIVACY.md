# Privacy

ClipStow is designed as a local-only application.

## Data stored on disk

- Notes, categories, and the last selected note are stored as a JSON file in the app sandbox's Application Support directory.
- Interface preferences, Copy Capture state, language, shortcut, and popover settings are stored in macOS UserDefaults.
- Login-at-launch state is managed by macOS.

## Clipboard access

Copy Capture is optional. When enabled, ClipStow checks the system Pasteboard change counter every 250 ms and reads the current string only after that counter changes.

- ClipStow does not intercept `⌘C` or monitor keyboard input.
- Clipboard changes made while ClipStow is the active application are ignored.
- Captured Scratchpad text remains in memory unless the user explicitly saves it as a note.
- Unsaved Scratchpad text is cleared when the app quits.
- macOS may request permission for programmatic Pasteboard access.

## Network and third parties

ClipStow does not include accounts, advertising, analytics, telemetry, crash-reporting SDKs, cloud sync, or application-level network requests. The source build uses Swift Package Manager to download its open-source build dependencies when needed.

## Deletion

Users can delete individual notes, Scratchpad items, or categories. Deleting a category also deletes all notes inside it after confirmation. Deleted content is not recoverable from within ClipStow.
