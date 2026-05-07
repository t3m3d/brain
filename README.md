# kcode

krypton-lang's first IDE — a terminal editor written in Krypton, compiled via `kcc` to a single Mach-O binary.

## Build

```sh
./build.sh
```

Produces `./kcode` (≈170 KB on macOS arm64). Requires `kcc` 1.8.0+ on PATH.

## Run

```sh
./kcode                  # empty buffer in cwd
./kcode path/to/file.k   # open a file
```

## Run as a macOS app (.app bundle)

```sh
./make-app.sh            # produces dist/kcode.app
open dist/kcode.app      # double-clickable launch in Terminal.app
open dist/kcode.app src/buf.k    # opens with a file
cp -R dist/kcode.app /Applications/   # install
```

Right-click → Open With → kcode also works for `.k` files (the bundle
declares itself as a default editor for the `k` extension via
`CFBundleDocumentTypes`).  `lsregister` runs at the end of
`make-app.sh` to refresh Launch Services so this kicks in immediately.

## Key bindings

| keys                    | action                                            |
|-------------------------|---------------------------------------------------|
| ←/→ ↑/↓ Home/End        | cursor movement                                   |
| PageUp / PageDown       | jump-scroll                                       |
| **mouse click**         | position cursor at click (editor pane)            |
| **mouse wheel**         | scroll buffer 3 lines per tick                    |
| printable / Tab / Enter | insert (Tab → 4 spaces)                           |
| Backspace / Delete      | delete                                            |
| Ctrl-Z / Ctrl-Y         | undo / redo (per word — space/Enter ends a group) |
| Ctrl-S                  | save (prompts for path if buffer is unnamed)      |
| Ctrl-O                  | open file (prompts for path)                      |
| Ctrl-P                  | fuzzy file picker (recursive in cwd)              |
| **Alt-n / Alt-p**       | **cycle to next / previous open buffer**          |
| **Ctrl-W**              | **close current buffer**                          |
| Ctrl-F / Ctrl-G         | find / find next                                  |
| Ctrl-L                  | go to line                                        |
| Ctrl-B / Ctrl-R         | build / build+run via `kcc.sh`                    |
| Ctrl-Q                  | quit (warns on unsaved changes)                   |
| ESC                     | dismiss prompt, picker, or build overlay          |

The status bar shows `[i/N]` when more than one buffer is open.

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

## What's verified end-to-end

PTY-driven smoke tests confirm:

- **Open** via argv (`./kcode src/buf.k`) and via Ctrl-P fuzzy picker
  (filter narrows live; Enter opens).
- **Edit** — dirty marker (●) appears in status; Ctrl-Z restores both
  text and dirty flag (compares against last-saved text).
- **Save** — Ctrl-S writes to disk; verified by reading the file back.
- **Search** — Ctrl-F prompt jumps cursor to first match; Ctrl-G next.
- **Build** — Ctrl-B captures `kcc.sh`'s stderr+stdout in an overlay;
  errors show with the source file path in the title.
- **Build + run** — Ctrl-R compiles, executes, captures program stdout
  too, shows exit code.
- **Quit** — Ctrl-Q on a clean buffer exits in <100 ms; on a dirty
  buffer prompts "unsaved changes — quit anyway? (y/N)"; ESC cancels;
  `y<Enter>` exits cleanly.

## Known limitations (v0.1)

- **No tree pane.** The original `tree.k` worked in isolation but pushed the
  combined program past a kcc 1.8.0 emitter limit (around 2,200 lines of
  Krypton with the heavy use of `let` we had — deterministic crash with
  SIGSEGV in the codegen, see notes below). Replaced with the **Ctrl-P
  fuzzy file picker**, which covers most of what a tree gives you and is
  smaller code-wise.
- **No multi-buffer / tabs.** One buffer at a time.
- **No mouse support.**
- **UTF-8 cursor positioning.** Multi-byte codepoints round-trip through
  the buffer correctly but the cursor's screen column assumes 1 byte = 1
  column. Pure-ASCII files render perfectly; emoji / wide CJK will visually
  drift.
- **Multi-line `/* */` comments** aren't tracked across lines by the
  highlighter (single-line `//` comments are).
- **Buffer ops are O(file size)** — whole buffer is a single string,
  spliced on each keystroke. Fine up to a few hundred KB; would need
  a piece-table or rope for megabyte files.

## kcc workarounds embedded in this code

While building this, hit a few sharp edges in the C-path emitter:

1. **`structNew()` / `setField` / `getField`** don't resolve in the C-path
   on macOS — kcc emits `structnew_unknown()` which clang can't link.
   Replaced everywhere with `envNew` / `envSet` / `envGet`.
2. **Imports aren't transitive.** Every module a program reaches must be
   `import`ed from the entry file. So `main.k` imports `term.k`, `buf.k`,
   and `editor.k` even though `editor.k` already imports them itself.
3. **`shellRun(cmd)`'s docstring says "returns the captured stdout"**, but
   it actually returns `system(3)`'s encoded status (`exit_code << 8`) and
   the command's stdout goes straight to the inherited terminal. The
   `_shellCapture` helper in `editor.k` redirects to a temp file and
   reads it back.
4. **Program-size SIGSEGV.** Past ~2,200 lines of Krypton with our shape
   (lots of `let` bindings, a few imports), the emitter segfaults at
   parse / IR-emit time. Hard threshold; very sensitive to small changes.
   This is what cost us the tree pane. The fuzzy picker fits comfortably
   underneath.
5. **`\xNN` escapes** aren't valid in Krypton string literals (only
   `\\ \" \n \t \r`). Build ANSI escapes via `fromCharCode(27)`. Even
   `\r` is parsed as two characters (backslash + `r`) — likely a kcc
   tokenizer bug, since the spec lists it as supported.

## Termios gotcha (not Krypton — POSIX)

`tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)` on shutdown was hanging
indefinitely under some PTY conditions (the editor would print
"shutting down" but never actually exit). Switching to `TCSANOW`
fixed it. The hang was reproducible enough to break the dirty-quit
flow specifically — likely the FLUSH was waiting on input drain that
never completed because the input source was a closed PTY.
