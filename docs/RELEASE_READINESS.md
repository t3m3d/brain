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

## GitHub and Source Control verification (2026-10-23)

The installed developer build reused the existing GitHub CLI login and displayed
the account in the rounded Krypton purple box at the bottom of Explorer. The
sidebar Open Folder action appeared in an empty workspace and disappeared after
opening a folder. The global Open Folder menu remained available.

Visible Source Control checks used a disposable local repository: changed-file
diffs showed the expected before/after text, Stage and Unstage updated the index
without losing working edits, Commit Staged included only the staged file, and
Create Branch updated the current branch. No user repository was committed or
pushed during these checks.

Native regressions cover NUL-delimited Git status paths with Unicode, spaces,
newlines and option-like filenames; staging; unborn-branch unstage; staged-only
commit; rename source/destination handling; branch creation; and clone input
validation. The task deadline uses NSDate comparisons because the installed
native compiler's floating return binding did not provide a usable uptime value.

Fresh browser sign-in, cloning an actual GitHub repository, and authenticated
GitHub fetch/pull/push still require end-to-end verification. Repository, Pull
Requests and Issues currently open GitHub browser pages. These features belong
to the developer edition; the sandboxed Store preview remains editor-only.

Native network-handler regressions now pass Fetch, Push, and fast-forward Pull
against a disposable local bare origin and a second clone. Pull refuses unsaved
editor contents. Branch selection refreshes after completion, and completed
repository scans return to a changed-file summary instead of leaving
“Running branches…” displayed. These checks do not contact GitHub.

## Extension package manager (2026-10-24)

The global Extensions menu opens a custom charcoal panel with rounded list
surface, Krypton purple Add VSIX action, selection details, Remove, and Done.
Packages are stored intact by normalized publisher/name, with an explicit
Inactive status. This is package management; VS Code API execution and applying
VSIX grammar/snippet/LSP contributions remain future work.

Import reads only extension/package.json using macOS unzip, with argument arrays,
a 100 MiB input limit, 1 MiB metadata limit, and 15-second deadline. It copies the
archive into private staging before inspection, checks manifest identity, then
moves the completed folder into place. Existing packages require replacement
confirmation. Failed imports preserve installed packages; failed replacement
moves restore the previous folder. No archive paths or binaries are extracted.
Removal validates identity and uses the app-owned extension directory.

Native fixture checks can run against temporary storage:

```
python3 tests/extension_fixtures.py /tmp/brain-extension-fixtures
brain.app/Contents/MacOS/brain --extensions-test /tmp/brain-extension-fixtures
```

Fixtures cover Unicode paths, byte-preserved archives, malformed/missing/oversized
manifests, duplicate manifests, invalid ZIPs, traversal identities, removal, and
cancellation. The separate --self-test mode retains editor/Git regressions.

Verification passed in the installed developer app: real Krypton 2.4.8 VSIX
import, duplicate-package replacement, Escape cancelling removal, confirmed
removal and list refresh, readable custom confirmations, popup close,
maximize/restore, minimize, and reopening from the global menu. Native extension
fixtures and existing editor/terminal/prompt/Explorer/Git regressions all passed.
The package used for visual checks was removed afterward; its source VSIX remains
in the Krypton repository. Store sandbox import still needs separate acceptance
verification; the installed developer app was updated and its signature verified.

## Command Center (2026-10-24)

Reference inspection used the installed VS Code Insiders 1.144.0-insider bundle:
its titlebar command dispatches workbench.action.quickOpenWithModes into Quick
Access with help entries, with optional unified/AI routing depending on settings.
The same bundle registers Quick Search with the % prefix. Microsoft's editor
navigation documentation describes file/command/symbol/line modes and ? help:
https://code.visualstudio.com/docs/editing/getting-started/userinterface
https://code.visualstudio.com/docs/editing/codebasics

Brain now provides native equivalents for editor navigation and quick text search,
with no VS Code runtime dependency. File indexing and disk scanning run in bounded
batches on the app event loop. Open buffers take precedence over on-disk copies,
including unsaved text. UTF-16 cursor offsets match AppKit's text model.
Declaration lookup uses common language declaration keywords; it is not semantic
symbol resolution. Search limits and unimplemented integrations are recorded in
FEATURES.md. Native regression coverage and visual acceptance are in progress.

## Icon and repeated Find opening (2026-10-25)

The supplied root artwork is named codebrain.png. make_icon.ks now packages it
with macOS sips/iconutil into packaging/brain.icns and the 1024px Store icon.
The installed app received the new icon without replacing its existing executable;
its signature and icon container were verified, and the user confirmed appearance.

Repeated Cmd+F opening was reported to leave a blank gray native popup. The first
replacement used a permanent, reserved header above the document, centered
beneath the tabs. The command routes no longer invoke the native Find window.
Native probes passed literal matching, UTF-16 offsets following an emoji, and
literal dollar-sign replacement.

On 2026-10-26 the rebuilt app was installed into /Applications/brain.app. Its
signature verified and installed executable matched the build byte for byte.
Visual acceptance passed: header stays above the document, six Cmd+F/Escape
cycles remain responsive, Next selects the second of two matches, and Replace
All changes both matches. Temporary test text was removed afterward.

The complete self-test is not yet green: Command Center's Back navigation
canonical-file-identity assertion still fails. The Find group now runs before
that assertion and passes. Isolated navigation probes pass, but that does not
resolve the full-suite failure.

The subsequent layout revision keeps only Command Center permanently visible,
directly before the top-right action buttons. It uses the same flipped holder
and vertical center as those actions, without macOS's separate centered-item
placement. Find opens with Cmd+F and Escape collapses its reserved header to
zero height, avoiding a second persistent search box. Replace remains on demand.
Installed and visually verified on 2026-10-26: a single permanent box aligned
with the action row; Cmd+F shows Find and Escape removes its controls again.
The installed executable matches the rebuilt app and its signature verifies.

## Shared toolbar search field (2026-10-26)

The follow-up replaces the toolbar search launcher with one editable field.
Cmd+F switches that field to current-file Find; Cmd+P and command prefixes use
the same field for Command Center. The result panel contains no search field.
Find's reserved header contains match controls only, plus an optional replacement
field. Escape ends the active mode, and the Find query survives mode switching.
Regression coverage checks shared input identity, repeated Find opening/closing,
Unicode offsets, literal replacement, and query restoration after command mode.

Installed verification passed: Cmd+F edits the toolbar field and Enter advances
through two document matches; command mode uses that same field with a visible
results-only child panel; typing preserves the > prefix and Enter executes Zoom
In. Find restores its prior query after commands. Five further Find/Escape cycles
remain responsive. Test text was removed and zoom reset. The native shared-Find
regressions pass; the pre-existing Back canonical-file assertion remains failing.
The installed signature verifies and its executable matches the final build.

## Terminal heading and File Info layout (2026-10-28)

Removed the redundant STEM TERMINAL / zsh label. Rebuilt and installed the app;
its signature verifies and installed executable matches the build. Visual checks
confirm the heading is absent, the terminal remains visible, and File Info text
wraps within its pane. A pending custom split-resize delegate caused a redraw
regression and was removed; standard native split layout is retained.

The active development checkout remains /Users/t3m3d/Documents/GitHub/kcode.
The separately inspected brain-ide checkout points to the same t3m3d/brain remote;
its HEAD is an ancestor of kcode HEAD and it had no unique source changes.
No repository folders or GitHub repositories were deleted by this task.

The terminal's inline × button was subsequently removed (2026-10-28). Installed
signature and executable identity verified. UI checks confirmed the button is
absent and terminal visibility still changes through Cmd+J, View → Toggle
Terminal, and the toolbar terminal button. Terminal was left visible afterward.
