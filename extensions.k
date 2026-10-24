// VSIX package management. Archives are stored intact; extension code is never run.
// Reading only package.json avoids extracting untrusted archive paths or binaries.
import "k:cocoa"
import "k:objc"

func exGet(key) { emit cocoaGetAssocKey(appH(), "extensions." + key) }
func exSet(key, value) { cocoaSetAssocKey(appH(), "extensions." + key, value)  emit 1 }
func exField(object, key) { emit msg_1(object, "objectForKey:", nsString(key)) }
func exString(object, key) {
  let value = exField(object, key)
  if msg_1(value, "isKindOfClass:", cls("NSString")) == 1 { emit msg(value, "UTF8String") }
  emit ""
}
func exMessage(text) { cocoaSetText(exGet("detail"), text)  emit 1 }
func exDirectory() {
  let override = exGet("test-root")
  if override != 0 { emit msg(override, "UTF8String") }
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let urls = msg_2(fm, "URLsForDirectory:inDomains:", 14, 1)
  emit msg(msg(msg(urls, "firstObject"), "path"), "UTF8String") + "/brain/Extensions"
}
func exIdentifier(value) {
  if len(value) < 1 || len(value) > 120 { emit 0 }
  if indexOf(value, "..") >= 0 { emit 0 }
  let i = 0
  while i < len(value) {
    let c = charCode(substring(value, i, i + 1))
    let letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    let digit = c >= 48 && c <= 57
    if letter == 0 && digit == 0 {
      if i == 0 || (c != 45 && c != 95 && c != 46) { emit 0 }
    }
    i = i + 1
  }
  emit 1
}
func exManifest(data) {
  if data == 0 || msg(data, "length") > 1048576 { emit 0 }
  let object = msg_3(cls("NSJSONSerialization"), "JSONObjectWithData:options:error:", data, 0, 0)
  if msg_1(object, "isKindOfClass:", cls("NSDictionary")) == 0 { emit 0 }
  if exIdentifier(exString(object, "publisher")) == 0 || exIdentifier(exString(object, "name")) == 0 { emit 0 }
  let version = exString(object, "version")
  if len(version) < 1 || len(version) > 64 { emit 0 }
  emit object
}
func exId(manifest) {
  emit msg(msg(nsString(exString(manifest, "publisher") + "." + exString(manifest, "name")), "lowercaseString"), "UTF8String")
}
func exTitle(manifest) {
  let title = exString(manifest, "displayName")
  if len(title) == 0 { title = exString(manifest, "name") }
  if len(title) > 100 { title = substring(title, 0, 100) }
  emit title
}
func exRows(self, cmd, table) { emit cocoaArrayCount(exGet("items")) }
func exValue(self, cmd, table, column, row) {
  let items = exGet("items")
  if row < 0 || row >= cocoaArrayCount(items) { emit nsString("") }
  let item = cocoaArrayGet(items, row)
  emit nsString(exTitle(item) + "   ·   " + exString(item, "version") + "   ·   Inactive")
}
func exSelected() {
  let row = msg(exGet("table"), "selectedRow")
  let items = exGet("items")
  if row < 0 || row >= cocoaArrayCount(items) { emit 0 }
  emit cocoaArrayGet(items, row)
}
func exSelection(self, cmd, notification) {
  let item = exSelected()
  msg_1(exGet("remove"), "setEnabled:", item != 0 && exGet("task") == 0)
  if exGet("task") != 0 { emit 1 }
  if item == 0 {
    let message = "No extensions added. Choose Add VSIX to import a package."
    if cocoaArrayCount(exGet("items")) > 0 { message = "Select an extension to see details or remove it." }
    exMessage(message + "\nVSIX features are not active in Brain yet.")
    emit 1
  }
  let description = exString(item, "description")
  if len(description) > 180 { description = substring(description, 0, 180) + "…" }
  exMessage(exId(item) + "\n" + description + "\nImported · Inactive — VS Code extension features are not supported yet.")
  emit 1
}
func exReload(selectedId) {
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let root = exDirectory()
  let names = msg_2(fm, "contentsOfDirectoryAtPath:error:", nsString(root), 0)
  names = msg_1(names, "sortedArrayUsingSelector:", sel("localizedStandardCompare:"))
  let items = cocoaArray()
  let selected = 0 - 1
  let i = 0
  while i < cocoaArrayCount(names) && i < 2000 {
    let name = msg(cocoaArrayGet(names, i), "UTF8String")
    if exIdentifier(name) == 1 {
      let data = msg_1(cls("NSData"), "dataWithContentsOfFile:", nsString(root + "/" + name + "/manifest.json"))
      let item = exManifest(data)
      if item != 0 { if exId(item) == name {
        if name == selectedId { selected = cocoaArrayCount(items) }
        cocoaArrayAdd(items, item)
      } }
    }
    i = i + 1
  }
  exSet("items", items)
  msg(exGet("table"), "reloadData")
  if selected >= 0 {
    msg_2(exGet("table"), "selectRowIndexes:byExtendingSelection:", msg_1(cls("NSIndexSet"), "indexSetWithIndex:", selected), 0)
  }
  exSelection(0, 0, 0)
  emit 1
}
func exDiscardStage() {
  let stage = exGet("stage")
  if stage != 0 { msg_2(msg(cls("NSFileManager"), "defaultManager"), "removeItemAtPath:error:", stage, 0) }
  exSet("stage", 0)
  emit 1
}
func exConfirm(title, detail, action) {
  let alert = allocInit("NSAlert")
  msg_1(alert, "setMessageText:", nsString(title))
  msg_1(alert, "setInformativeText:", nsString(detail))
  msg_1(alert, "addButtonWithTitle:", nsString(action))
  msg_1(alert, "addButtonWithTitle:", nsString("Cancel"))
  let response = runBrainAlert(alert)
  msg(alert, "release")
  msg_1(exGet("window"), "makeKeyAndOrderFront:", 0)
  emit response == 1000
}
func exCommit(data) {
  let item = exManifest(data)
  if item == 0 { exDiscardStage()  exMessage("Invalid VSIX: package.json needs a publisher, name, and version.")  emit 0 }
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let identifier = exId(item)
  let target = exDirectory() + "/" + identifier
  let stage = msg(exGet("stage"), "UTF8String")
  if msg_2(data, "writeToFile:atomically:", nsString(stage + "/manifest.json"), 1) == 0 {
    exDiscardStage()  exMessage("Could not save extension metadata.")  emit 0
  }
  let backup = ""
  if msg_1(fm, "fileExistsAtPath:", nsString(target)) == 1 {
    if exConfirm("Replace extension?", exTitle(item) + " is already installed. Replace its stored package with version " + exString(item, "version") + "?", "Replace") == 0 {
      exDiscardStage()  exMessage("Import cancelled. Existing extension kept.")  emit 0
    }
    backup = stage + "-previous"
    if msg_3(fm, "moveItemAtPath:toPath:error:", nsString(target), nsString(backup), 0) == 0 {
      exDiscardStage()  exMessage("Could not replace existing extension.")  emit 0
    }
  }
  if msg_3(fm, "moveItemAtPath:toPath:error:", nsString(stage), nsString(target), 0) == 0 {
    if backup != "" { msg_3(fm, "moveItemAtPath:toPath:error:", nsString(backup), nsString(target), 0) }
    exDiscardStage()  exMessage("Could not install extension package.")  emit 0
  }
  exSet("stage", 0)
  if backup != "" { msg_2(fm, "removeItemAtPath:error:", nsString(backup), 0) }
  exReload(identifier)
  emit 1
}
func exBeginImport(path) {
  if exGet("task") != 0 { exMessage("Import running. Wait or close this window to cancel.")  emit 0 }
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let attributes = msg_2(fm, "attributesOfItemAtPath:error:", nsString(path), 0)
  let kind = exField(attributes, "NSFileType")
  let size = msg(exField(attributes, "NSFileSize"), "unsignedLongLongValue")
  if msg_1(kind, "isEqualToString:", nsString("NSFileTypeRegular")) == 0 || size < 22 || size > 104857600 || extOf(path) != "vsix" {
    exMessage("Choose a valid .vsix file, up to 100 MiB.")  emit 0
  }
  let root = exDirectory()
  if msg_4(fm, "createDirectoryAtPath:withIntermediateDirectories:attributes:error:", nsString(root), 1, 0, 0) == 0 {
    exMessage("Could not create the extension storage folder.")  emit 0
  }
  let uuid = msg(msg(msg(cls("NSUUID"), "UUID"), "UUIDString"), "UTF8String")
  let stage = root + "/.import-" + uuid
  if msg_4(fm, "createDirectoryAtPath:withIntermediateDirectories:attributes:error:", nsString(stage), 0, 0, 0) == 0 {
    exMessage("Could not prepare extension import.")  emit 0
  }
  exSet("stage", nsString(stage))
  if msg_3(fm, "copyItemAtPath:toPath:error:", nsString(path), nsString(stage + "/package.vsix"), 0) == 0 {
    exDiscardStage()  exMessage("Could not read the selected extension.")  emit 0
  }
  let task = allocInit("NSTask")
  let pipe = msg(cls("NSPipe"), "pipe")
  let args = cocoaArray()
  cocoaArrayAdd(args, nsString("-p"))
  cocoaArrayAdd(args, nsString(stage + "/package.vsix"))
  cocoaArrayAdd(args, nsString("extension/package.json"))
  msg_1(task, "setExecutableURL:", msg_1(cls("NSURL"), "fileURLWithPath:", nsString("/usr/bin/unzip")))
  msg_1(task, "setArguments:", args)
  msg_1(task, "setStandardOutput:", pipe)
  msg_1(task, "setStandardError:", msg(cls("NSFileHandle"), "fileHandleWithNullDevice"))
  msg_1(task, "setStandardInput:", msg(cls("NSFileHandle"), "fileHandleWithNullDevice"))
  if msg_1(task, "launchAndReturnError:", 0) == 0 {
    msg(task, "release")  exDiscardStage()  exMessage("Could not read VSIX package.")  emit 0
  }
  let handle = msg(pipe, "fileHandleForReading")
  fdSetNonblock(msg(handle, "fileDescriptor"))
  exSet("task", task)  exSet("pipe", pipe)  exSet("handle", handle)
  exSet("data", msg(cls("NSMutableData"), "data"))
  exSet("deadline", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 15))
  exSet("failed", cocoaNumber(0))
  msg(task, "release")
  msg_1(exGet("add"), "setEnabled:", 0)
  msg_1(exGet("remove"), "setEnabled:", 0)
  exMessage("Reading extension package…")
  emit 1
}
func exPoll() {
  let task = exGet("task")
  if task == 0 { emit 1 }
  let data = exGet("data")
  let chunk = fdRead(msg(exGet("handle"), "fileDescriptor"), 65536)
  if len(chunk) > 0 {
    if msg(data, "length") + len(chunk) > 1048576 {
      exSet("failed", cocoaNumber(1))  msg(task, "terminate")
    } else { msg_2(data, "appendBytes:length:", chunk, len(chunk)) }
    emit 1
  }
  if msg(task, "isRunning") == 1 {
    if msg_1(msg(cls("NSDate"), "date"), "compare:", exGet("deadline")) == 1 {
      exSet("failed", cocoaNumber(1))  msg(task, "terminate")
    }
    emit 1
  }
  let status = msg(task, "terminationStatus")
  msg(exGet("handle"), "closeFile")
  exSet("task", 0)  exSet("pipe", 0)  exSet("handle", 0)
  msg_1(exGet("add"), "setEnabled:", 1)
  if status != 0 || cocoaNumberVal(exGet("failed")) == 1 {
    exDiscardStage()  exSelection(0, 0, 0)
    exMessage("Could not import VSIX. Archive is invalid, too large, or missing extension/package.json.")
  } else { exCommit(data) }
  exSet("data", 0)
  emit 1
}
func exAdd(self, cmd, sender) {
  if exGet("task") != 0 { emit 1 }
  let panel = msg(cls("NSOpenPanel"), "openPanel")
  msg_1(panel, "setCanChooseDirectories:", 0)
  msg_1(panel, "setCanChooseFiles:", 1)
  msg_1(panel, "setAllowsMultipleSelection:", 0)
  let types = cocoaArray()  cocoaArrayAdd(types, nsString("vsix"))
  msg_1(panel, "setAllowedFileTypes:", types)
  msg_1(panel, "setTitle:", nsString("Add Extension"))
  msg_1(panel, "setPrompt:", nsString("Add VSIX"))
  let result = runBrainPanel(panel)
  msg_1(exGet("window"), "makeKeyAndOrderFront:", 0)
  if result == 1 {
    let url = msg(panel, "URL")
    let accessing = msg(url, "startAccessingSecurityScopedResource")
    exBeginImport(msg(msg(url, "path"), "UTF8String"))
    if accessing == 1 { msg(url, "stopAccessingSecurityScopedResource") }
  }
  emit 1
}
func exDelete(identifier) {
  if exIdentifier(identifier) == 0 { emit 0 }
  let ok = msg_2(msg(cls("NSFileManager"), "defaultManager"), "removeItemAtPath:error:", nsString(exDirectory() + "/" + identifier), 0)
  exReload("")
  emit ok
}
func exRemove(self, cmd, sender) {
  if exGet("task") != 0 { emit 1 }
  let item = exSelected()
  if item == 0 { exMessage("Select an extension to remove.")  emit 1 }
  let identifier = exId(item)
  if exConfirm("Remove extension?", "Remove " + exTitle(item) + " and its stored VSIX package from Brain?", "Remove") == 1 {
    if exDelete(identifier) == 0 { exMessage("Could not remove extension. Check folder permissions.") }
  }
  emit 1
}
func exClose(self, cmd, sender) {
  let task = exGet("task")
  if task != 0 { exSet("failed", cocoaNumber(1))  msg(task, "terminate") }
  msg_1(exGet("window"), "orderOut:", 0)
  emit 1
}
func exWindowClose(self, cmd, window) { exClose(self, cmd, window)  emit 0 }
func exButton(window, title, x, width, action, key) {
  let button = cocoaButton(window, title, x, 20, width, 32)
  msg_1(button, "setBezelStyle:", 1)
  cocoaSetFont(button, msg_d1(cls("NSFont"), "systemFontOfSize:", 13))
  cocoaOnClickKeyed(button, "extensions-" + key, action)
  emit button
}
func exInit() {
  if exGet("window") != 0 { emit 1 }
  let window = msg_rect(msg(cls("NSPanel"), "alloc"), "initWithContentRect:styleMask:backing:defer:", 0, 0, 660, 440, 15, 2, 0)
  msg_1(window, "setReleasedWhenClosed:", 0)
  msg_1(window, "setTitle:", nsString("Extensions"))
  msg_1(window, "setBackgroundColor:", themeSidebar())
  msg_1(window, "setAppearance:", msg_1(cls("NSAppearance"), "appearanceNamed:", nsString("NSAppearanceNameDarkAqua")))
  cocoaSetWindowMinSize(window, 660, 468)
  let header = cocoaPlainLabel(window, "Extensions", 24, 386, 610, 30)
  cocoaSetFont(header, msg_d1(cls("NSFont"), "boldSystemFontOfSize:", 21))
  cocoaSetTextColor(header, themeText())
  msg_1(header, "setAutoresizingMask:", 10)
  let subtitle = cocoaPlainLabel(window, "Add and remove VSIX packages for Brain", 24, 360, 610, 22)
  cocoaSetTextColor(subtitle, cocoaRGB(164, 166, 174))
  msg_1(subtitle, "setAutoresizingMask:", 10)
  let table = cocoaTable(window, 24, 154, 612, 194)
  msg_1(table, "setHeaderView:", 0)
  msg_d1(table, "setRowHeight:", 34)
  msg_1(table, "setBackgroundColor:", themeCanvas())
  themeSurface(msg(table, "enclosingScrollView"), themeCanvas(), 8)
  msg_1(msg(table, "enclosingScrollView"), "setAutoresizingMask:", 18)
  let columns = msg(table, "tableColumns")
  if cocoaArrayCount(columns) > 0 { msg_d1(cocoaArrayGet(columns, 0), "setWidth:", 600) }
  let detail = cocoaPlainLabel(window, "", 24, 65, 612, 78)
  msg_1(msg(detail, "cell"), "setWraps:", 1)
  cocoaSetFont(detail, msg_d1(cls("NSFont"), "systemFontOfSize:", 12))
  cocoaSetTextColor(detail, themeText())
  msg_1(detail, "setAutoresizingMask:", 2)
  let add = exButton(window, "Add VSIX…", 24, 150, funcptr(exAdd), "add")
  cocoaSetButtonTextColor(add, cocoaRGB(255, 255, 255))
  msg_1(add, "setBezelColor:", themeToolbarPurple())
  let remove = exButton(window, "Remove", 186, 126, funcptr(exRemove), "remove")
  let done = exButton(window, "Done", 536, 100, funcptr(exClose), "done")
  msg_1(done, "setKeyEquivalent:", nsString(fromCharCode(27)))
  msg_1(done, "setAutoresizingMask:", 1)
  let c = cocoaClassNew("BrainExtensionsDelegate")
  cocoaClassAddMethod(c, "numberOfRowsInTableView:", funcptr(exRows), "q@:@")
  cocoaClassAddMethod(c, "tableView:objectValueForTableColumn:row:", funcptr(exValue), "@@:@@q")
  cocoaClassAddMethod(c, "tableViewSelectionDidChange:", funcptr(exSelection), "v@:@")
  cocoaClassAddMethod(c, "windowShouldClose:", funcptr(exWindowClose), "c@:@")
  cocoaClassRegister(c)
  let delegate = cocoaNew(c)
  exSet("window", window)  exSet("table", table)  exSet("detail", detail)
  exSet("add", add)  exSet("remove", remove)  exSet("delegate", delegate)
  cocoaSetDataSource(table, delegate)
  msg_1(table, "setDelegate:", delegate)
  msg_1(window, "setDelegate:", delegate)
  msg(window, "center")
  emit 1
}
func onExtensions(self, cmd, sender) {
  exInit()
  if exGet("task") == 0 { exReload("") }
  msg_1(exGet("window"), "makeKeyAndOrderFront:", 0)
  emit 1
}
func onAddExtension(self, cmd, sender) { onExtensions(self, cmd, sender)  exAdd(self, cmd, sender)  emit 1 }

// Regression mode uses isolated storage and real ZIP reads, never user packages.
func exTestIdle() {
  let steps = 0
  while exGet("task") != 0 && steps < 3000 {
    exPoll()
    sleepUs(0, 8000)
    steps = steps + 1
  }
  regressionAssert(exGet("task") == 0, "Extension import finishes without blocking")
  regressionAssert(exGet("stage") == 0, "Extension staging cleaned after operation")
  emit 1
}
func extensionsRegression(fixtures) {
  cocoaInit()
  exInit()
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let root = msg(msg(msg(fm, "temporaryDirectory"), "path"), "UTF8String") + "/brain-extensions-test-" + msg(msg(msg(cls("NSUUID"), "UUID"), "UUIDString"), "UTF8String")
  exSet("test-root", nsString(root))
  exReload("")
  regressionAssert(cocoaArrayCount(exGet("items")) == 0, "New extension list is empty")
  regressionAssert(exIdentifier("../escape") == 0 && exIdentifier(".hidden") == 0 && exIdentifier("evil/name") == 0, "Extension identifiers cannot escape storage")
  regressionAssert(exBeginImport(fixtures + "/Unicode café 🦋.vsix") == 1, "Unicode VSIX path imports")
  exTestIdle()
  regressionAssert(cocoaArrayCount(exGet("items")) == 1, "Real VSIX is listed after import")
  let item = exSelected()
  regressionAssert(item != 0 && exId(item) == "brain-test.fixture", "Imported extension is selected by stable identity")
  regressionAssert(indexOf(cocoaGetText(exGet("detail")), "Inactive") >= 0, "Extension runtime limitation is visible")
  let copied = msg_1(cls("NSData"), "dataWithContentsOfFile:", nsString(root + "/brain-test.fixture/package.vsix"))
  let original = msg_1(cls("NSData"), "dataWithContentsOfFile:", nsString(fixtures + "/Unicode café 🦋.vsix"))
  regressionAssert(msg_1(copied, "isEqualToData:", original) == 1, "Stored VSIX is byte-for-byte identical")
  let invalid = msg_1(nsString("bad-json|missing|oversized|traversal|duplicate|corrupt"), "componentsSeparatedByString:", nsString("|"))
  let i = 0
  while i < cocoaArrayCount(invalid) {
    let name = msg(cocoaArrayGet(invalid, i), "UTF8String")
    regressionAssert(exBeginImport(fixtures + "/" + name + ".vsix") == 1, "Invalid fixture begins bounded inspection")
    exTestIdle()
    regressionAssert(cocoaArrayCount(exGet("items")) == 1, "Invalid import preserves existing extension")
    i = i + 1
  }
  regressionAssert(exDelete("../escape") == 0, "Removal rejects path traversal")
  regressionAssert(exDelete("brain-test.fixture") == 1, "Remove deletes selected extension package")
  regressionAssert(cocoaArrayCount(exGet("items")) == 0, "Remove refreshes extension list")
  regressionAssert(msg_1(fm, "fileExistsAtPath:", nsString(root + "/brain-test.fixture")) == 0, "Removed package no longer exists")
  regressionAssert(exBeginImport(fixtures + "/Unicode café 🦋.vsix") == 1, "Cancellation fixture begins import")
  exClose(0, 0, 0)
  exTestIdle()
  regressionAssert(cocoaArrayCount(exGet("items")) == 0, "Closing window cancels import without installing")
  msg_2(fm, "removeItemAtPath:error:", nsString(root), 0)
  exSet("test-root", 0)
  print("PASS: VSIX import, Unicode paths, metadata validation, bounded reads, preserved archives, removal, cancellation")
  emit 1
}
