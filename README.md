# kcode

A fast, native **macOS code editor / IDE** for the [Krypton language](https://krypton-lang.org) — and 80+ other languages. Built in Cocoa; the editor's *language* support is driven by real TextMate grammars (the same ones VS Code uses) and VS Code extensions.

## Install

```bash
brew tap t3m3d/krypton          # once
brew install --cask kcode       # clickable kcode.app in /Applications
```

Apple Silicon. The app is ad-hoc signed (not notarized); the installer strips the quarantine flag so it launches. If macOS still blocks it: System Settings → Privacy & Security → "Open Anyway".

## Features

- **80+ languages** — syntax highlighting via a built-in TextMate grammar engine + 84 bundled VS Code grammars (js/ts/py/go/rust/c/c++/java/html/css/json/yaml/sql/shell/markdown/…); cross-language embeds (HTML→JS/CSS, Markdown fences)
- **VS Code extensions** — bundles the Krypton extension for `.k/.ks/.htk`; **File → Install Extension** loads any `.vsix`
- **File-tree sidebar** — open folders, New File/Folder/Rename/Trash/Reveal, Copy Path
- **Editor tabs** — per-document undo/selection; ⌘⇧[ / ⌘⇧]
- **Command Palette** ⌘⇧P · **Quick Open** ⌘P · **Find in Files** ⌘⇧F · **Go to Line** ⌘L
- **Integrated terminal** ⌃\` — a real shell (the pure-Krypton kryoterm engine)
- **Git** — gutter diff markers (added/modified/deleted) + branch in the status bar
- **Minimap** — code overview, click/drag to scroll
- **Editing** — find & replace, auto-close brackets, auto-indent, bracket matching, current-line highlight, autocomplete ⌃Space, Toggle Comment ⌘/, Duplicate Line ⌘⇧D, Indent/Outdent ⌘]/⌘[
- **Build** ⌘B (`kcc`) · **Run** — runs in the integrated terminal via the right toolchain per language
- **Markdown preview** ⌘⇧V · **light/dark themes** · drag files to open · session restore (window + last folder) · Open Recent

## Build from source

```bash
./build_app.sh    # compiles gui_editor.m (Cocoa) + bundles grammars/engine -> kcode.app
```

The editor surface is Obj-C/Cocoa (`gui_editor.m`) — a deliberate, temporary bridge until the Krypton macho backend gains AppKit FFI (the **objk** work), at which point the GUI becomes pure Krypton. The Krypton compiler (`kcc`) and the integrated terminal engine are already pure Krypton.

A pure-Krypton terminal build (`build.sh` → `kcode` TUI) also exists for running inside any terminal.

## License

MIT — see [LICENSE](LICENSE).
