# Privacy

ClipStow is designed as a local-only application.

## Data stored on disk

- Notes, categories, and the last selected note are stored as a JSON file in the app sandbox's Application Support directory.
- Interface preferences, Copy Capture state, language, shortcut, popover settings, and the security-scoped bookmark for a user-selected folder are stored in macOS UserDefaults.
- Login-at-launch state is managed by macOS.

## Folder access

Folder browsing is optional. ClipStow receives read-only access only after the user selects a folder with the macOS folder picker.

- Access is limited to the selected folder and its contents.
- ClipStow reads names and metadata to build the file list and reads a selected file only for Quick Look preview or a user-initiated drag to another app.
- ClipStow does not modify, move, delete, copy into its own storage, upload, or index files in the selected folder.
- A security-scoped bookmark restores the selected folder after relaunch. The user can remove that bookmark with **Disconnect Folder** without deleting any files.

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

Users can delete individual notes, Scratchpad items, or categories. Deleting a category also deletes all notes inside it after confirmation. Deleted content is not recoverable from within ClipStow. Disconnecting a selected folder only removes ClipStow's saved access and never deletes the folder or its files.
