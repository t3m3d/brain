// Find controls for the shared toolbar input. No second search field.
import "k:cocoa"
import "k:objc"
func fiGet(key) { emit cocoaGetAssocKey(appH(), "find." + key) }
func fiSet(key, value) { cocoaSetAssocKey(appH(), "find." + key, value)  emit 1 }
func fiStatus(text) { cocoaSetText(fiGet("status"), text)  emit 1 }
func fiInvalidate(self, cmd, sender) {
  fiSet("snapshot", 0)  fiSet("last", cocoaNumber(0 - 1))
  fiStatus("Find")
  emit 1
}
func fiPrepare() {
  let editor = cocoaGetAssocKey(appH(), "brain.editor")
  let text = msg(editor, "string")
  let query = msg(fiGet("query"), "stringValue")
  if msg(query, "length") == 0 { fiSet("hits", 0)  fiStatus("Type text to find")  emit 0 }
  if msg(text, "length") > 2097152 { fiStatus("Document exceeds the 2 MiB Find preview limit")  emit 0 }
  let caseFlag = msg(fiGet("case"), "state")
  if fiGet("snapshot") != 0 && msg_1(text, "isEqualToString:", fiGet("snapshot")) == 1 && msg_1(query, "isEqualToString:", fiGet("cached-query")) == 1 && caseFlag == cocoaNumberVal(fiGet("cached-case")) { emit 1 }
  let pattern = msg_1(cls("NSRegularExpression"), "escapedPatternForString:", query)
  let expression = msg_3(cls("NSRegularExpression"), "regularExpressionWithPattern:options:error:", pattern, 1 - caseFlag, 0)
  if expression == 0 { fiStatus("Could not search this text")  emit 0 }
  let hits = msg_4(expression, "matchesInString:options:range:", text, 0, 0, msg(text, "length"))
  fiSet("expression", expression)  fiSet("hits", hits)
  fiSet("snapshot", msg(msg(text, "copy"), "autorelease"))  fiSet("cached-query", query)
  fiSet("cached-case", cocoaNumber(caseFlag))  fiSet("last", cocoaNumber(0 - 1))
  if cocoaArrayCount(hits) == 0 { fiStatus("No matches")  emit 0 }
  emit 1
}
func fiLength(hit) {
  let value = msg_4(fiGet("expression"), "replacementStringForResult:inString:offset:template:", hit, fiGet("snapshot"), 0, nsString("$0"))
  emit msg(value, "length")
}
func fiStep(direction) {
  if fiPrepare() == 0 { emit 0 }
  let editor = cocoaGetAssocKey(appH(), "brain.editor")
  let hits = fiGet("hits")
  let caret = msg(editor, "selectedRange")
  let previous = cocoaNumberVal(fiGet("last"))
  let chosen = 0
  if direction < 0 { chosen = cocoaArrayCount(hits) - 1 }
  let i = 0  let found = 0
  while i < cocoaArrayCount(hits) && found == 0 {
    let offset = msg(cocoaArrayGet(hits, i), "range")
    if direction > 0 {
      if offset > caret || (offset == caret && previous != i) { chosen = i  found = 1 }
    } else { if offset >= caret { found = 1 } else { chosen = i } }
    i = i + 1
  }
  let hit = cocoaArrayGet(hits, chosen)
  let offset = msg(hit, "range")
  let length = fiLength(hit)
  msg_2(editor, "setSelectedRange:", offset, length)
  msg_2(editor, "scrollRangeToVisible:", offset, length)
  fiSet("last", cocoaNumber(chosen))
  fiStatus((chosen + 1) + " / " + cocoaArrayCount(hits))
  refreshEditorChrome()
  emit 1
}
func fiNext(self, cmd, sender) {
  if cocoaNumberVal(fiGet("active")) == 0 { onFind(0, 0, 0) }
  fiStep(1)
}
func fiPrevious(self, cmd, sender) {
  if cocoaNumberVal(fiGet("active")) == 0 { onFind(0, 0, 0) }
  fiStep(0 - 1)
}
func fiReplace(self, cmd, sender) {
  if fiPrepare() == 0 { emit 0 }
  let editor = cocoaGetAssocKey(appH(), "brain.editor")
  let index = cocoaNumberVal(fiGet("last"))
  let hits = fiGet("hits")
  if index < 0 || index >= cocoaArrayCount(hits) { fiStep(1)  index = cocoaNumberVal(fiGet("last")) }
  let hit = cocoaArrayGet(hits, index)
  let offset = msg(hit, "range")
  if msg(editor, "selectedRange") != offset { fiStep(1)  emit 0 }
  msg_3(editor, "insertText:replacementRange:", msg(fiGet("replacement"), "stringValue"), offset, fiLength(hit))
  fiInvalidate(0, 0, 0)
  fiStep(1)
  emit 1
}
func fiReplaceAll(self, cmd, sender) {
  if fiPrepare() == 0 { emit 0 }
  let text = fiGet("snapshot")
  let count = cocoaArrayCount(fiGet("hits"))
  let template = msg_1(cls("NSRegularExpression"), "escapedTemplateForString:", msg(fiGet("replacement"), "stringValue"))
  let value = msg_5(fiGet("expression"), "stringByReplacingMatchesInString:options:range:withTemplate:", text, 0, 0, msg(text, "length"), template)
  msg_3(cocoaGetAssocKey(appH(), "brain.editor"), "insertText:replacementRange:", value, 0, msg(text, "length"))
  fiInvalidate(0, 0, 0)  fiStatus("Replaced " + count + " matches")
  emit 1
}
func fiClose(self, cmd, sender) {
  if cocoaNumberVal(fiGet("active")) == 1 {
    fiSet("saved-query", msg(msg(msg(fiGet("query"), "stringValue"), "copy"), "autorelease"))
  }
  fiSet("active", cocoaNumber(0))
  msg_1(fiGet("query"), "setStringValue:", nsString(""))
  msg_1(fiGet("query"), "setAccessibilityLabel:", nsString("Search files and commands"))
  ccTitle()
  msg_1(fiGet("panel"), "setHidden:", 1)
  msg_d1(fiGet("height"), "setConstant:", 0)
  msg(fiGet("parent"), "layoutSubtreeIfNeeded")
  cocoaMakeFirstResponder(cocoaGetAssocKey(appH(), "brain.win"), cocoaGetAssocKey(appH(), "brain.editor"))
  emit 1
}
func fiClear(self, cmd, sender) {
  msg_1(fiGet("query"), "setStringValue:", nsString(""))
  fiInvalidate(0, 0, 0)  fiClose(0, 0, 0)
  emit 1
}
func fiToggleReplace(self, cmd, sender) {
  let hidden = msg(fiGet("replace-row"), "isHidden")
  msg_1(fiGet("replace-row"), "setHidden:", 1 - hidden)
  let height = 40  if hidden == 1 { height = 76 }
  msg_d1(fiGet("height"), "setConstant:", height)
  msg(fiGet("parent"), "layoutSubtreeIfNeeded")
  emit 1
}
func fiCommand(self, cmd, control, textView, command) {
  if pickerSelectorEquals(command, "cancelOperation:") == 1 { fiClose(0, 0, 0)  emit 1 }
  if pickerSelectorEquals(command, "insertNewline:") == 1 {
    if control == fiGet("replacement") { fiReplace(0, 0, 0) } else { fiStep(1) }
    emit 1
  }
  emit 0
}
func fiButton(win, panel, title, x, y, width, action, key) {
  let button = cocoaButton(win, title, x, y, width, 28)
  moveView(button, panel, x, y, width, 28, 0)
  msg_1(button, "setBezelStyle:", 1)
  cocoaOnClickKeyed(button, "find-" + key, action)
  emit button
}
func fiInstall(win, parent) {
  if fiGet("panel") != 0 { emit 1 }
  // A reserved header strip above the document, never an overlay on text.
  let panel = pane(parent, 0, 426, 829, 40, 10)
  msg_1(panel, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
  let constraints = cocoaArray()
  cocoaArrayAdd(constraints, msg_1(msg(panel, "leadingAnchor"), "constraintEqualToAnchor:", msg(parent, "leadingAnchor")))
  cocoaArrayAdd(constraints, msg_1(msg(panel, "trailingAnchor"), "constraintEqualToAnchor:", msg(parent, "trailingAnchor")))
  cocoaArrayAdd(constraints, msg_1(msg(panel, "topAnchor"), "constraintEqualToAnchor:", msg(parent, "topAnchor")))
  let height = msg_d1(msg(panel, "heightAnchor"), "constraintEqualToConstant:", 0)
  cocoaArrayAdd(constraints, height)
  let scroll = msg(cocoaGetAssocKey(appH(), "brain.editor"), "enclosingScrollView")
  let minimap = cocoaGetAssocKey(appH(), "brain.minimap")
  if scroll != 0 {
    msg_1(scroll, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
    cocoaArrayAdd(constraints, msg_1(msg(scroll, "leadingAnchor"), "constraintEqualToAnchor:", msg(parent, "leadingAnchor")))
    let trailing = msg_1(msg(scroll, "trailingAnchor"), "constraintEqualToAnchor:", msg(parent, "trailingAnchor"))
    msg_d1(trailing, "setConstant:", 0 - 62)
    cocoaArrayAdd(constraints, trailing)
    cocoaArrayAdd(constraints, msg_1(msg(scroll, "topAnchor"), "constraintEqualToAnchor:", msg(panel, "bottomAnchor")))
    cocoaArrayAdd(constraints, msg_1(msg(scroll, "bottomAnchor"), "constraintEqualToAnchor:", msg(parent, "bottomAnchor")))
  }
  if minimap != 0 {
    msg_1(minimap, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
    cocoaArrayAdd(constraints, msg_1(msg(minimap, "leadingAnchor"), "constraintEqualToAnchor:", msg(scroll, "trailingAnchor")))
    cocoaArrayAdd(constraints, msg_1(msg(minimap, "trailingAnchor"), "constraintEqualToAnchor:", msg(parent, "trailingAnchor")))
    cocoaArrayAdd(constraints, msg_1(msg(minimap, "topAnchor"), "constraintEqualToAnchor:", msg(panel, "bottomAnchor")))
    cocoaArrayAdd(constraints, msg_1(msg(minimap, "bottomAnchor"), "constraintEqualToAnchor:", msg(parent, "bottomAnchor")))
  }
  fiSet("parent", parent)  fiSet("height", height)
  msg_1(cls("NSLayoutConstraint"), "activateConstraints:", constraints)
  themeSurface(panel, themeSidebar(), 0)
  let body = pane(panel, 164, 0, 500, 40, 13)
  let replaceRow = pane(panel, 164, 0, 500, 36, 5)
  msg_1(replaceRow, "setHidden:", 1)
  let query = ccSharedInput()
  let replacement = cocoaTextField(win, 12, 4, 220, 28)
  moveView(replacement, replaceRow, 12, 4, 220, 28, 0)
  msg_1(replacement, "setPlaceholderString:", nsString("Replace with…"))
  cocoaSetBg(query, themeCanvas())  cocoaSetTextColor(query, themeText())
  cocoaSetBg(replacement, themeCanvas())  cocoaSetTextColor(replacement, themeText())
  fiButton(win, body, "↑", 312, 6, 30, funcptr(fiPrevious), "previous")
  let next = fiButton(win, body, "↓", 348, 6, 30, funcptr(fiNext), "next")
  cocoaSetButtonTextColor(next, themeToolbarPurple())
  let caseButton = fiButton(win, body, "Aa", 384, 6, 38, funcptr(fiInvalidate), "case")
  msg_1(caseButton, "setButtonType:", 1)
  msg_1(caseButton, "setToolTip:", nsString("Match case"))
  let expand = fiButton(win, body, "↕", 428, 6, 28, funcptr(fiToggleReplace), "expand")
  msg_1(expand, "setToolTip:", nsString("Show or hide Replace"))
  let clear = fiButton(win, body, "×", 462, 6, 28, funcptr(fiClear), "clear")
  msg_1(clear, "setToolTip:", nsString("Clear Find"))
  fiButton(win, replaceRow, "Replace", 250, 4, 82, funcptr(fiReplace), "replace")
  fiButton(win, replaceRow, "Replace All", 344, 4, 110, funcptr(fiReplaceAll), "all")
  let status = cocoaPlainLabel(win, "Find in current file", 12, 9, 292, 20)
  moveView(status, body, 12, 9, 292, 20, 0)
  cocoaSetFont(status, msg_d1(cls("NSFont"), "systemFontOfSize:", 10))
  cocoaSetTextColor(status, themeText())
  fiSet("replace-row", replaceRow)
  let c = cocoaClassNew("BrainFindDelegate")
  cocoaClassAddMethod(c, "controlTextDidChange:", funcptr(fiInvalidate), "v@:@")
  cocoaClassAddMethod(c, "control:textView:doCommandBySelector:", funcptr(fiCommand), "c@:@@:")
  cocoaClassRegister(c)
  let delegate = cocoaNew(c)
  fiSet("delegate", delegate)  fiSet("panel", panel)  fiSet("query", query)
  fiSet("replacement", replacement)  fiSet("status", status)  fiSet("case", caseButton)
  msg_1(replacement, "setDelegate:", delegate)
  msg_1(panel, "setHidden:", 1)
  emit 1
}
func onFind(self, cmd, sender) {
  if fiGet("panel") == 0 { emit 0 }
  let wasActive = cocoaNumberVal(fiGet("active"))
  pickerClose()
  fiSet("active", cocoaNumber(1))
  if wasActive == 0 {
    let saved = fiGet("saved-query")
    if saved == 0 { saved = nsString("") }
    msg_1(fiGet("query"), "setStringValue:", saved)
  }
  msg_1(fiGet("query"), "setPlaceholderString:", nsString("Find in current file  ⌘F"))
  msg_1(fiGet("query"), "setAccessibilityLabel:", nsString("Find in current file"))
  msg_1(scGet("panel"), "setHidden:", 1)
  let height = 40
  if msg(fiGet("replace-row"), "isHidden") == 0 { height = 76 }
  msg_d1(fiGet("height"), "setConstant:", height)
  msg_1(fiGet("panel"), "setHidden:", 0)
  msg(fiGet("parent"), "layoutSubtreeIfNeeded")
  fiInvalidate(0, 0, 0)
  cocoaMakeFirstResponder(cocoaGetAssocKey(appH(), "brain.win"), fiGet("query"))
  msg_1(fiGet("query"), "selectText:", 0)
  emit 1
}
func onFindReplace(self, cmd, sender) {
  onFind(0, 0, 0)
  if msg(fiGet("replace-row"), "isHidden") == 1 { fiToggleReplace(0, 0, 0) }
  cocoaMakeFirstResponder(cocoaGetAssocKey(appH(), "brain.win"), fiGet("replacement"))
  emit 1
}
func findRegression(win) {
  fiInstall(win, msg(win, "contentView"))
  let editor = cocoaGetAssocKey(appH(), "brain.editor")
  let before = msg(msg(editor, "string"), "copy")
  cocoaTVSetString(editor, "café 🦋 needle NEEDLE needle")
  fiSet("saved-query", nsString("needle"))
  regressionAssert(fiGet("query") == ccSharedInput(), "Find and Command Center share one input")
  let i = 0
  while i < 8 {
    onFind(0, 0, 0)
    regressionAssert(msg(fiGet("panel"), "isHidden") == 0, "Find repeatedly opens editor header")
    fiNext(0, 0, 0)
    regressionAssert(cocoaArrayCount(fiGet("hits")) == 3, "Find literal case-insensitive results")
    fiClose(0, 0, 0)
    regressionAssert(msg(fiGet("panel"), "isHidden") == 1, "Find closes without leaving a second search box")
    i = i + 1
  }
  onFind(0, 0, 0)
  fiNext(0, 0, 0)
  regressionAssert(msg(editor, "selectedRange") == 8, "Find uses UTF-16 offset after emoji")
  fiNext(0, 0, 0)
  fiPrevious(0, 0, 0)
  regressionAssert(msg(editor, "selectedRange") == 8, "Find previous returns to prior result")
  msg_1(fiGet("replacement"), "setStringValue:", nsString("$1"))
  fiReplaceAll(0, 0, 0)
  regressionAssert(cocoaTVGetString(editor) == "café 🦋 $1 $1 $1", "Replace All treats replacement as literal text")
  fiClose(0, 0, 0)
  ccOpen(">zoom")
  regressionAssert(cocoaGetAssocKey(appH(), "brain.picker.input") == fiGet("query"), "Commands retain the shared toolbar input")
  pickerClose()
  onFind(0, 0, 0)
  regressionAssert(msg(msg(fiGet("query"), "stringValue"), "UTF8String") == "needle", "Find query survives command mode")
  fiClose(0, 0, 0)
  cocoaTVSetString(editor, msg(before, "UTF8String"))  msg(before, "release")
  print("PASS: repeated Find open/close, Unicode offsets, next/previous, literal Replace All")
  emit 1
}
