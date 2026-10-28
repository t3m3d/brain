# Brain feature list

Updated: 2026-10-28. Keep this file current whenever a feature is added or changed.
Implementation and remaining release checks are tracked separately in
[RELEASE_READINESS.md](RELEASE_READINESS.md).

## Editor and workspace

- Native Objective-K editor for text and source files, with syntax highlighting,
  line numbers, and font zoom.
- Multiple document tabs with isolated contents, selections, scrolling, and undo.
- Open files and folders, recent items, workspace files, Save As, Save All,
  Auto Save, and Revert File.
- Expandable Explorer folders with stable expansion/collapse state.
- Sidebar Open Folder action shown when no workspace folder is open; global
  menu action remains available at all times.
- Quick Open and searchable Command Palette, including keyboard navigation.
- Find, Find Next/Previous, and Find and Replace.
- Unsaved-change confirmations, atomic saves, session recovery, and protection
  against opening binary files as text.

## Appearance and windows

- Charcoal editor surfaces and darker Krypton purple toolbar symbols (#5D16DA).
- Subtle rounded controls, spaced toolbar actions, and adjusted toolbar position.
- Sidebar and terminal visibility toggles.
- Terminal panel omits the redundant “STEM TERMINAL / zsh” heading and inline
  close button. View menu, toolbar toggle, and Cmd+J control its visibility.
- Custom readable dark confirmation panels, with Escape/Cancel/close behavior.
- Prompt ordering above editor/search windows, fullscreen-space support, and
  restored prompt focus when activating Brain.
- Native titlebar controls plus explicit editor Exit, Minimize, and Maximize
  controls for use when macOS hides its titlebar buttons.

## Stem terminal and build tools — developer edition

- Integrated Stem terminal with a real shell, resizing, Unicode text,
  scrollback, alternate screen, and bracketed paste.
- Build and Run the current Krypton file using the installed compiler.
- Background build/run tasks, captured results, and Stop action.

## GitHub and source control — developer edition

- Rounded Krypton purple GitHub account card at bottom of Explorer.
- Reuse existing GitHub CLI sign-in, with sign-in and refresh actions.
- Source Control panel with changed files and colored working/staged diffs.
- Stage, unstage, commit staged changes, create/select branches.
- Fetch, push, and fast-forward pull; pull protects unsaved editor contents.
- Clone by GitHub OWNER/REPO or HTTPS URL.
- Open repository, Pull Requests, and Issues in the browser.
- Background Git tasks, progress, cancellation, and completion status.

Verification: existing signed-in account and local Git workflows were checked.
Fetch/push/pull handlers passed against a disposable local remote. Fresh browser
sign-in and authenticated GitHub remote operations still need end-to-end checks.

## Extension packages

- Global Extensions menu with Manage Extensions and Add Extension from VSIX.
- Custom charcoal manager popup, rounded list, purple Add VSIX action, version
  display, selection details, Remove, and Done.
- Local VSIX import into Brain's Application Support folder.
- Replacement confirmation for an existing publisher/name.
- Removal confirmation and immediate list refresh.
- Background manifest reading with input/output limits and cancellation.
- Original archives preserved intact; packaged code is not extracted or run.

Verification: native fixtures and existing editor/Git regressions pass. Visual
checks confirmed Add, Replace, Remove, Escape cancellation, popup close,
maximize/restore, minimize, and reopening from the global menu.
Compatibility: imported packages are explicitly marked **Inactive**. Brain does
not yet execute the VS Code extension API or apply VSIX grammars, snippets,
commands, or language-server contributions.

## Krypton extension update — companion package

- Local Krypton VSIX refreshed to 2.4.8 in the sibling Krypton repository.
- Objective-K declaration highlighting and modern Krypton snippets.
- Canonical `print` completions/snippets; legacy `kp` highlighting retained.
- Language-server initialization, restart, shutdown, and stale-diagnostic fixes.
- macOS arm64 language server bundled in the local artifact.
- Explicit package asset list excludes checkout metadata and test fixtures.

Verification: 15 package/client checks passed, including tests against the
extracted VSIX and its real bundled server. Snippet examples compiled and ran.
This companion package targets VS Code-compatible hosts; Brain compatibility
remains subject to the limitation above.

## App Store preparation

- Separate editor-focused sandboxed preview; full developer edition retained.
- Store preview omits terminal, external compiler, and Git/CLI integration.
- Security-scoped file/folder access and remembered folder access.
- Ad-hoc local signing and bundle verification.

Status: development preview, not App Store submission-ready. Distribution
signing, remaining acceptance checks, and supported-macOS coverage remain open.

## Command Center (2026-10-24)

- Shared editable toolbar search field with workspace placeholder and Back/Forward
  arrows. Cmd+F switches that field to current-file Find; Cmd+P restores files.
- A results-only panel for files, recent/open editors, commands, symbols, lines,
  text, and search-mode help. Prefixes switch providers while typing.
- Fuzzy file-name/path matching, with exact/base-name matches ranked first.
- `file:line[:column]` and `:line[:column]` navigation, with Unicode/CRLF handling.
- `>` runs Brain commands, including Extensions, GitHub, View, and Build/Run.
- `@` finds declarations in the current buffer; `#` searches workspace declarations.
- `%` searches literal text across the workspace and open/unsaved buffers, with
  individual match locations. `?` lists modes and switches to the selected mode.
- Incremental file indexing and batched workspace scanning; closing the popup
  cancels further indexing/search work. Generated folders and binary files skipped.
- Bounded file/cursor navigation history, including restoring unsaved open tabs.
- Go menu and familiar shortcuts: Cmd+P files, Cmd+Shift+P commands,
  Ctrl+G line, Cmd+Shift+O file symbols, Cmd+T workspace symbols,
  Cmd+Shift+F quick text search, Ctrl+- Back, Ctrl+Shift+- Forward.
  Find and Replace moves to Cmd+Option+F; Open Folder remains in File menu.

Status: implemented, verification in progress. Symbol lookup is a declaration
scan for common language keywords, not semantic language-server navigation.
Workspace search uses explicit limits (20,000 filesystem entries, 2,000 scanned
files, 256 KiB disk files, 16 MiB text budget, 200 results); the popup reports
limited results. Full .gitignore semantics, regex search, AI chat, and VS Code
extension-provided search modes are not implemented.

## Icon and Find overlay (2026-10-25)

- Supplied `codebrain.png` artwork packaged as macOS app icon and 1024px Store
  asset; icon installed in the existing developer app.
- `make_icon.ks` rebuilds every icon size from the supplied artwork.
- One permanent Command Center box sits directly left of the top-right actions,
  vertically centered with their buttons.
- Find uses the same toolbar field. Only match count/navigation/case controls
  appear above the document; there is no additional Find search field or window.
  Find queries survive switching to commands and back. Replace expands on demand.
- Cmd+F focuses Find; Cmd+Option+F focuses replacement. Enter/Next/Previous
  navigate literal matches, with case toggle and Unicode-safe offsets.
- Replace and Replace All insert literal replacement text through the editor's
  normal editing path. Escape closes Find; Clear resets its query and closes it.

Full native regression verification remains in progress.

## File Info (2026-10-27)

- Collapsible right-hand pane follows the active file and unsaved editor contents.
- Explains likely purpose: entry point, header/interface, module, test, build or
  release automation, project manifest, configuration/data, documentation,
  template, stylesheet, or generated file.
- Shows classification evidence, language, UTF-8 size, line count for smaller
  files, imports/includes, declarations, and full path. Lists show up to eight
  entries and report additional recognized items.
- View → Toggle File Info and command palette action reopen or hide the pane.
- Local, non-executing source-pattern analysis; cached between content changes.
  Large-file analysis is limited to the first 131,072 UTF-16 units. No LSP or AI
  semantic summary is claimed; the pane labels its findings as inferred.
