// term.k — terminal driver: raw mode, key reading, window size, ANSI helpers.
//
// Lives in cfunc { } because Krypton's stdlib has line-buffered input only
// (`input()` reads to newline). A TUI editor needs single-keystroke reads,
// so we drop into termios + read(2).
//
// Public API:
//   tInit()            -> "1" on success; sets raw mode, alt screen, hides cursor
//   tRestore()         -> "1"; undo everything tInit did
//   tSize()            -> "rows,cols"
//   tReadKey()         -> token: "a", "ENTER", "TAB", "BACKSPACE", "ESC",
//                                 "UP", "DOWN", "LEFT", "RIGHT", "HOME", "END",
//                                 "PAGEUP", "PAGEDOWN", "DEL",
//                                 "C-a".."C-z", "M-x" (alt+letter), or "?" for unknown
//   tWrite(s)          -> raw bytes to stdout, no newline
//   tFlush()           -> flush stdout
//
// All other ANSI sequences are emitted by the renderer via tWrite().

module term

// Pure Krypton — no C. Raw mode is set with `stty` on the controlling terminal
// (/dev/tty); keys/output use the native fd builtins (fdRead/fdWrite). The engine
// gives kcode a real pty with a controlling tty, so /dev/tty resolves correctly
// whether kcode runs in Terminal.app or inside the kryoterm window shim.

func _ESC() { emit fromCharCode(27) }

// Strip trailing CR/LF/space from a captured string.
func _chomp(s) {
    let n = len(s)
    while n > 0 {
        let c = charCode(s[n - 1])
        if c == 10 || c == 13 || c == 32 || c == 9 { n = n - 1 }
        else { emit substring(s, 0, n) }
    }
    emit ""
}

// tInit — save current tty settings (to /tmp), drop to raw, enter alt screen,
// hide cursor, enable SGR mouse. Returns "1" on success, "0" if no tty.
func tInit() {
    let saved = exec("stty -g </dev/tty 2>/dev/null")
    if len(saved) < 2 { emit "0" }              // not a terminal
    writeFile("/tmp/kcode.stty", saved)
    shellRun("stty raw -echo </dev/tty 2>/dev/null")
    fdSetNonblock(0)                            // stdin: poll-driven reads (clean ESC timeout)
    let e = _ESC()
    let seq = e + "[?1049h" + e + "[?25l" + e + "[2J" + e + "[H" + e + "[?1000h" + e + "[?1006h"
    fdWrite(1, seq, len(seq))
    emit "1"
}

// tRestore — leave alt screen / show cursor / disable mouse, restore tty.
func tRestore() {
    let e = _ESC()
    let seq = e + "[?1006l" + e + "[?1000l" + e + "[?25h" + e + "[?1049l"
    fdWrite(1, seq, len(seq))
    let saved = _chomp(readFile("/tmp/kcode.stty"))
    if len(saved) > 1 { shellRun("stty " + saved + " </dev/tty 2>/dev/null") }
    else { shellRun("stty sane </dev/tty 2>/dev/null") }
    emit "1"
}

// tSize — "rows,cols" from `stty size` ("rows cols"); 24,80 fallback.
func tSize() {
    let s = _chomp(exec("stty size </dev/tty 2>/dev/null"))
    let sp = indexOf(s, " ")
    if sp > 0 {
        let rows = substring(s, 0, sp)
        let cols = substring(s, sp + 1, len(s))
        if toInt(rows) > 0 && toInt(cols) > 0 { emit rows + "," + cols }
    }
    emit "24,80"     // unsized pty / parse miss -> sane default (editor needs >0 rows)
}

func tWrite(s)  { fdWrite(1, s, len(s))  emit "1" }
func tFlush()   { emit "1" }                          // fdWrite is unbuffered — nothing to flush

// ── key input ───────────────────────────────────────────────────────────────
// stdin is non-blocking; we poll for the first byte, then grab any contiguous
// continuation bytes (the rest of an escape sequence arrives together).

// Wait up to ~250ms for a byte; return "" on timeout so the caller can re-render
// (the editor redraws on each tick -> picks up window resizes / first paint).
func _readBlocking() {
    let k = fdRead(0, 1)
    let waited = 0
    while len(k) == 0 && waited < 250 {
        sleepUs(0, 5000)                        // 5ms poll
        waited = waited + 5
        k = fdRead(0, 1)
    }
    emit k
}

// After ESC: wait up to ~40ms for continuation; if some arrives, drain the rest.
func _readMore() {
    let acc = ""
    let w = 0
    while w < 40 && len(acc) == 0 {
        acc = fdRead(0, 16)
        if len(acc) == 0 { sleepUs(0, 2000)  w = w + 2 }
    }
    let more = fdRead(0, 16)
    while len(more) > 0 { acc = acc + more  more = fdRead(0, 16) }
    emit acc
}

// Parse a CSI/SS3 body (everything after ESC) into a key token.
func _parseEsc(rest) {
    if len(rest) == 0 { emit "ESC" }
    let b1 = charCode(rest[0])
    let body = substring(rest, 1, len(rest))    // chars after '[' or 'O'
    if b1 == 91 || b1 == 79 {                   // '[' (CSI) or 'O' (SS3)
        if len(body) == 0 { emit "ESC" }
        let f = charCode(body[0])               // first body char
        if f == 65 { emit "UP" }
        if f == 66 { emit "DOWN" }
        if f == 67 { emit "RIGHT" }
        if f == 68 { emit "LEFT" }
        if f == 72 { emit "HOME" }
        if f == 70 { emit "END" }
        if f == 90 { emit "S-TAB" }
        if b1 == 79 && f >= 80 && f <= 83 { emit "F" + (f - 80 + 1) }   // SS3 F1..F4
        if f == 60 { emit _parseMouse(body) }   // '<' SGR mouse
        if f >= 48 && f <= 57 {                 // digits: CSI n ~
            let term = charCode(body[len(body) - 1])
            let digs = substring(body, 0, len(body) - 1)
            // strip any ';' modifier section — take leading number
            let semi = indexOf(digs, ";")
            if semi >= 0 { digs = substring(digs, 0, semi) }
            let n = toInt(digs)
            if term == 126 {                    // '~'
                if n == 1 || n == 7 { emit "HOME" }
                if n == 4 || n == 8 { emit "END" }
                if n == 3 { emit "DEL" }
                if n == 5 { emit "PAGEUP" }
                if n == 6 { emit "PAGEDOWN" }
                if n == 2 { emit "INS" }
                emit "CSI~" + n
            }
            emit "CSI" + digs + fromCharCode(term)
        }
        emit "CSI" + fromCharCode(f)
    }
    // ESC + printable = ALT-<char>
    if b1 >= 32 && b1 < 127 {
        let c = b1
        if c >= 65 && c <= 90 { c = c + 32 }
        emit "M-" + fromCharCode(c)
    }
    emit "ESC"
}

// SGR mouse body: "<btn;x;yM" (the leading '<' already consumed -> body = "btn;x;yM").
func _parseMouse(body) {
    let n = len(body)
    let term = charCode(body[n - 1])
    let nums = substring(body, 1, n - 1)        // drop leading '<' and trailing M/m
    let s1 = indexOf(nums, ";")
    if s1 < 0 { emit "MOUSE-UP" }
    let btn = toInt(substring(nums, 0, s1))
    let r2 = substring(nums, s1 + 1, len(nums))
    let s2 = indexOf(r2, ";")
    if s2 < 0 { emit "MOUSE-UP" }
    let mx = toInt(substring(r2, 0, s2))
    let my = toInt(substring(r2, s2 + 1, len(r2)))
    if mx > 0 { mx = mx - 1 }
    if my > 0 { my = my - 1 }
    if term == 109 { emit "MOUSE-UP" }          // 'm' release
    let low = btn - (btn / 4) * 4 + (btn / 64) * 64   // keep wheel/button low bits
    if btn == 64 { emit "WHEEL-UP" }
    if btn == 65 { emit "WHEEL-DOWN" }
    let bb = btn - (btn / 4) * 4
    let bs = "L"
    if bb == 1 { bs = "M" }
    if bb == 2 { bs = "R" }
    emit "MOUSE" + fromCharCode(9) + my + fromCharCode(9) + mx + fromCharCode(9) + bs
}

// tReadKey — one normalized key token (same vocabulary as before).
func tReadKey() {
    let k = _readBlocking()
    if len(k) == 0 { emit "" }                  // idle tick -> caller re-renders
    let b = charCode(k[0])
    if b == 27 { emit _parseEsc(_readMore()) }
    if b == 13 || b == 10 { emit "ENTER" }
    if b == 9 { emit "TAB" }
    if b == 127 || b == 8 { emit "BACKSPACE" }
    if b >= 1 && b <= 26 { emit "C-" + fromCharCode(96 + b) }   // C-a..C-z
    if b >= 32 && b < 127 { emit k[0] }                         // printable ASCII
    if b >= 128 {                                               // UTF-8 lead: gather the codepoint
        let more = 1
        if b >= 240 { more = 3 }
        else { if b >= 224 { more = 2 } }
        let buf = k
        while len(buf) <= more {
            let c = fdRead(0, 1)
            if len(c) == 0 { sleepUs(0, 1000) }
            else { buf = buf + c }
        }
        emit buf
    }
    emit "?" + b
}

// ── Entry: lives here so editor.k stays under the kcc 1.8.0 size threshold

func _dirOf(p) {
    let n = len(p)
    let i = n - 1
    while i >= 0 {
        if p[i] == "/" {
            if i == 0 { emit "/" }
            emit substring(p, 0, i)
        }
        i -= 1
    }
    emit "."
}

func kcodeMain() {
    let path = ""
    if argCount() >= 1 { path = arg(0) }
    let openFile = ""
    let treeRoot = "."
    if path != "" {
        // shellRun returns system(3)'s exit status; test -d returns 0 when path is a dir.
        if shellRun("test -d \"" + path + "\"") == "0" {
            treeRoot = path
        } else {
            openFile = path
            treeRoot = _dirOf(path)
        }
    }
    if tInit() != "1" {
        printErr("kcode: cannot enter raw mode (is stdin a tty?)")
        exit(1)
    }
    let e = edNew(openFile, treeRoot)
    e = _setMsg(e, "kcode — Ctrl-Q quit · Ctrl-S save · Ctrl-B build · Tab tree", "")
    e = edRun(e)
    tRestore()
    kp("")
    emit "1"
}
