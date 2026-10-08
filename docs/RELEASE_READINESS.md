# Release readiness

The current Objective K build is a development preview, not a release candidate.
Every visible action must pass a behavior test before submission. A compiled or
ad-hoc-signed bundle alone does not establish readiness.

## Editor acceptance gates

- [ ] Repeated long/short file switches show each document's own contents.
- [ ] Unsaved edits survive tab switches and closing a background tab.
- [ ] Each document has independent undo/redo history and selection/scroll state.
- [ ] New documents have unique identities; Save opens a save panel.
- [ ] Save As updates tab identity, title, language, and later Save destination.
- [ ] Atomic save reports permission, full-disk, and encoding errors.
- [ ] Close, Quit, window close, and Revert protect unsaved edits.
- [ ] Save All includes untitled documents and handles cancellation.
- [ ] Unicode, emoji, combining characters, CRLF, and empty files work safely.
- [ ] Invalid text/binary input never silently becomes an empty document.
- [ ] Find/replace, clipboard, shortcuts, zoom, gutter, and minimap work.
- [ ] Folder navigation, recent items, and workspace actions match their labels.
- [ ] Terminal accepts input, resizes, and shuts down its child process on exit.
- [ ] Build/Run report errors without blocking or overwriting unsaved documents.
- [ ] New Window opens this build and supports independent documents.
- [ ] Finder Open With, dropped files, launch arguments, and reopening work.
- [ ] Accessibility labels, keyboard navigation, appearance, and window resizing pass.
- [ ] Large-file performance, crash recovery, and sustained use pass.

## Mac App Store gates

- [x] Store feature scope chosen: editor-only; full developer edition retained.
- [ ] Editor-only Store build verified to launch without external tool dependencies.
- [ ] App Sandbox enabled and tested with actual entitlements.
- [ ] Native file panels grant access; security-scoped bookmarks restore access.
- [ ] Application Support/preferences/recovery files live in the app container.
- [ ] Bundle identifier, display name, versions, minimum OS, and document UTIs finalized.
- [ ] Icons, privacy disclosures, support URL, screenshots, and store metadata complete.
- [ ] App and installer distribution certificates available with private keys.
- [ ] Appropriate provisioning/signing verified; packaged using Xcode technologies.
- [ ] Supported architectures and currently shipping macOS tested.
- [ ] Signed archive validated, then tested through TestFlight.
- [ ] User reviews the exact upload/submission before it is sent.

## Findings (2026-10-08)

Source audit found background-tab close dropping active edits, Save As retaining
an obsolete tab path, reused untitled identities, a shared undo history, unsafe
UTF-8 byte offsets passed to UTF-16 AppKit APIs, unchecked writes, and no unsaved
changes confirmation. Fixes require regression evidence before checking gates.

The current build uses ad-hoc signing. An unrestricted read confirmed a usable
Developer ID Application identity for team SD4X94BA97. The earlier zero-result
was limited by the shell sandbox. A Mac App Store distribution identity and
installer identity have not yet been found; Developer ID signing is for direct
distribution and does not replace App Store signing.

Apple references:

- [App Review Guidelines, 2.4.5 and 2.5](https://developer.apple.com/app-store/review/guidelines/#performance)
- [Configuring App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Accessing files from App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

## Regression evidence

Native `brain --self-test` passes document isolation, background-tab close, unique
untitled identities, independent undo-manager ownership, the switch guard,
Unicode highlight ranges following emoji, and an atomic UTF-8 save round trip.
This is model-level evidence; visible save dialogs, actual undo/redo gestures,
window lifecycle, and sandbox relaunch behavior still require UI verification.
