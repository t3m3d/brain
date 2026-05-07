# kcode

krypton-lang's first IDE — a terminal editor written in Krypton, compiled via `kcc` to a single Mach-O binary.

## Build

```sh
./build.sh
```

Produces `./kcode` (≈140 KB on macOS arm64). Requires `kcc` 1.8.0+ on PATH.

## Run

```sh
./kcode                  # empty buffer in cwd
./kcode path/to/file.k   # open a file
```

## Key bindings

| keys                    | action                                       |
|-------------------------|----------------------------------------------|
| ←/→ ↑/↓ Home/End        | cursor movement                              |
| PageUp / PageDown       | jump-scroll                                  |
| printable / Tab / Enter | insert (Tab → 4 spaces)                      |
| Backspace / Delete      | delete                                       |
| Ctrl-Z / Ctrl-Y         | undo / redo                                  |
| Ctrl-S                  | save (prompts for path if buffer is unnamed) |
| Ctrl-O                  | open file (prompts for path)                 |
| Ctrl-F / Ctrl-G         | find / find next                             |
| Ctrl-L                  | go to line                                   |
| Ctrl-B / Ctrl-R         | build / build+run via `kcc.sh`               |
| Ctrl-Q                  | quit (warns on unsaved changes)              |
| ESC                     | dismiss prompt or build overlay              |

## Layout

```
src/
  term.k     — termios FFI (raw mode, key reading, ANSI), single-keystroke
               input via read(2) since the stdlib's input()/readLine() are
               line-buffered. Also hosts kcodeMain (the entry point).
  buf.k      — text buffer: cursor, scroll, insert/delete, save/load,
               snapshot-based undo/redo, forward/backward search.
  editor.k   — state container, ANSI renderer, .k syntax highlighter,
               minibuffer + prompts, build/run overlay, key dispatch,
               main loop.
  main.k     — `just run { kcodeMain() }`, single statement to dodge a
               kcc 1.8.0 codegen bug.
```

## Known limitations (v0.1)

- **No file tree pane.** Originally implemented as `tree.k` but had to be cut: with
  all the modules combined, the kcc 1.8.0 emitter segfaults on programs over a
  certain global complexity threshold. Will come back when kcc grows. The git
  history has the `tree.k` work if it's ever useful.
- **No multi-buffer / tabs.** One buffer at a time.
- **No mouse support.**
- **UTF-8 cursor positioning.** Multi-byte codepoints are stored and edited
  correctly but the cursor's screen column assumes 1 byte = 1 column.
- **Multi-line `/* */` comments** aren't tracked across lines by the highlighter.
- **Performance**: edit ops are O(file size) (the whole buffer is one string
  spliced on each keystroke). Fine up to a few hundred KB.
