// Native Command Center: quick access providers share one popup and result model.
import "k:cocoa"
import "k:objc"

func ccGet(key) { emit cocoaGetAssocKey(appH(), "cc." + key) }
func ccSet(key, value) { cocoaSetAssocKey(appH(), "cc." + key, value)  emit 1 }
func ccField(item, key) { emit msg_1(item, "objectForKey:", nsString(key)) }
func ccText(item, key) { emit msg(ccField(item, key), "UTF8String") }
func ccPut(item, key, value) { msg_2(item, "setObject:forKey:", value, nsString(key))  emit 1 }
func ccClip(text, limit) {
  let value = nsString(text)
  if msg(value, "length") <= limit { emit text }
  let c = msg_1(value, "characterAtIndex:", limit - 1)
  if c >= 55296 && c <= 56319 { limit = limit - 1 }
  emit msg(msg_1(value, "substringToIndex:", limit), "UTF8String") + "…"
}
func ccItem(kind, title, path, line, column) {
  let item = msg(cls("NSMutableDictionary"), "dictionary")
  ccPut(item, "kind", nsString(kind))  ccPut(item, "title", nsString(title))
  ccPut(item, "path", nsString(path))  ccPut(item, "line", cocoaNumber(line))
  ccPut(item, "column", cocoaNumber(column))
  emit item
}
func ccPrefix(text) {
  if len(text) == 0 { emit "" }
  let first = substring(text, 0, 1)
  if first == ">" || first == "@" || first == "#" || first == ":" || first == "%" || first == "?" { emit first }
  emit ""
}
func ccNumber(text) {
  if len(text) == 0 || len(text) > 9 { emit 0 }
  let i = 0
  while i < len(text) {
    let c = charCode(substring(text, i, i + 1))
    if c < 48 || c > 57 { emit 0 }
    i = i + 1
  }
  emit toInt(text)
}
func ccLocation(text) {
  let parts = msg_1(nsString(text), "componentsSeparatedByString:", nsString(":"))
  if cocoaArrayCount(parts) < 1 || cocoaArrayCount(parts) > 2 { emit 0 }
  let line = ccNumber(msg(cocoaArrayGet(parts, 0), "UTF8String"))
  let column = 1
  if cocoaArrayCount(parts) == 2 { column = ccNumber(msg(cocoaArrayGet(parts, 1), "UTF8String")) }
  if line < 1 || column < 1 { emit 0 }
  emit ccItem("location", "", "", line, column)
}
func ccFileQuery(text) {
  ccSet("file-location", 0)
  let i = len(text) - 1
  while i >= 0 {
    if substring(text, i, i + 1) == ":" {
      let location = ccLocation(substring(text, i + 1, len(text)))
      if location != 0 {
        let head = substring(text, 0, i)
        let j = i - 1
        while j >= 0 && substring(text, j, j + 1) != ":" { j = j - 1 }
        if j >= 0 {
          let pair = ccLocation(substring(text, j + 1, len(text)))
          if pair != 0 { location = pair  head = substring(text, 0, j) }
        }
        ccSet("file-location", location)  emit head
      }
      emit text
    }
    i = i - 1
  }
  emit text
}
func ccLabel(path) {
  let root = msg(cocoaGetAssocKey(appH(), "brain.dir"), "UTF8String")
  if len(root) > 0 && startsWith(path, root + "/") { emit substring(path, len(root) + 1, len(path)) }
  emit path
}
func ccOpenIndex(path) {
  let paths = cocoaGetAssocKey(appH(), "brain.tabpaths")
  let i = 0
  while i < cocoaArrayCount(paths) {
    if msg(cocoaArrayGet(paths, i), "UTF8String") == path { emit i }
    i = i + 1
  }
  emit 0 - 1
}
func ccRead(path) {
  let index = ccOpenIndex(path)
  if index >= 0 {
    if index == curTabIdx() { emit msg(cocoaGetAssocKey(appH(), "brain.editor"), "string") }
    emit cocoaArrayGet(cocoaGetAssocKey(appH(), "brain.tabtexts"), index)
  }
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let attrs = msg_2(fm, "attributesOfItemAtPath:error:", nsString(path), 0)
  if msg_1(ccField(attrs, "NSFileType"), "isEqualToString:", nsString("NSFileTypeRegular")) == 0 { emit 0 }
  if msg(ccField(attrs, "NSFileSize"), "unsignedLongLongValue") > 262144 { ccSet("scan-limited", cocoaNumber(1))  emit 0 }
  let text = msg_3(cls("NSString"), "stringWithContentsOfFile:encoding:error:", nsString(path), 4, 0)
  if readableText(text) == 0 { emit 0 }
  emit text
}
func ccQueue(path) {
  let seen = ccGet("scan-seen")
  if seen != 0 && msg_1(seen, "containsObject:", nsString(path)) == 0 {
    msg_1(seen, "addObject:", nsString(path))
    cocoaArrayAdd(ccGet("scan-queue"), nsString(path))
  }
  emit 1
}
func ccStartIndex() {
  let app = appH()
  let root = msg(cocoaGetAssocKey(app, "brain.dir"), "UTF8String")
  ccSet("index-root", nsString(root))
  ccSet("index-visited", cocoaNumber(0))
  cocoaSetAssocKey(app, "brain.picker.limited", cocoaNumber(0))
  cocoaSetAssocKey(app, "brain.picker.source", cocoaArray())
  ccSet("enumerator", 0)
  if brainFlag("brain.workspace", 1) == 1 && len(root) > 0 {
    ccSet("enumerator", msg_1(msg(cls("NSFileManager"), "defaultManager"), "enumeratorAtPath:", nsString(root)))
  }
  emit 1
}
func ccIndexBatch() {
  let enumerator = ccGet("enumerator")
  if enumerator == 0 { emit 0 }
  let visited = cocoaNumberVal(ccGet("index-visited"))
  let count = 0
  while count < 64 && visited < 20000 {
    let item = msg(enumerator, "nextObject")
    if item == 0 { ccSet("enumerator", 0)  count = 64 }
    else {
      let attrs = msg(enumerator, "fileAttributes")
      let kind = ccField(attrs, "NSFileType")
      if msg_1(kind, "isEqualToString:", nsString("NSFileTypeDirectory")) == 1 {
        let name = msg(msg(item, "lastPathComponent"), "UTF8String")
        if name == ".git" || name == "node_modules" || name == ".hg" || name == ".svn" || name == ".venv" || name == "__pycache__" || endsWith(name, ".app") { msg(enumerator, "skipDescendants") }
      } else { if msg_1(kind, "isEqualToString:", nsString("NSFileTypeRegular")) == 1 {
        cocoaArrayAdd(cocoaGetAssocKey(appH(), "brain.picker.source"), item)
        let prefix = msg(ccGet("prefix"), "UTF8String")
        if prefix == "#" || prefix == "%" { ccQueue(msg(ccGet("index-root"), "UTF8String") + "/" + msg(item, "UTF8String")) }
      } }
      count = count + 1  visited = visited + 1
    }
  }
  ccSet("index-visited", cocoaNumber(visited))
  if visited >= 20000 {
    ccSet("enumerator", 0)
    cocoaSetAssocKey(appH(), "brain.picker.limited", cocoaNumber(1))
  }
  emit 1
}
func ccScore(label, query) {
  let value = msg(msg(nsString(label), "lowercaseString"), "UTF8String")
  query = msg(msg(nsString(query), "lowercaseString"), "UTF8String")
  if query == "" { emit 0 }
  let name = baseName(value)
  if name == query { emit 0 }
  if startsWith(name, query) { emit 1 }
  if indexOf(name, query) >= 0 { emit 2 }
  if indexOf(value, query) >= 0 { emit 3 }
  let i = 0  let j = 0
  while i < len(value) && j < len(query) {
    let c = substring(query, j, j + 1)
    if c == " " || c == "\t" { j = j + 1 }
    else { if substring(value, i, i + 1) == c { j = j + 1 }  i = i + 1 }
  }
  while j < len(query) && substring(query, j, j + 1) == " " { j = j + 1 }
  if j == len(query) { emit 4 }
  emit 0 - 1
}
func ccCandidates() {
  let result = cocoaArray()
  let seen = msg(cls("NSMutableSet"), "set")
  let app = appH()
  let paths = cocoaGetAssocKey(app, "brain.tabpaths")
  let i = cocoaArrayCount(paths) - 1
  while i >= 0 {
    let path = cocoaArrayGet(paths, i)
    if msg_1(seen, "containsObject:", path) == 0 { cocoaArrayAdd(result, path)  msg_1(seen, "addObject:", path) }
    i = i - 1
  }
  let defaults = msg(cls("NSUserDefaults"), "standardUserDefaults")
  let recent = msg_1(defaults, "arrayForKey:", nsString("brain.recent.files"))
  if ccGet("recent-override") != 0 { recent = ccGet("recent-override") }
  let fm = msg(cls("NSFileManager"), "defaultManager")
  i = 0
  while i < cocoaArrayCount(recent) {
    let path = cocoaArrayGet(recent, i)
    if msg_1(seen, "containsObject:", path) == 0 && msg_1(fm, "isReadableFileAtPath:", path) == 1 {
      cocoaArrayAdd(result, path)  msg_1(seen, "addObject:", path)
    }
    i = i + 1
  }
  let source = cocoaGetAssocKey(app, "brain.picker.source")
  let root = msg(ccGet("index-root"), "UTF8String")
  i = 0
  while i < cocoaArrayCount(source) {
    let path = nsString(root + "/" + msg(cocoaArrayGet(source, i), "UTF8String"))
    if msg_1(seen, "containsObject:", path) == 0 { cocoaArrayAdd(result, path)  msg_1(seen, "addObject:", path) }
    i = i + 1
  }
  emit result
}
func ccCommands() {
  let names = "File: New Text File|File: New Krypton File|File: New Window|File: Open File|File: Open Folder|File: Open Workspace|File: Save Workspace As|File: Duplicate Workspace|File: Save|File: Save As|File: Save All|File: Revert File|File: Close Editor|File: Close Window|Edit: Undo|Edit: Redo|Edit: Cut|Edit: Copy|Edit: Paste|Edit: Select All|Edit: Find|Edit: Find Next|Edit: Find Previous|Edit: Find and Replace|View: Toggle Sidebar|View: Zoom In|View: Zoom Out|View: Reset Zoom|Go: Quick Open|Go: Go to Line|Go: Symbol in File|Go: Symbol in Workspace|Go: Back|Go: Forward|Search: Quick Search|Extensions: Manage Extensions|Extensions: Add Extension from VSIX"
  if storeEdition() == 0 { names = names + "|View: Toggle Terminal|Run: Build File|Run: Run File|Run: Stop|GitHub: Source Control|GitHub: Sign In|GitHub: Refresh" }
  emit msg_1(nsString(names), "componentsSeparatedByString:", nsString("|"))
}
func ccRunCommand(name) {
  if name == "File: New Text File" { onNew(0, 0, 0) }
  if name == "File: New Krypton File" { onNewFile(0, 0, 0) }
  if name == "File: New Window" { onNewWindow(0, 0, 0) }
  if name == "File: Open File" { onOpen(0, 0, 0) }
  if name == "File: Open Folder" { onOpenFolder(0, 0, 0) }
  if name == "File: Open Workspace" { onOpenWorkspace(0, 0, 0) }
  if name == "File: Save Workspace As" { onSaveWorkspaceAs(0, 0, 0) }
  if name == "File: Duplicate Workspace" { onDupWorkspace(0, 0, 0) }
  if name == "File: Save" { onSave(0, 0, 0) }
  if name == "File: Save As" { onSaveAs(0, 0, 0) }
  if name == "File: Save All" { onSaveAll(0, 0, 0) }
  if name == "File: Revert File" { onRevert(0, 0, 0) }
  if name == "File: Close Editor" { onClose(0, 0, 0) }
  if name == "File: Close Window" { onCloseWindow(0, 0, 0) }
  let edit = ""
  if name == "Edit: Undo" { edit = "undo:" }
  if name == "Edit: Redo" { edit = "redo:" }
  if name == "Edit: Cut" { edit = "cut:" }
  if name == "Edit: Copy" { edit = "copy:" }
  if name == "Edit: Paste" { edit = "paste:" }
  if name == "Edit: Select All" { edit = "selectAll:" }
  if edit != "" { msg_3(appH(), "sendAction:to:from:", sel(edit), 0, 0) }
  let tag = 0
  if name == "Edit: Find" { tag = 1 }
  if name == "Edit: Find Next" { tag = 2 }
  if name == "Edit: Find Previous" { tag = 3 }
  if name == "Edit: Find and Replace" { tag = 12 }
  if tag > 0 {
    let sender = allocInit("NSMenuItem")
    msg_1(sender, "setTag:", tag)
    msg_3(appH(), "sendAction:to:from:", sel("performTextFinderAction:"), 0, sender)
    msg(sender, "release")
  }
  if name == "View: Toggle Sidebar" { onToggleSidebar(0, 0, 0) }
  if name == "View: Toggle Terminal" { onToggleTerminal(0, 0, 0) }
  if name == "View: Zoom In" { onZoomIn(0, 0, 0) }
  if name == "View: Zoom Out" { onZoomOut(0, 0, 0) }
  if name == "View: Reset Zoom" { onZoomReset(0, 0, 0) }
  if name == "Go: Quick Open" { pickerOpen(0) }
  if name == "Go: Go to Line" { ccOpen(":") }
  if name == "Go: Symbol in File" { ccOpen("@") }
  if name == "Go: Symbol in Workspace" { ccOpen("#") }
  if name == "Go: Back" { ccBack(0, 0, 0) }
  if name == "Go: Forward" { ccForward(0, 0, 0) }
  if name == "Search: Quick Search" { ccOpen("%") }
  if name == "Extensions: Manage Extensions" { onExtensions(0, 0, 0) }
  if name == "Extensions: Add Extension from VSIX" { onAddExtension(0, 0, 0) }
  if name == "Run: Build File" { onBuild(0, 0, 0) }
  if name == "Run: Run File" { onRun(0, 0, 0) }
  if name == "Run: Stop" { onStopTask(0, 0, 0) }
  if name == "GitHub: Source Control" { onSourceControl(0, 0, 0) }
  if name == "GitHub: Sign In" { scAuthenticate(0, 0, 0) }
  if name == "GitHub: Refresh" { scRefreshAccount(0, 0, 0) }
  emit 1
}
func ccPublish(results, reset) {
  let app = appH()
  let table = cocoaGetAssocKey(app, "brain.picker.table")
  let old = cocoaGetAssocKey(app, "brain.picker.results")
  let selected = msg(table, "selectedRow")
  let identity = 0
  if reset == 0 && selected >= 0 && selected < cocoaArrayCount(old) { identity = cocoaArrayGet(old, selected) }
  cocoaSetAssocKey(app, "brain.picker.results", results)
  cocoaReload(table)
  let row = 0
  if identity != 0 {
    let i = 0
    while i < cocoaArrayCount(results) {
      if msg_1(cocoaArrayGet(results, i), "isEqual:", identity) == 1 { row = i }
      i = i + 1
    }
  }
  if cocoaArrayCount(results) > 0 { msg_2(table, "selectRowIndexes:byExtendingSelection:", msg_1(cls("NSIndexSet"), "indexSetWithIndex:", row), 0) }
  let prefix = msg(ccGet("prefix"), "UTF8String")
  let detail = "Enter to open · ↑/↓ select · Esc close · ? modes"
  if prefix == ">" { detail = "Enter to run command · Esc close" }
  if prefix == ":" { detail = ":line[:column] · Enter to jump · Esc close" }
  if prefix == "@" { detail = "Declarations in current file · Enter to jump" }
  if prefix == "#" { detail = "Workspace declarations · Enter to jump" }
  if prefix == "%" { detail = "Literal text · Case insensitive · Enter to open match" }
  if cocoaArrayCount(results) == 0 { detail = "No results · " + detail }
  if ccGet("enumerator") != 0 { detail = "Indexing files… · " + detail }
  if (prefix == "#" || prefix == "%") && cocoaNumberVal(ccGet("scan-done")) == 0 { detail = "Searching… · " + detail }
  if prefix == "%" && len(trim(msg(ccGet("query"), "UTF8String"))) < 2 { detail = "Type at least two characters to search text" }
  if brainFlag("brain.picker.limited", 0) == 1 || cocoaNumberVal(ccGet("scan-limited")) == 1 || cocoaArrayCount(results) >= 200 { detail = "Results limited · " + detail }
  cocoaSetText(cocoaGetAssocKey(app, "brain.picker.detail"), detail)
  emit 1
}
func ccFiles(query, reset) {
  query = ccFileQuery(query)
  let candidates = ccCandidates()
  let groups = cocoaArray()
  let i = 0
  while i < 5 { cocoaArrayAdd(groups, cocoaArray())  i = i + 1 }
  i = 0
  while i < cocoaArrayCount(candidates) {
    let path = msg(cocoaArrayGet(candidates, i), "UTF8String")
    let label = ccLabel(path)
    let score = ccScore(label, query)
    if score >= 0 {
      let group = cocoaArrayGet(groups, score)
      if cocoaArrayCount(group) < 200 {
        let title = label
        if query == "" {
          if ccOpenIndex(path) >= 0 { title = "Open · " + label }
          else { title = "File · " + label }
        }
        let line = 0  let column = 1
        let location = ccGet("file-location")
        if location != 0 { line = cocoaNumberVal(ccField(location, "line"))  column = cocoaNumberVal(ccField(location, "column")) }
        cocoaArrayAdd(group, ccItem("file", title, path, line, column))
      }
    }
    i = i + 1
  }
  let results = cocoaArray()
  i = 0
  while i < 5 {
    let group = cocoaArrayGet(groups, i)
    let j = 0
    while j < cocoaArrayCount(group) && cocoaArrayCount(results) < 200 { cocoaArrayAdd(results, cocoaArrayGet(group, j))  j = j + 1 }
    i = i + 1
  }
  ccPublish(results, reset)
  emit 1
}
func ccSymbolRegex() {
  if ccGet("symbol-regex") == 0 {
    let pattern = "^[ \\t]*(?:(?:export|pub|public|private|static|async|local)\\s+)*(?:(?:func|fn|def|function|class|struct|enum|interface|trait|module|type|method|require)\\s+|objk\\s+(?:object|protocol)\\s+)([A-Za-z_$][A-Za-z0-9_$]*)"
    ccSet("symbol-regex", msg_3(cls("NSRegularExpression"), "regularExpressionWithPattern:options:error:", nsString(pattern), 0, 0))
  }
  emit ccGet("symbol-regex")
}
func ccScanText(path, text, query, symbols, results) {
  if msg(text, "length") > 262144 { ccSet("scan-limited", cocoaNumber(1))  emit 1 }
  let lines = msg_1(text, "componentsSeparatedByString:", nsString("\n"))
  let i = 0  let block = 0
  while i < cocoaArrayCount(lines) && i < 10000 && cocoaArrayCount(results) < 200 {
    let line = cocoaArrayGet(lines, i)
    let trimmed = msg_1(line, "stringByTrimmingCharactersInSet:", msg(cls("NSCharacterSet"), "whitespaceAndNewlineCharacterSet"))
    let value = msg(trimmed, "UTF8String")
    if symbols == 1 {
      if startsWith(value, "/*") { block = 1 }
      if block == 0 {
        let symbolMatch = msg_4(ccSymbolRegex(), "firstMatchInString:options:range:", line, 0, 0, msg(line, "length"))
        let name = ""
        if symbolMatch != 0 {
          let start = msg_1(symbolMatch, "rangeAtIndex:", 1)
          let tail = msg(msg_1(line, "substringFromIndex:", start), "UTF8String")
          let end = 0
          while end < len(tail) && (isIdentCh(charCode(substring(tail, end, end + 1))) == 1 || substring(tail, end, end + 1) == "$") { end = end + 1 }
          name = substring(tail, 0, end)
        }
        if symbolMatch != 0 && ccScore(name, query) >= 0 {
          cocoaArrayAdd(results, ccItem("symbol", ccClip(value, 100) + "  —  " + ccLabel(path) + ":" + (i + 1), path, i + 1, 1))
        }
      }
      if indexOf(value, "*/") >= 0 { block = 0 }
    } else {
      let start = 0
      let length = msg(line, "length")
      while start < length && cocoaArrayCount(results) < 200 {
        let tail = msg_1(line, "substringFromIndex:", start)
        let found = msg_2(tail, "rangeOfString:options:", nsString(query), 1)
        if found < 0 || found >= msg(tail, "length") { start = length }
        else {
          let column = start + found + 1
          cocoaArrayAdd(results, ccItem("match", ccLabel(path) + ":" + (i + 1) + ":" + column + "  " + ccClip(value, 100), path, i + 1, column))
          start = start + found + msg(nsString(query), "length")
        }
      }
    }
    i = i + 1
  }
  if i >= 10000 { ccSet("scan-limited", cocoaNumber(1)) }
  emit 1
}
func ccStartScan(prefix, query) {
  ccSet("scan-prefix", nsString(prefix))  ccSet("scan-query", nsString(query))
  ccSet("scan-queue", cocoaArray())  ccSet("scan-seen", msg(cls("NSMutableSet"), "set"))
  ccSet("scan-index", cocoaNumber(0))  ccSet("scan-bytes", cocoaNumber(0))
  ccSet("scan-done", cocoaNumber(0))  ccSet("scan-limited", cocoaNumber(0))
  ccSet("scan-due", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 0.15))
  let paths = cocoaGetAssocKey(appH(), "brain.tabpaths")
  let i = 0
  while i < cocoaArrayCount(paths) { ccQueue(msg(cocoaArrayGet(paths, i), "UTF8String"))  i = i + 1 }
  let source = cocoaGetAssocKey(appH(), "brain.picker.source")
  let root = msg(ccGet("index-root"), "UTF8String")
  i = 0
  while i < cocoaArrayCount(source) { ccQueue(root + "/" + msg(cocoaArrayGet(source, i), "UTF8String"))  i = i + 1 }
  ccPublish(cocoaArray(), 1)
  emit 1
}
func pickerRows(self, cmd, table) { emit cocoaArrayCount(cocoaGetAssocKey(appH(), "brain.picker.results")) }
func pickerValue(self, cmd, table, column, row) {
  let results = cocoaGetAssocKey(appH(), "brain.picker.results")
  if row < 0 || row >= cocoaArrayCount(results) { emit nsString("") }
  emit ccField(cocoaArrayGet(results, row), "title")
}
func pickerFilter() {
  let raw = msg(msg(cocoaGetAssocKey(appH(), "brain.picker.input"), "stringValue"), "UTF8String")
  let prefix = ccPrefix(raw)
  let query = raw
  if prefix != "" { query = substring(raw, 1, len(raw)) }
  query = trim(query)
  ccSet("prefix", nsString(prefix))  ccSet("query", nsString(query))
  cocoaSetAssocKey(appH(), "brain.picker.mode", cocoaNumber(0))
  if prefix == ">" { cocoaSetAssocKey(appH(), "brain.picker.mode", cocoaNumber(1)) }
  if prefix == "" { ccFiles(query, 1)  emit 1 }
  let results = cocoaArray()
  if prefix == ">" {
    let commands = ccCommands()
    let i = 0
    while i < cocoaArrayCount(commands) {
      let name = msg(cocoaArrayGet(commands, i), "UTF8String")
      if ccScore(name, query) >= 0 { cocoaArrayAdd(results, ccItem("command", name, "", 0, 0)) }
      i = i + 1
    }
  }
  if prefix == "?" {
    cocoaArrayAdd(results, ccItem("help", "Files · Type a name or path (file:line:column also works)", "", 0, 0))
    cocoaArrayAdd(results, ccItem("help", "> Commands · Run an editor action", ">", 0, 0))
    cocoaArrayAdd(results, ccItem("help", "@ Symbols · Declarations in current file", "@", 0, 0))
    cocoaArrayAdd(results, ccItem("help", "# Symbols · Declarations across workspace", "#", 0, 0))
    cocoaArrayAdd(results, ccItem("help", ": Line · Jump to line and optional column", ":", 0, 0))
    cocoaArrayAdd(results, ccItem("help", "% Text · Search workspace and unsaved buffers", "%", 0, 0))
  }
  if prefix == ":" {
    let location = ccLocation(query)
    let path = msg(cocoaGetAssocKey(appH(), "brain.curpath"), "UTF8String")
    if location != 0 && len(path) > 0 {
      let line = cocoaNumberVal(ccField(location, "line"))
      let column = cocoaNumberVal(ccField(location, "column"))
      cocoaArrayAdd(results, ccItem("line", "Go to line " + line + ", column " + column, path, line, column))
    }
  }
  if prefix == "@" {
    let path = msg(cocoaGetAssocKey(appH(), "brain.curpath"), "UTF8String")
    if len(path) > 0 { ccScanText(path, msg(cocoaGetAssocKey(appH(), "brain.editor"), "string"), query, 1, results) }
  }
  if prefix == "#" || prefix == "%" { ccStartScan(prefix, query)  emit 1 }
  ccPublish(results, 1)
  emit 1
}
func ccPoll() {
  let panel = cocoaGetAssocKey(appH(), "brain.picker.window")
  if panel == 0 || msg(panel, "isVisible") == 0 { emit 1 }
  let indexed = ccIndexBatch()
  let prefix = msg(ccGet("prefix"), "UTF8String")
  if prefix == "" && indexed == 1 { ccFiles(msg(ccGet("query"), "UTF8String"), 0) }
  if prefix != "#" && prefix != "%" { emit 1 }
  let query = msg(ccGet("scan-query"), "UTF8String")
  if prefix == "%" && len(query) < 2 { emit 1 }
  if msg_1(msg(cls("NSDate"), "date"), "compare:", ccGet("scan-due")) == 0 - 1 { emit 1 }
  let queue = ccGet("scan-queue")
  let index = cocoaNumberVal(ccGet("scan-index"))
  let results = cocoaGetAssocKey(appH(), "brain.picker.results")
  if cocoaArrayCount(results) >= 200 || index >= 2000 || cocoaNumberVal(ccGet("scan-bytes")) >= 16777216 {
    if cocoaNumberVal(ccGet("scan-done")) == 1 { emit 1 }
    ccSet("scan-done", cocoaNumber(1))  ccSet("scan-limited", cocoaNumber(1))
    ccPublish(results, 0)  emit 1
  }
  if index < cocoaArrayCount(queue) {
    let path = msg(cocoaArrayGet(queue, index), "UTF8String")
    let text = ccRead(path)
    if text != 0 {
      ccSet("scan-bytes", cocoaNumber(cocoaNumberVal(ccGet("scan-bytes")) + msg_1(text, "lengthOfBytesUsingEncoding:", 4)))
      let symbols = 0  if prefix == "#" { symbols = 1 }
      ccScanText(path, text, query, symbols, results)
    }
    ccSet("scan-index", cocoaNumber(index + 1))
    ccPublish(results, 0)
  } else { if ccGet("enumerator") == 0 && cocoaNumberVal(ccGet("scan-done")) == 0 {
    ccSet("scan-done", cocoaNumber(1))  ccPublish(results, 0)
  } }
  emit 1
}
func ccJump(line, column) {
  let editor = cocoaGetAssocKey(appH(), "brain.editor")
  let text = msg(editor, "string")
  let lines = msg_1(text, "componentsSeparatedByString:", nsString("\n"))
  if line < 1 { line = 1 }
  if line > cocoaArrayCount(lines) { line = cocoaArrayCount(lines) }
  let offset = 0  let i = 0
  while i < line - 1 { offset = offset + msg(cocoaArrayGet(lines, i), "length") + 1  i = i + 1 }
  let length = msg(cocoaArrayGet(lines, line - 1), "length")
  if length > 0 { if msg_1(cocoaArrayGet(lines, line - 1), "characterAtIndex:", length - 1) == 13 { length = length - 1 } }
  if column < 1 { column = 1 }
  if column > length + 1 { column = length + 1 }
  offset = offset + column - 1
  // Never place the caret between a UTF-16 surrogate pair.
  if offset > 0 && offset < msg(text, "length") {
    let c = msg_1(text, "characterAtIndex:", offset)
    if c >= 56320 && c <= 57343 { offset = offset - 1 }
  }
  msg_2(editor, "setSelectedRange:", offset, 0)
  msg_2(editor, "scrollRangeToVisible:", offset, 0)
  refreshEditorChrome()
  emit 1
}
func ccCapture() {
  let path = cocoaGetAssocKey(appH(), "brain.curpath")
  if path == 0 { emit 0 }
  let item = ccItem("history", "", msg(path, "UTF8String"), 0, 0)
  ccPut(item, "offset", cocoaNumber(msg(cocoaGetAssocKey(appH(), "brain.editor"), "selectedRange")))
  emit item
}
func ccHistoryUI() {
  let index = cocoaNumberVal(ccGet("history-index"))
  msg_1(ccGet("back"), "setEnabled:", index > 0)
  msg_1(ccGet("forward"), "setEnabled:", index + 1 < cocoaArrayCount(ccGet("history")))
  emit 1
}
func ccAppend(item) {
  if item == 0 { emit 1 }
  let history = ccGet("history")
  if history == 0 { history = cocoaArray()  ccSet("history", history)  ccSet("history-index", cocoaNumber(0 - 1)) }
  let index = cocoaNumberVal(ccGet("history-index"))
  if index >= 0 && index < cocoaArrayCount(history) {
    if msg_1(cocoaArrayGet(history, index), "isEqual:", item) == 1 { ccHistoryUI()  emit 1 }
  }
  while cocoaArrayCount(history) > index + 1 { cocoaArrayRemove(history, cocoaArrayCount(history) - 1) }
  cocoaArrayAdd(history, item)
  if cocoaArrayCount(history) > 100 { cocoaArrayRemove(history, 0) }
  ccSet("history-index", cocoaNumber(cocoaArrayCount(history) - 1))
  ccHistoryUI()
  emit 1
}
func ccRemember() {
  if cocoaNumberVal(ccGet("history-lock")) == 1 { emit 1 }
  let item = ccCapture()
  if item == 0 { emit 1 }
  let history = ccGet("history")
  let index = cocoaNumberVal(ccGet("history-index"))
  if history != 0 && index >= 0 && index < cocoaArrayCount(history) {
    let previous = cocoaArrayGet(history, index)
    if ccText(previous, "path") == ccText(item, "path") { cocoaArraySet(history, index, item)  ccHistoryUI()  emit 1 }
  }
  ccAppend(item)
  emit 1
}
func ccNavigate(path, line, column) {
  ccRemember()
  ccSet("history-lock", cocoaNumber(1))
  let index = ccOpenIndex(path)
  if index >= 0 { selectTab(index) } else { openTab(path) }
  if msg(cocoaGetAssocKey(appH(), "brain.curpath"), "UTF8String") == path { if line > 0 { ccJump(line, column) } }
  ccSet("history-lock", cocoaNumber(0))
  ccAppend(ccCapture())
  emit 1
}
func ccHistoryMove(delta) {
  ccRemember()
  let history = ccGet("history")
  let index = cocoaNumberVal(ccGet("history-index")) + delta
  while index >= 0 && index < cocoaArrayCount(history) {
    let item = cocoaArrayGet(history, index)
    let path = ccText(item, "path")
    if ccOpenIndex(path) >= 0 || msg_1(msg(cls("NSFileManager"), "defaultManager"), "isReadableFileAtPath:", nsString(path)) == 1 {
      ccSet("history-lock", cocoaNumber(1))
      let existing = ccOpenIndex(path)
      if existing >= 0 { selectTab(existing) } else { openTab(path) }
      let editor = cocoaGetAssocKey(appH(), "brain.editor")
      let offset = cocoaNumberVal(ccField(item, "offset"))
      let length = msg(msg(editor, "string"), "length")
      if offset > length { offset = length }
      msg_2(editor, "setSelectedRange:", offset, 0)
      msg_2(editor, "scrollRangeToVisible:", offset, 0)
      ccSet("history-index", cocoaNumber(index))  ccSet("history-lock", cocoaNumber(0))
      ccHistoryUI()  refreshEditorChrome()  emit 1
    }
    index = index + delta
  }
  ccHistoryUI()
  emit 1
}
func ccBack(self, cmd, sender) { ccHistoryMove(0 - 1) }
func ccForward(self, cmd, sender) { ccHistoryMove(1) }
func ccTitle() {
  let root = msg(cocoaGetAssocKey(appH(), "brain.dir"), "UTF8String")
  let title = "Search Brain  ⌘P"
  if brainFlag("brain.workspace", 0) == 1 { title = ccClip(baseName(root), 23) + "  ⌘P" }
  msg_1(ccGet("search-button"), "setTitle:", nsString(title))
  emit 1
}
func pickerClose() {
  msg_1(cocoaGetAssocKey(appH(), "brain.picker.window"), "orderOut:", 0)
  ccSet("enumerator", 0)  ccSet("scan-queue", 0)  ccSet("scan-seen", 0)
  let win = cocoaGetAssocKey(appH(), "brain.win")
  msg_1(win, "makeKeyAndOrderFront:", 0)
  cocoaMakeFirstResponder(win, cocoaGetAssocKey(appH(), "brain.editor"))
  emit 1
}
func pickerExecute(self, cmd, sender) {
  let results = cocoaGetAssocKey(appH(), "brain.picker.results")
  let row = msg(cocoaGetAssocKey(appH(), "brain.picker.table"), "selectedRow")
  if row < 0 || row >= cocoaArrayCount(results) { emit 1 }
  let item = cocoaArrayGet(results, row)
  msg_1(item, "retain")
  let kind = ccText(item, "kind")
  if kind == "help" {
    msg_1(cocoaGetAssocKey(appH(), "brain.picker.input"), "setStringValue:", ccField(item, "path"))
    pickerFilter()
    cocoaMakeFirstResponder(cocoaGetAssocKey(appH(), "brain.picker.window"), cocoaGetAssocKey(appH(), "brain.picker.input"))
  } else {
    pickerClose()
    if kind == "command" { ccRunCommand(ccText(item, "title")) }
    else { ccNavigate(ccText(item, "path"), cocoaNumberVal(ccField(item, "line")), cocoaNumberVal(ccField(item, "column"))) }
  }
  msg(item, "release")
  emit 1
}
func pickerChanged(self, cmd, notification) { pickerFilter() }
func pickerSelectorEquals(command, name) {
  let value = msg_1(cls("NSValue"), "valueWithPointer:", command)
  emit msg_1(value, "isEqual:", msg_1(cls("NSValue"), "valueWithPointer:", sel(name)))
}
func pickerCommand(self, cmd, control, textView, command) {
  if pickerSelectorEquals(command, "cancelOperation:") == 1 { pickerClose()  emit 1 }
  if pickerSelectorEquals(command, "insertNewline:") == 1 { pickerExecute(0, 0, 0)  emit 1 }
  let delta = 0
  if pickerSelectorEquals(command, "moveDown:") == 1 { delta = 1 }
  if pickerSelectorEquals(command, "moveUp:") == 1 { delta = 0 - 1 }
  if delta != 0 {
    let table = cocoaGetAssocKey(appH(), "brain.picker.table")
    let count = cocoaArrayCount(cocoaGetAssocKey(appH(), "brain.picker.results"))
    if count > 0 {
      let row = msg(table, "selectedRow") + delta
      if row < 0 { row = 0 }
      if row >= count { row = count - 1 }
      msg_2(table, "selectRowIndexes:byExtendingSelection:", msg_1(cls("NSIndexSet"), "indexSetWithIndex:", row), 0)
      msg_1(table, "scrollRowToVisible:", row)
    }
    emit 1
  }
  emit 0
}
func pickerWindowClose(self, cmd, window) { pickerClose()  emit 0 }
func pickerInit() {
  let app = appH()
  if cocoaGetAssocKey(app, "brain.picker.window") != 0 { emit 1 }
  let panel = msg_rect(msg(cls("NSPanel"), "alloc"), "initWithContentRect:styleMask:backing:defer:", 0, 0, 740, 430, 3, 2, 0)
  msg_1(panel, "setReleasedWhenClosed:", 0)
  msg_1(panel, "setTitle:", nsString("Command Center"))
  msg_1(panel, "setBackgroundColor:", themeSidebar())
  msg_1(panel, "setAppearance:", msg_1(cls("NSAppearance"), "appearanceNamed:", nsString("NSAppearanceNameDarkAqua")))
  msg_1(panel, "setCollectionBehavior:", 257)  msg_1(panel, "setLevel:", 3)
  let input = cocoaTextField(panel, 18, 374, 704, 34)
  cocoaSetFont(input, msg_d1(cls("NSFont"), "systemFontOfSize:", 15))
  cocoaSetBg(input, themeCanvas())  cocoaSetTextColor(input, themeText())
  msg_1(input, "setPlaceholderString:", nsString("Search files · > commands · @ symbols · : line · % text · ? help"))
  let table = cocoaTable(panel, 18, 50, 704, 312)
  msg_1(table, "setHeaderView:", 0)  msg_d1(table, "setRowHeight:", 28)
  msg_1(table, "setBackgroundColor:", themeCanvas())
  let columns = msg(table, "tableColumns")
  if cocoaArrayCount(columns) > 0 { msg_1(cocoaArrayGet(columns, 0), "setEditable:", 0) }
  themeSurface(msg(table, "enclosingScrollView"), themeCanvas(), 8)
  let detail = cocoaPlainLabel(panel, "", 18, 14, 704, 26)
  cocoaSetFont(detail, msg_d1(cls("NSFont"), "systemFontOfSize:", 11))
  cocoaSetTextColor(detail, cocoaRGB(164, 166, 174))
  let c = cocoaClassNew("BrainCommandCenterDelegate")
  cocoaClassAddMethod(c, "numberOfRowsInTableView:", funcptr(pickerRows), "q@:@")
  cocoaClassAddMethod(c, "tableView:objectValueForTableColumn:row:", funcptr(pickerValue), "@@:@@q")
  cocoaClassAddMethod(c, "controlTextDidChange:", funcptr(pickerChanged), "v@:@")
  cocoaClassAddMethod(c, "control:textView:doCommandBySelector:", funcptr(pickerCommand), "c@:@@:")
  cocoaClassAddMethod(c, "execute:", funcptr(pickerExecute), "v@:@")
  cocoaClassAddMethod(c, "windowShouldClose:", funcptr(pickerWindowClose), "c@:@")
  cocoaClassRegister(c)
  let delegate = cocoaNew(c)
  cocoaSetAssocKey(app, "brain.picker.delegate", delegate)
  cocoaSetDataSource(table, delegate)
  msg_1(input, "setDelegate:", delegate)  msg_1(panel, "setDelegate:", delegate)
  msg_1(table, "setTarget:", delegate)  msg_1(table, "setDoubleAction:", sel("execute:"))
  cocoaSetAssocKey(app, "brain.picker.window", panel)
  cocoaSetAssocKey(app, "brain.picker.input", input)
  cocoaSetAssocKey(app, "brain.picker.table", table)
  cocoaSetAssocKey(app, "brain.picker.detail", detail)
  emit 1
}
func ccOpen(prefix) {
  if cocoaGetAssocKey(appH(), "brain.promptwindow") != 0 { raiseActivePrompt()  emit 1 }
  pickerInit()
  ccStartIndex()
  ccSet("prefix", nsString(prefix))
  ccIndexBatch()
  msg_1(cocoaGetAssocKey(appH(), "brain.picker.input"), "setStringValue:", nsString(prefix))
  ccSet("scan-limited", cocoaNumber(0))
  pickerFilter()
  let panel = cocoaGetAssocKey(appH(), "brain.picker.window")
  msg(panel, "center")  cocoaShow(panel, appH())
  cocoaMakeFirstResponder(panel, cocoaGetAssocKey(appH(), "brain.picker.input"))
  emit 1
}
func pickerOpen(mode) { if mode == 1 { ccOpen(">") } else { ccOpen("") }  emit 1 }
func onQuickOpen(self, cmd, sender) { pickerOpen(0) }
func onCommandPalette(self, cmd, sender) { pickerOpen(1) }
func onGoLine(self, cmd, sender) { ccOpen(":") }
func onGoSymbol(self, cmd, sender) { ccOpen("@") }
func onWorkspaceSymbol(self, cmd, sender) { ccOpen("#") }
func onQuickSearch(self, cmd, sender) { ccOpen("%") }

func ccToolbar(self, identifier) {
  let item = msg_1(msg(cls("NSToolbarItem"), "alloc"), "initWithItemIdentifier:", identifier)
  msg_1(item, "setLabel:", nsString("Command Center"))
  msg_1(item, "setVisibilityPriority:", 1000)
  let holder = msg_frame(msg(cls("NSView"), "alloc"), "initWithFrame:", 0, 0, 308, 44)
  let back = msg_frame(msg(cls("NSButton"), "alloc"), "initWithFrame:", 0, 7, 28, 28)
  let forward = msg_frame(msg(cls("NSButton"), "alloc"), "initWithFrame:", 30, 7, 28, 28)
  let button = msg_frame(msg(cls("NSButton"), "alloc"), "initWithFrame:", 64, 7, 244, 28)
  let image = msg_2(cls("NSImage"), "imageWithSystemSymbolName:accessibilityDescription:", nsString("magnifyingglass"), nsString("Search"))
  msg_1(button, "setImage:", image)  msg_1(button, "setImagePosition:", 2)
  msg_1(button, "setContentTintColor:", themeToolbarPurple())
  msg_1(button, "setTarget:", self)  msg_1(button, "setAction:", sel("commandCenter:"))
  msg_1(button, "setToolTip:", nsString("Search files, commands, symbols and text (⌘P)"))
  msg_1(button, "setAccessibilityLabel:", nsString("Command Center"))
  cocoaSetFont(button, msg_d1(cls("NSFont"), "systemFontOfSize:", 12))
  cocoaSetButtonTextColor(button, themeText())
  let controls = cocoaArray()  cocoaArrayAdd(controls, back)  cocoaArrayAdd(controls, forward)
  let i = 0
  while i < 2 {
    let control = cocoaArrayGet(controls, i)
    let symbol = "arrow.left"  let action = "navigateBack:"  let label = "Go Back"
    if i == 1 { symbol = "arrow.right"  action = "navigateForward:"  label = "Go Forward" }
    msg_1(control, "setImage:", msg_2(cls("NSImage"), "imageWithSystemSymbolName:accessibilityDescription:", nsString(symbol), nsString(label)))
    msg_1(control, "setTitle:", nsString(""))  msg_1(control, "setBordered:", 0)
    msg_1(control, "setContentTintColor:", themeToolbarPurple())
    msg_1(control, "setTarget:", self)  msg_1(control, "setAction:", sel(action))
    msg_1(control, "setAccessibilityLabel:", nsString(label))  msg_1(control, "setToolTip:", nsString(label))
    msg_1(holder, "addSubview:", control)
    i = i + 1
  }
  msg_1(button, "setBordered:", 0)
  themeSurface(button, themeCanvas(), 6)
  msg_d1(msg(button, "layer"), "setBorderWidth:", 1)
  msg_1(msg(button, "layer"), "setBorderColor:", msg(cocoaRGB(72, 64, 87), "CGColor"))
  msg_1(holder, "addSubview:", button)
  msg_1(item, "setView:", holder)
  msg_d2(item, "setMinSize:", 308, 44)  msg_d2(item, "setMaxSize:", 308, 44)
  ccSet("back", back)  ccSet("forward", forward)  ccSet("search-button", button)
  ccHistoryUI()  ccTitle()
  emit item
}

func ccTestSearchIdle() {
  let steps = 0
  while (ccGet("enumerator") != 0 || cocoaNumberVal(ccGet("scan-done")) == 0) && steps < 3000 {
    ccPoll()  sleepUs(0, 8000)  steps = steps + 1
  }
  regressionAssert(steps < 3000, "Command Center indexing/search completes incrementally")
  emit 1
}
func commandCenterRegression(root) {
  regressionAssert(ccScore("source_control.k", "srctrl") >= 0, "File search accepts fuzzy subsequences")
  regressionAssert(ccScore("alpha.txt", "xyz") < 0, "Unmatched fuzzy query is rejected")
  regressionAssert(ccFileQuery("file.ks:12:3") == "file.ks", "File query separates line and column")
  regressionAssert(cocoaNumberVal(ccField(ccGet("file-location"), "line")) == 12 && cocoaNumberVal(ccField(ccGet("file-location"), "column")) == 3, "File line/column parsed exactly")
  regressionAssert(ccLocation("0") == 0 && ccLocation("2:no") == 0 && ccLocation("1:2:3") == 0, "Invalid line inputs rejected")
  let path = root + "/symbols café.k"
  writeDocument(path, nsString("// func fake() {}\n/*\nfunc hidden() {}\n*/\nobjk object Counter {\n  method tick() -> int = counterTick\n}\nfunc counterTick(runtime, self) { emit 1 }\njust run { print(\"🦋\") }\n"))
  openTab(path)
  ccOpen("@counterTick")
  regressionAssert(cocoaArrayCount(cocoaGetAssocKey(appH(), "brain.picker.results")) == 1, "Symbol names filter independently of callback bodies")
  pickerExecute(0, 0, 0)
  let editor = cocoaGetAssocKey(appH(), "brain.editor")
  let prefix = msg_1(msg(editor, "string"), "substringToIndex:", msg(editor, "selectedRange"))
  regressionAssert(cocoaArrayCount(msg_1(prefix, "componentsSeparatedByString:", nsString("\n"))) == 8, "Symbol activation jumps to declaration line")
  ccOpen("@hidden")
  regressionAssert(cocoaArrayCount(cocoaGetAssocKey(appH(), "brain.picker.results")) == 0, "Block-comment declarations excluded")
  pickerClose()
  cocoaTVSetString(editor, "café 🦋" + fromCharCode(13) + "\nsecond needle_cc_742 needle_cc_742" + fromCharCode(13) + "\nthird\n")
  ccJump(1, 7)
  regressionAssert(msg(editor, "selectedRange") == 5, "Line jump never splits a surrogate pair")
  ccJump(2, 8)
  regressionAssert(msg(editor, "selectedRange") == 16, "Line jump handles UTF-16 and CRLF")
  ccOpen("%needle_cc_742")
  ccTestSearchIdle()
  regressionAssert(cocoaArrayCount(cocoaGetAssocKey(appH(), "brain.picker.results")) == 2, "Text search includes all matches in unsaved current buffer")
  pickerExecute(0, 0, 0)
  regressionAssert(msg(editor, "selectedRange") == 16, "Text result opens exact UTF-16 match location")
  ccOpen("#counterTick")
  ccTestSearchIdle()
  regressionAssert(cocoaArrayCount(cocoaGetAssocKey(appH(), "brain.picker.results")) == 0, "Workspace symbols prefer unsaved text over stale disk text")
  pickerClose()
  ccSet("history", 0)
  ccRemember()
  ccNavigate(root + "/alpha.txt", 1, 1)
  ccBack(0, 0, 0)
  regressionAssert(msg(cocoaGetAssocKey(appH(), "brain.curpath"), "UTF8String") == path && msg(editor, "selectedRange") == 16, "Back restores file and cursor without losing unsaved text")
  ccForward(0, 0, 0)
  regressionAssert(msg(cocoaGetAssocKey(appH(), "brain.curpath"), "UTF8String") == root + "/alpha.txt", "Forward restores next file")
  ccBack(0, 0, 0)
  ccNavigate(root + "/nested/inside.txt", 1, 1)
  regressionAssert(cocoaNumberVal(ccGet("history-index")) + 1 == cocoaArrayCount(ccGet("history")), "New navigation drops stale forward branch")
  ccOpen("?")
  regressionAssert(cocoaArrayCount(cocoaGetAssocKey(appH(), "brain.picker.results")) == 6, "Help lists every supported search mode")
  msg_2(cocoaGetAssocKey(appH(), "brain.picker.table"), "selectRowIndexes:byExtendingSelection:", msg_1(cls("NSIndexSet"), "indexSetWithIndex:", 1), 0)
  pickerExecute(0, 0, 0)
  regressionAssert(startsWith(msg(msg(cocoaGetAssocKey(appH(), "brain.picker.input"), "stringValue"), "UTF8String"), ">"), "Help selection switches to command provider")
  pickerClose()
  print("PASS: Command Center fuzzy files, prefixes, symbols, Unicode/CRLF jumps, unsaved text search, help, Back/Forward")
  emit 1
}
