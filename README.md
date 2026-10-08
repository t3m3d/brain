# brain

A native macOS code editor / IDE whose entire UI is **pure Krypton** on the
[objk](https://krypton-lang.org/objk.html) Objective-C FFI — no Obj-C, no Swift
source. A real Cocoa app (NSWindow, NSTextView, NSTableView, menus) driven by
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
The app menu includes Quit (⌘Q); View → Toggle Terminal (⌘J) expands/collapses
and focuses the terminal. Long lines scroll horizontally so gutter numbers stay
aligned. The sidebar currently navigates one folder at a time.

## Release work

The Objective K app is a development preview. Release acceptance and remaining
issues are tracked in [docs/RELEASE_READINESS.md](docs/RELEASE_READINESS.md).

```
kr build.ks
kr tests/editor_regression.ks  # native document-model and Unicode regressions
kr build_store.ks              # sandboxed editor-only preview in dist/
```

The Store preview omits the terminal and external compiler. The full developer
edition remains available. Store previews use ad-hoc signing for local sandbox
testing; they are not signed archives suitable for App Store submission.
