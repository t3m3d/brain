# brain

A native macOS code editor / IDE whose entire UI is **pure Krypton** on the
[objk](https://krypton-lang.org/objk.html) Objective-C FFI — no Obj-C, no Swift
source. A real Cocoa app (NSWindow, NSTextView, NSOutlineView, menus) driven by
Krypton functions used directly as Objective-C method IMPs.

## Features
- File-tree sidebar with directory navigation, multi-file tabs (with close ✕)
- Multi-language syntax highlighting (k/ks, js, ts, py, c, go, rs, sh, rb, json, …)
- A **real interactive terminal** pane (live zsh on a pty, the stem grid engine)
- File menu (New/Open/Open Folder/Open Recent/Save/Save As/Save All/Auto Save…),
  Edit (undo/redo/find/replace), View (toggle sidebar/terminal, font zoom), Run
- Native file/folder pickers, recent files/folders

## Install
```
brew install --cask t3m3d/krypton/brain
```

## Build from source
Needs a [Krypton](https://github.com/t3m3d/krypton) checkout (the toolchain):
```
KRYPTON=/path/to/krypton kr build.ks    # -> brain.app
```

Source of record: `brain.ks` (here). The older `gui_editor.m` is retained for reference; app builds use Objective K.

All build and install entry points are KryptScript (`.ks`), executed with `kr`
(or `kcc -r`). Run them from this checkout; set `KCODE_ROOT` when running
elsewhere. The installed macOS toolchain is used by default; `KRYPTON` selects an alternate checkout.

```
kr build_app.ks             # -> dist/brain.app (make-app.ks does the same)
kr install.ks               # -> ~/Applications/brain.app
kr install.ks /Applications # optional destination; must be writable
kr kcc.ks --version         # forwards to the installed native driver
```

`brain.icns` is optional. Build failures preserve the existing app. The editor
restores kcode's charcoal palette, native toolbar, split panes, blue active tabs,
line-number gutter, minimap, and cursor status through Objective K's Cocoa bindings.
The app menu includes Quit (⌘Q). The developer edition opens an embedded Stem
terminal below the editor, with a real zsh shell in the project folder. The purple
Terminal toolbar button or View → Toggle Terminal (⌘J) hides/shows it without
restarting the shell; the panel’s × button hides it too. Terminal text supports
selection/copy and ⌘V paste, including bracketed paste for terminal applications.
Resizing the window or divider updates the shell’s rows and columns while
preserving screen contents and terminal modes. Long lines scroll horizontally so gutter numbers stay
aligned. Explorer expands folders lazily and shows nested files. Quick Open (⌘P) searches
project paths; Command Palette (⌘⇧P) searches editor actions. New Text File
uses ⌘N. Both pickers support Enter, Escape, and arrow keys.

The developer edition includes GitHub and Source Control. The purple account box
at the bottom of Explorer starts browser sign-in or opens Source Control when
signed in. Install GitHub CLI (`gh`) to connect an account; an existing login is
reused, with credentials managed by GitHub CLI. Source Control shows changed files,
colored working/staged diffs, staging, staged-only commits, branches, fetch, push,
and fast-forward pull. Clone accepts a GitHub OWNER/REPO or HTTPS repository URL.
Repository, Pull Requests, and Issues open the corresponding GitHub browser pages.
Git operations run in the background and can be cancelled. Save modified editor
buffers before switching branches or pulling.

## Command Center

Click the toolbar search field or press **Cmd+P**. Type a file name
or path; fuzzy matching includes open/recent files. Use `file:line:column` to
open at a position. Prefixes switch modes in that same field; a results panel
contains matches without another search field:

| Prefix | Action |
|---|---|
| `>` | Find and run Brain commands (Cmd+Shift+P) |
| `@` | Find declarations in current buffer (Cmd+Shift+O) |
| `#` | Find declarations across workspace (Cmd+T) |
| `:` | Go to line and optional column (Ctrl+G) |
| `%` | Find literal text in workspace/open buffers (Cmd+Shift+F) |
| `?` | Show and select a search mode |

Use Enter to open/run, arrow keys to select, and Escape to close. Back/Forward
buttons restore previous files and cursor positions (Ctrl+- / Ctrl+Shift+-).
Search prefers unsaved buffers over disk contents. Indexing and scanning run
incrementally with limits reported in the popup. Symbol lookup scans common
language declarations; semantic language-server navigation is not included.
Cmd+F switches the same toolbar field to Find in the current file. Enter advances
matches; Escape returns it to file/command search. The Find query is remembered
when switching modes. Find and Replace uses Cmd+Option+F; Open Folder remains
available in File menu.

## File Info

The right-hand **File Info** pane explains the active file's likely role: main
program, header/interface, source module, test, build script, manifest, or other
document. It shows why that role was inferred, language, size/line count, imports,
declarations, and path. It follows tabs and unsaved edits. Close it with × and
reopen it with **View → Toggle File Info** or the command palette.

Analysis runs locally, never executes the file, and scans a bounded source prefix
for large files. Role descriptions are filename/source inferences, not semantic
or runtime verification.

## Extensions

Choose **Extensions → Manage Extensions…** in the macOS menu bar. The matching
charcoal popup lists imported VSIX packages and versions. **Add VSIX…** imports a
local package; **Remove** deletes the selected package after confirmation.
Importing the same publisher/name offers to replace its stored version.

Packages remain **Inactive**: Brain does not yet run the VS Code extension host
or apply VSIX grammars, snippets, and language servers. The manager stores each
archive intact under Application Support/brain/Extensions and reads only its
manifest. It never extracts or executes packaged code. Import runs in the
background; closing the popup cancels an unfinished import.

Feature inventory: [docs/FEATURES.md](docs/FEATURES.md).

## Release work

The Objective K app is a development preview. Release acceptance and remaining
issues are tracked in [docs/RELEASE_READINESS.md](docs/RELEASE_READINESS.md).

```
kr build.ks
brain.app/Contents/MacOS/brain --self-test # native regression checks; reliable exit status
kr build_store.ks              # sandboxed editor-only preview in dist/
```

The Store preview omits the terminal, external compiler, and Git/CLI integration. The full developer
edition remains available. Store previews use ad-hoc signing for local sandbox
testing; they are not signed archives suitable for App Store submission.

The `kr` wrapper currently masks native child exit codes. CI should invoke the
compiled app directly for regression checks, and compile release-check scripts
with `kcc --native release_check.ks -o /tmp/brain-release-check`, then run
`/tmp/brain-release-check`.

## App artwork

The supplied `codebrain.png` is the icon source. On macOS, run `kr make_icon.ks`
to regenerate `packaging/brain.icns` and `packaging/store-icon-1024.png`, then
build the app. The permanent Command Center sits directly left of the top-right
actions, aligned with their centers. Cmd+F switches that field to Find; only match
controls appear above the document. Escape ends Find. Replace expands on demand.

## Product roadmap

See [the feature roadmap](docs/ROADMAP.md) for the 25-feature plan, five product
pillars, local-first architecture, delivery phases, and acceptance gates.
