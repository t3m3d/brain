import "stdlib/gui.k"
import "stdlib/io_utils.k"

let g_win    = ""
let g_area   = ""
let g_status = ""
let g_path   = ""

jxt {
    func krFileWrite(path, text) -> char_ptr
}

cfunc {
    #include <stdio.h>
    #include <string.h>

    char* krFileWrite(char* path, char* text) {
        if (!path || !*path) return (char*)"0";
        FILE* f = fopen(path, "wb");
        if (!f) return (char*)"0";
        size_t n = text ? strlen(text) : 0;
        size_t w = (n > 0) ? fwrite(text, 1, n, f) : 0;
        fclose(f);
        return (w == n) ? (char*)"1" : (char*)"0";
    }
}


func updateStatus() {
    if len(g_path) == 0 {
        guiStatusSet(g_status, 0, " (untitled)")
    } else {
        guiStatusSet(g_status, 0, " " + g_path)
    }
    guiStatusSet(g_status, 1, " UTF-8")
}


func onNew() {
    guiSetText(g_area, "")
    g_path = ""
    updateStatus()
}


func onOpen() {
    let p = guiOpenFile("Open File", "Krypton:*.k;*.krh,Text:*.txt;*.md,All:*.*")
    if len(p) > 0 {
        let content = readFileContent(p)
        guiSetText(g_area, content)
        g_path = p
        updateStatus()
    }
}


func onSaveAs() {
    let p = guiSaveFile("Save File", "Krypton:*.k;*.krh,Text:*.txt", "untitled.k")
    if len(p) > 0 {
        let text = guiGetText(g_area)
        let ok = krFileWrite(p, text)
        if ok == "1" {
            g_path = p
            updateStatus()
            guiStatusSet(g_status, 0, " saved: " + p)
        } else {
            guiMessageBox("kcode", "Could not save file:\n" + p)
        }
    }
}


func onSave() {
    if len(g_path) == 0 {
        onSaveAs()
    } else {
        let text = guiGetText(g_area)
        let ok = krFileWrite(g_path, text)
        if ok == "1" {
            guiStatusSet(g_status, 0, " saved: " + g_path)
        } else {
            guiMessageBox("kcode", "Could not save file:\n" + g_path)
        }
    }
}


func onQuit()  { guiQuit() }
func onAbout() {
    guiMessageBox("About kcode",
        "kcode — Krypton's portable code editor.\n" +
        "Built on stdlib/gui.k. Runs on Windows (Win32) and macOS (Cocoa).")
}


just run {
    guiInit()
    g_win = guiWindow("kcode", 820, 560)

    // ── Menu bar ──────────────────────────────────────────────
    let menu  = guiMenuBegin(g_win)
    let mFile = guiMenu(menu, "File")
    let mNew    = guiMenuItem(mFile, "New")
    let mOpen   = guiMenuItem(mFile, "Open...")
    guiMenuSeparator(mFile)
    let mSave   = guiMenuItem(mFile, "Save")
    let mSaveAs = guiMenuItem(mFile, "Save As...")
    guiMenuSeparator(mFile)
    let mQuit   = guiMenuItem(mFile, "Quit")

    let mHelp  = guiMenu(menu, "Help")
    let mAbout = guiMenuItem(mHelp, "About kcode")

    guiOnClick(mNew,    funcptr(onNew))
    guiOnClick(mOpen,   funcptr(onOpen))
    guiOnClick(mSave,   funcptr(onSave))
    guiOnClick(mSaveAs, funcptr(onSaveAs))
    guiOnClick(mQuit,   funcptr(onQuit))
    guiOnClick(mAbout,  funcptr(onAbout))

    // ── Toolbar — top-pinned button row ──────────────────────
    let tb = guiToolbar(g_win)
    let bNew  = guiToolButton(tb, "New",  "new")
    let bOpen = guiToolButton(tb, "Open", "open")
    guiToolSep(tb)
    let bSave = guiToolButton(tb, "Save", "save")
    guiOnClick(bNew,  funcptr(onNew))
    guiOnClick(bOpen, funcptr(onOpen))
    guiOnClick(bSave, funcptr(onSave))

    // ── Status bar — bottom-pinned, file path | encoding ─────
    g_status = guiStatusBar(g_win)
    guiStatusParts(g_status, "*,80")

    // ── Editor body — fills the middle, dock manager keeps it
    g_area = guiTextArea(g_win, 0, 36, 820, 460)

    let dock = guiDock(g_win)
    guiDockTop(dock,    tb,       36)
    guiDockBottom(dock, g_status, 24)
    guiDockFill(dock,   g_area)
    guiDockApply(dock)

    updateStatus()
    guiShow(g_win)
    guiRun()
}
