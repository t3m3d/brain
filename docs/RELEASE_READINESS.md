# Release readiness

The current Objective K build is a development preview, not a release candidate.
Every visible action must pass a behavior test before submission. A compiled or
ad-hoc-signed bundle alone does not establish readiness.

## Editor acceptance gates

- [ ] Repeated long/short file switches show each document's own contents.
- [x] Unsaved edits survive tab switches and closing a background tab.
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
- [x] Editor-only Store build verified to launch without external tool dependencies.
- [x] App Sandbox enabled and tested with actual entitlements (basic file-access checks).
- [x] Native file panels grant access; security-scoped bookmarks restore access.
- [x] Application Support/preferences/recovery files live in the app container.
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

## UI verification (2026-10-11)

Developer build: Quick Open searches nested paths case-insensitively; Enter opens
the selected document; arrow keys select a different result; empty searches show
“No results”; Escape restores editor focus. Command Palette filters commands and
runs Zoom In. Explorer expands nested folders and opens their files.

The picker crash was traced to an unresolved theme helper in the previous binary;
a fresh build with the corrected helper passed these UI checks. Native regression
coverage now exercises picker construction, filtering, keyboard commands, binary
NUL rejection, and canonical path identity. The compiler can emit a binary with an
unresolved function call, so successful compilation alone is not sufficient.

Earlier developer-build UI checks passed separate edits in two tabs, per-document
undo/redo, background close with Discard, native Open/Save As panels, Find/Replace,
terminal input and toggle, and a successful asynchronous Run. Remaining compound
acceptance gates above stay unchecked until every part has evidence.

Save-conflict UI verification preserved external disk changes and in-memory edits
when Cancel was chosen. Revert Cancel preserved edits; Revert confirmation
reloaded the disk contents.

The sandboxed Store preview launched with no terminal/compiler controls. Native
folder selection granted access to nested files; an atomic Unicode save reached
the selected file; Application Support was confirmed inside the app container.
Bookmark relaunch initially failed for nested files because only exact bookmark
keys were checked. Ancestor-folder lookup and path-boundary checks were added;
the relaunch result must be verified before checking that gate.

Signing identities were rechecked on 2026-10-11: Developer ID Application remains
available; no App Store application distribution identity was listed.

Bookmark relaunch verification passed after the ancestor lookup fix: a fresh
Store process opened the previously selected folder's nested file through a
launch argument without another file panel. Empty startup/file-only windows now
show Open Folder instead of exposing the home directory or app recovery folder.
The running test window was left open when unsaved user typing appeared.

The final compiler IR was inspected for unresolved calls. Remaining external
calls are declared Objective-C runtime functions and the native bitAnd builtin;
no undeclared theme helper remains.

## Prompt rendering and window controls (2026-10-11)

Native NSAlert windows exposed their accessibility text but rendered blank on
this Objective K/manual-event-loop path. Confirmations now render ordinary
AppKit labels and buttons in a dark panel. A modal session continues processing
window updates until a response arrives. Cancel, Escape, and the panel close
button preserve edits. Prompts use modal window level, join fullscreen Spaces,
and regain focus on application/editor activation. The floating search picker
is hidden before a prompt opens; dismissal restores editor focus.

Explicit Exit, Minimize, and Maximize toolbar controls remain available when
macOS hides the titlebar buttons. Exit still confirms unsaved documents. Prompt
minimize hides the application together so the blocked owner cannot look frozen.
The developer edition's exit cleanup now constructs an NSFileHandle using its
instance initializer; the previous nonexistent class method crashed on quit.

Native document and prompt-ordering regression checks pass. Visual checks
confirmed readable confirmation text/buttons, Escape preserving edits, and the
prompt close button preserving edits, readable prompts above the fullscreen editor,
and visible native Open/Save panels. The same confirmation was visually checked
in the sandboxed Store preview. Release acceptance still requires testing
on additional supported macOS versions.
