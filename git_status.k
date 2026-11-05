// Git working-tree decorations for the Explorer.
// Runs `git status` in the background; the UI loop polls it without blocking.
import "k:cocoa"
import "k:objc"

func gsGet(key) { emit cocoaGetAssocKey(appH(), "gs." + key) }
func gsSet(key, value) { cocoaSetAssocKey(appH(), "gs." + key, value)  emit "1" }
func gsText(key) {
  let value = gsGet(key)
  if value == 0 { emit "" }
  emit msg(value, "UTF8String")
}
func gsArgs() { emit cocoaArray() }
func gsArg(args, value) { cocoaArrayAdd(args, nsString(value))  emit "1" }

// 1 modified, 2 untracked, 3 ignored. Conflict/renamed/deleted all read as modified.
func gsKind(state) {
  if state == "??" { emit 2 }
  if state == "!!" { emit 3 }
  if len(state) == 0 || state == "  " { emit 0 }
  emit 1
}
func gsBadge(state) {
  if state == 2 { emit "U" }
  if state == 3 { emit "I" }
  if state == 1 { emit "M" }
  emit ""
}
func gsColor(state) {
  if state == 1 { emit cocoaRGB(226, 192, 141) } // VS Code dirty amber
  if state == 2 { emit cocoaRGB(115, 201, 145) } // untracked green
  if state == 3 { emit cocoaRGB(128, 117, 144) } // ignored, dimmer than muted text
  emit themeText()
}

func gsMark(map, path, state) {
  if msg(path, "length") == 0 { emit "1" }
  let old = msg_1(map, "objectForKey:", path)
  if old != 0 { if cocoaNumberVal(old) <= state { emit "1" } }
  msg_2(map, "setObject:forKey:", cocoaNumber(state), path)
  emit "1"
}
func gsMarkPath(map, root, relative, state) {
  let path = nsString(root + "/" + msg(relative, "UTF8String"))
  gsMark(map, path, state)
  // Tint the containing folders so collapsed trees still reveal work below.
  let parts = msg_1(relative, "componentsSeparatedByString:", nsString("/"))
  let prefix = root
  let i = 0
  while i < cocoaArrayCount(parts) - 1 {
    prefix = prefix + "/" + msg(cocoaArrayGet(parts, i), "UTF8String")
    gsMark(map, nsString(prefix), state)
    i = i + 1
  }
  emit "1"
}
// Porcelain v1 -z separates records with NUL. Scan UTF-16 units instead of
// building a one-byte NUL NSString, which is not a valid ObjC string bridge.
func gsSplitNul(text) {
  let entries = cocoaArray()
  let length = msg(text, "length")
  let start = 0
  let i = 0
  while i < length {
    if msg_1(text, "characterAtIndex:", i) == 0 {
      cocoaArrayAdd(entries, msg_2(text, "substringWithRange:", start, i - start))
      start = i + 1
    }
    i = i + 1
  }
  if start < length { cocoaArrayAdd(entries, msg_2(text, "substringWithRange:", start, length - start)) }
  emit entries
}
func gsMapFromEntries(entries, root) {
  let map = allocInit("NSMutableDictionary")
  let i = 0
  while i < cocoaArrayCount(entries) {
    let entry = cocoaArrayGet(entries, i)
    if msg(entry, "length") >= 4 {
      let state = gsKind(msg(msg_2(entry, "substringWithRange:", 0, 2), "UTF8String"))
      let path = msg_1(entry, "substringFromIndex:", 3)
      if state > 0 { gsMarkPath(map, root, path, state) }
      // Rename records carry the source path in the following NUL field.
      let code = msg(msg_2(entry, "substringWithRange:", 0, 2), "UTF8String")
      if indexOf(code, "R") >= 0 || indexOf(code, "C") >= 0 {
        i = i + 1
        if i < cocoaArrayCount(entries) {
          let old = cocoaArrayGet(entries, i)
          if msg(old, "length") > 0 { gsMarkPath(map, root, old, state) }
        }
      }
    }
    i = i + 1
  }
  emit map
}
func gsMapFor(text, root) {
  let entries = gsSplitNul(text)
  let map = gsMapFromEntries(entries, root)
  msg(entries, "release")
  emit map
}
func gsStateIn(map, path) {
  if map == 0 { emit 0 }
  let value = msg_1(map, "objectForKey:", nsString(path))
  if value == 0 { emit 0 }
  emit cocoaNumberVal(value)
}
func gsState(path) {
  let map = gsGet("map")
  if map == 0 { emit 0 }
  emit gsStateIn(map, path)
}
func gsReloadExplorer() {
  let table = cocoaGetAssocKey(appH(), "brain.table")
  if table != 0 { cocoaReload(table) }
  emit "1"
}

func gsReadOutput() {
  let attributes = msg_2(msg(cls("NSFileManager"), "defaultManager"), "attributesOfItemAtPath:error:", gsGet("log"), 0)
  let size = msg(msg_1(attributes, "objectForKey:", nsString("NSFileSize")), "unsignedLongLongValue")
  if size > 1048576 { emit 0 }
  let data = msg_1(cls("NSData"), "dataWithContentsOfFile:", gsGet("log"))
  if data == 0 { emit 0 }
  let text = msg_2(msg(cls("NSString"), "alloc"), "initWithData:encoding:", data, 4)
  if text == 0 { emit 0 }
  emit msg(text, "autorelease")
}
func gsCleanup() {
  let output = gsGet("output")
  if output != 0 { msg(output, "closeFile") }
  let temporary = gsGet("temporary")
  if temporary != 0 { msg_2(msg(cls("NSFileManager"), "defaultManager"), "removeItemAtPath:error:", temporary, 0) }
  gsSet("task", 0)  gsSet("output", 0)  gsSet("temporary", 0)  gsSet("log", 0)
  emit "1"
}
func gsLaunch(args, mode, directory) {
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let uuid = msg(msg(msg(cls("NSUUID"), "UUID"), "UUIDString"), "UTF8String")
  let temporary = msg(msg(msg(fm, "temporaryDirectory"), "path"), "UTF8String") + "/brain-status-" + uuid
  let permissions = allocInit("NSMutableDictionary")
  msg_2(permissions, "setObject:forKey:", cocoaNumber(448), nsString("NSFilePosixPermissions"))
  if msg_4(fm, "createDirectoryAtPath:withIntermediateDirectories:attributes:error:", nsString(temporary), 0, permissions, 0) == 0 {
    msg(permissions, "release")  emit 0
  }
  let log = temporary + "/output"
  msg_2(permissions, "setObject:forKey:", cocoaNumber(384), nsString("NSFilePosixPermissions"))
  msg_3(fm, "createFileAtPath:contents:attributes:", nsString(log), msg(cls("NSData"), "data"), permissions)
  msg(permissions, "release")
  let output = msg_1(cls("NSFileHandle"), "fileHandleForWritingAtPath:", nsString(log))
  if output == 0 { msg_2(fm, "removeItemAtPath:error:", nsString(temporary), 0)  emit 0 }
  let task = allocInit("NSTask")
  msg_1(task, "setExecutableURL:", msg_1(cls("NSURL"), "fileURLWithPath:", nsString("/usr/bin/git")))
  msg_1(task, "setArguments:", args)
  msg_1(task, "setCurrentDirectoryURL:", msg_1(cls("NSURL"), "fileURLWithPath:", nsString(directory)))
  msg_1(task, "setStandardOutput:", output)
  msg_1(task, "setStandardError:", output)
  let environment = msg(msg(msg(cls("NSProcessInfo"), "processInfo"), "environment"), "mutableCopy")
  msg_2(environment, "setObject:forKey:", nsString("0"), nsString("GIT_TERMINAL_PROMPT"))
  msg_2(environment, "setObject:forKey:", nsString("0"), nsString("GIT_OPTIONAL_LOCKS"))
  msg_2(environment, "setObject:forKey:", nsString("cat"), nsString("GIT_PAGER"))
  msg_1(task, "setEnvironment:", environment)
  msg(environment, "release")
  let input = msg(cls("NSPipe"), "pipe")
  msg_1(task, "setStandardInput:", input)
  msg(msg(input, "fileHandleForWriting"), "closeFile")
  if msg_1(task, "launchAndReturnError:", 0) == 0 {
    msg(task, "release")  msg(output, "closeFile")
    msg_2(fm, "removeItemAtPath:error:", nsString(temporary), 0)
    emit 0
  }
  gsSet("task", task)  gsSet("output", output)
  gsSet("temporary", nsString(temporary))  gsSet("log", nsString(log))
  gsSet("mode", nsString(mode))
  gsSet("deadline", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 20))
  gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 3))
  msg(task, "release")
  emit 1
}
func gsStartRoot(workspace) {
  let args = gsArgs()
  gsArg(args, "-C")  gsArg(args, workspace)
  gsArg(args, "rev-parse")  gsArg(args, "--show-toplevel")
  gsLaunch(args, "root", workspace)
  emit "1"
}
func gsStartStatus() {
  let root = gsText("root")
  if len(root) == 0 { emit 0 }
  let args = gsArgs()
  gsArg(args, "-C")  gsArg(args, root)
  gsArg(args, "-c")  gsArg(args, "core.quotepath=false")
  gsArg(args, "status")  gsArg(args, "--porcelain=v1")  gsArg(args, "-z")
  gsArg(args, "--untracked-files=all")  gsArg(args, "--ignored=matching")
  gsLaunch(args, "status", root)
  emit "1"
}
func gsReset() {
  let task = gsGet("task")
  if task != 0 {
    msg(task, "terminate")
    msg(task, "waitUntilExit")
  }
  gsCleanup()
  gsSet("map", 0)  gsSet("raw", 0)  gsSet("root", 0)  gsSet("workspace", 0)
  gsSet("due", 0)  gsSet("mode", 0)
  gsReloadExplorer()
  emit "1"
}
func gsRefresh(force) {
  if storeEdition() == 1 { emit "1" }
  let workspace = msg(cocoaGetAssocKey(appH(), "brain.dir"), "UTF8String")
  if len(workspace) == 0 { emit "1" }
  if gsGet("task") != 0 { gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 1))  emit "1" }
  let known = gsGet("workspace")
  if force == 1 || known == 0 || msg_1(known, "isEqualToString:", nsString(workspace)) == 0 {
    gsSet("workspace", nsString(workspace))
    gsSet("root", 0)  gsSet("raw", 0)  gsSet("map", 0)
    gsReloadExplorer()
    gsStartRoot(workspace)
    emit "1"
  }
  let root = gsGet("root")
  if root == 0 || msg(root, "length") == 0 {
    gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 10))
    emit "1"
  }
  gsStartStatus()
  emit "1"
}
func gsPoll() {
  let task = gsGet("task")
  if task == 0 { emit "1" }
  let now = msg(cls("NSDate"), "date")
  if msg(task, "isRunning") == 1 {
    if msg_1(now, "compare:", gsGet("deadline")) == 1 { msg(task, "terminate") }
    emit "1"
  }
  let status = msg(task, "terminationStatus")
  let mode = gsText("mode")
  let workspace = msg(cocoaGetAssocKey(appH(), "brain.dir"), "UTF8String")
  let output = gsReadOutput()
  gsCleanup()
  if output == 0 || status != 0 {
    if mode == "root" { gsSet("root", 0)  gsSet("map", 0)  gsSet("raw", 0)  gsReloadExplorer() }
    gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 10))
    emit "1"
  }
  let text = msg(output, "UTF8String")
  if mode == "root" {
    let root = trim(text)
    gsSet("root", nsString(root))
    if len(root) == 0 { gsSet("map", 0)  gsSet("raw", 0)  gsReloadExplorer()  gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 10))  emit "1" }
    gsStartStatus()
    emit "1"
  }
  if mode == "status" {
    let raw = gsGet("raw")
    if raw != 0 && msg_1(raw, "isEqualToString:", nsString(text)) == 1 {
      gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 3))
      emit "1"
    }
    gsSet("raw", nsString(text))
    let statusMap = gsMapFor(nsString(text), gsText("root"))
    gsSet("map", statusMap)
    msg(statusMap, "release")
    gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 3))
    gsReloadExplorer()
    emit "1"
  }
  gsSet("due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 3))
  emit "1"
}
func gsTick() {
  if storeEdition() == 1 { emit "1" }
  if gsGet("task") != 0 { gsPoll()  emit "1" }
  let due = gsGet("due")
  if due == 0 { gsRefresh(0)  emit "1" }
  let compared = msg_1(msg(cls("NSDate"), "date"), "compare:", due)
  if compared == 0 || compared == 1 { gsRefresh(0) }
  emit "1"
}

func gitStatusRegression() {
  regressionAssert(gsKind(" M") == 1 && gsKind("M ") == 1 && gsKind("A ") == 1, "Git modified states")
  regressionAssert(gsKind("??") == 2 && gsKind("!!") == 3 && gsKind("  ") == 0, "Git untracked, ignored, clean states")
  regressionAssert(gsBadge(1) == "M" && gsBadge(2) == "U" && gsBadge(3) == "I", "Git decoration badges")
  // Porcelain v1 -z record shape: `XY path`; a rename's source is the next record.
  let entries = cocoaArray()
  cocoaArrayAdd(entries, nsString(" M src/app.k"))
  cocoaArrayAdd(entries, nsString("?? notes/new.md"))
  cocoaArrayAdd(entries, nsString("!! build/out.o"))
  cocoaArrayAdd(entries, nsString("R  moved.txt"))
  cocoaArrayAdd(entries, nsString("old.txt"))
  let map = gsMapFromEntries(entries, "/repo")
  msg(entries, "release")
  regressionAssert(map != 0, "Git status map built")
  regressionAssert(gsStateIn(map, "/repo/src/app.k") == 1, "Git modified file path")
  regressionAssert(gsStateIn(map, "/repo/src") == 1, "Git modified folder path")
  regressionAssert(gsStateIn(map, "/repo/notes/new.md") == 2, "Git untracked file path")
  regressionAssert(gsStateIn(map, "/repo/build/out.o") == 3, "Git ignored file path")
  regressionAssert(gsStateIn(map, "/repo/moved.txt") == 1, "Git rename destination")
  regressionAssert(gsStateIn(map, "/repo/old.txt") == 1, "Git rename source")
  msg(map, "release")
  emit "1"
}
