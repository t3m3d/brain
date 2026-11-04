// Permanent activity rail and section-specific sidebars. No network/AI backend.
import "k:cocoa"
import "k:objc"
func arGet(key) { emit cocoaGetAssocKey(appH(), "activity." + key) }
func arSet(key, value) { cocoaSetAssocKey(appH(), "activity." + key, value)  emit 1 }
func arName(index) {
  let names = msg_1(nsString("CODE|EXPLORE|HISTORY|SECURITY|INTELLIGENCE|EXTENSIONS"), "componentsSeparatedByString:", nsString("|"))
  if index < 0 || index >= 6 { emit "CODE" }
  emit msg(cocoaArrayGet(names, index), "UTF8String")
}
func arAction(self, cmd, sender) {
  let action = msg(cocoaGetAssocKey(sender, "activity.action"), "UTF8String")
  if action == "symbols" { onGoSymbol(0, 0, 0) }
  if action == "workspace-symbols" { onWorkspaceSymbol(0, 0, 0) }
  if action == "files" { onQuickOpen(0, 0, 0) }
  if action == "search" { onQuickSearch(0, 0, 0) }
  if action == "file-info" {
    if brainFlag("brain.fileinfo", 1) == 0 { onFileInfo(0, 0, 0) }
    infoRefresh()
  }
  if action == "git" { onSourceControl(0, 0, 0) }
  if action == "credential-search" { ccOpen("%password") }
  if action == "execution-search" { ccOpen("%exec") }
  if action == "add-extension" { exAdd(0, 0, 0) }
  if action == "refresh-extensions" { if exGet("task") == 0 { exReload("") } }
  if action == "extension-page" { arActivate(5, 0) }
  arRefresh()
  emit 1
}
func arButton(win, panel, title, row, action) {
  let width = cocoaNumberVal(arGet("width")) - 24
  let button = cocoaButton(win, title, 12, 628 - row * 34, width, 28)
  moveView(button, panel, 12, 628 - row * 34, width, 28, 10)
  cocoaSetFont(button, msg_d1(cls("NSFont"), "systemFontOfSize:", 11))
  msg_1(button, "setBezelStyle:", 1)
  cocoaSetAssocKey(button, "activity.action", nsString(action))
  cocoaOnClickKeyed(button, "activity-action", funcptr(arAction))
  emit button
}
func arPanel(win, side, index, rows) {
  let width = cocoaNumberVal(arGet("width"))
  let panel = pane(side, 0, 0, width, 698, 18)
  themeSurface(panel, themeSidebar(), 0)
  let header = cocoaPlainLabel(win, arName(index), 12, 668, width - 24, 26)
  moveView(header, panel, 12, 668, width - 24, 26, 10)
  cocoaSetFont(header, msg_d1(cls("NSFont"), "boldSystemFontOfSize:", 11))
  cocoaSetTextColor(header, themeToolbarPurple())
  let height = 620 - rows * 34
  let text = cocoaScrollText(win, 0, 0, width, height)
  moveView(msg(text, "enclosingScrollView"), panel, 0, 0, width, height, 18)
  msg_1(msg(text, "enclosingScrollView"), "setBorderType:", 0)
  msg_1(text, "setEditable:", 0)  msg_1(text, "setSelectable:", 1)
  msg_1(text, "setAutoresizingMask:", 2)
  msg_1(text, "setVerticallyResizable:", 1)
  msg_1(text, "setHorizontallyResizable:", 0)
  msg_1(msg(text, "textContainer"), "setWidthTracksTextView:", 1)
  msg_d2(text, "setTextContainerInset:", 12, 10)
  cocoaSetFont(text, msg_d1(cls("NSFont"), "systemFontOfSize:", 11))
  cocoaSetBg(text, themeSidebar())  cocoaSetTextColor(text, themeText())
  arSet("text." + index, text)
  msg_1(panel, "setHidden:", 1)
  emit panel
}
func arRefresh() {
  if arGet("bar") == 0 || brainFlag("brain.sidebar", 1) == 0 { emit 1 }
  let index = cocoaNumberVal(arGet("selected"))
  if index == 0 { emit 1 }
  let path = cocoaGetAssocKey(appH(), "brain.curpath")
  let text = msg(cocoaGetAssocKey(appH(), "brain.editor"), "string")
  if path == 0 { path = nsString("No file selected") }
  let target = arGet("text." + index)
  if arGet("last-path") == path && arGet("last-text") != 0 && msg_1(text, "isEqualToString:", arGet("last-text")) == 1 && cocoaNumberVal(arGet("last-section")) == index { emit 1 }
  let report = ""
  if index == 1 { report = infoSummary(msg(path, "UTF8String"), text) + "\n\nPROJECT NAVIGATION\nUse the controls above for file, declaration and text search. Architecture and call graphs are not implemented yet." }
  if index == 2 {
    report = "GIT\nOpen Source Control to inspect changes, stage files, commit and manage branches.\n\nRECENT FILES\n"
    let recent = msg_1(msg(cls("NSUserDefaults"), "standardUserDefaults"), "arrayForKey:", nsString("brain.recent.files"))
    let i = 0
    while i < cocoaArrayCount(recent) && i < 20 { report = report + "• " + baseName(msg(cocoaArrayGet(recent, i), "UTF8String")) + "\n"  i = i + 1 }
    if i == 0 { report = report + "No recent files yet.\n" }
    report = report + "\nUse Open Recent / Files above to navigate. Local timelines, blame and workspace snapshots are not implemented yet."
    if storeEdition() == 1 { report = "RECENT FILES\nUse Open Recent / Files to navigate.\n\nGit operations are available in the developer edition. Local timelines and snapshots are not implemented yet." }
  }
  if index == 3 { report = "MANUAL SOURCE REVIEW\nSearch credential-related code and command execution using the controls above. These are literal searches, not security findings.\n\nCURRENT FILE\n" + msg(path, "UTF8String") + "\n\nSecurity scanning, vulnerability checks and data-flow analysis are not implemented yet. No scan has been performed.\n\nSOURCE CONTEXT\n" + infoRole(msg(path, "UTF8String"), text) }
  if index == 4 { report = "LOCAL FILE EXPLANATION\n\n" + infoSummary(msg(path, "UTF8String"), text) + "\n\nAI STATUS\nNo AI provider is configured or called by this panel. This explanation uses local filename and source patterns. Project-wide AI and semantic retrieval are not implemented yet." }
  if index == 5 { report = "INSTALLED PACKAGES\nThe Extensions page shows package versions and details. Add VSIX also replaces an existing package after confirmation.\n\nACTIVATION\nImported VSIX packages remain Inactive. VS Code extension execution is not supported yet.\n\nUse the main page to select and remove a package." }
  cocoaTVSetString(target, report)
  arSet("last-path", path)  arSet("last-text", msg(msg(text, "copy"), "autorelease"))
  arSet("last-section", cocoaNumber(index))
  emit 1
}
func arSync() {
  if arGet("bar") == 0 { emit 1 }
  let index = cocoaNumberVal(arGet("selected"))
  let visible = brainFlag("brain.sidebar", 1)
  let i = 0
  while i < 6 {
    let active = i == index && visible == 1
    let button = cocoaArrayGet(arGet("buttons"), i)
    msg_1(button, "setContentTintColor:", themeMuted())
    if active == 1 { msg_1(button, "setContentTintColor:", themeToolbarPurple()) }
    msg_1(cocoaArrayGet(arGet("markers"), i), "setHidden:", 1 - active)
    msg_1(cocoaArrayGet(arGet("panels"), i), "setHidden:", i != index)
    i = i + 1
  }
  if exGet("dock") != 0 { msg_1(exGet("dock"), "setHidden:", visible == 0 || index != 5) }
  arRefresh()
  emit 1
}
func arActivate(index, toggle) {
  if index < 0 || index >= 6 || arGet("bar") == 0 { emit 0 }
  let visible = 1
  if toggle == 1 && index == cocoaNumberVal(arGet("selected")) && brainFlag("brain.sidebar", 1) == 1 { visible = 0 }
  arSet("selected", cocoaNumber(index))
  arSet("last-path", 0)
  cocoaSetAssocKey(appH(), "brain.sidebar", cocoaNumber(visible))
  msg_1(exGet("dock"), "setHidden:", 1)
  relayout()
  if index == 5 && visible == 1 { exShowDock() }
  arSync()
  emit 1
}
func arDismissPage() {
  if arGet("bar") == 0 || exGet("dock") == 0 { emit 1 }
  if msg(exGet("dock"), "isHidden") == 0 {
    msg_1(exGet("dock"), "setHidden:", 1)
    arSet("selected", cocoaNumber(0))
    arSync()
  }
  emit 1
}
func arClick(self, cmd, sender) { arActivate(cocoaNumberVal(cocoaGetAssocKey(sender, "activity.index")), 1) }
func arCode(self, cmd, sender) { arActivate(0, 0) }
func arExplore(self, cmd, sender) { arActivate(1, 0) }
func arHistory(self, cmd, sender) { arActivate(2, 0) }
func arSecurity(self, cmd, sender) { arActivate(3, 0) }
func arIntelligence(self, cmd, sender) { arActivate(4, 0) }
func arExtensions(self, cmd, sender) { arActivate(5, 0) }
func arInstall(win, editorParent) {
  if arGet("bar") != 0 { emit 1 }
  let split = cocoaGetAssocKey(appH(), "brain.hsplit")
  let side = cocoaGetAssocKey(appH(), "brain.sidepane")
  arSet("editor-parent", editorParent)
  // Wrap the existing Explorer, empty-workspace action and GitHub card intact.
  let original = msg(msg(side, "subviews"), "copy")
  let width = msgPointX(msg(cocoaGetAssocKey(appH(), "brain.table"), "enclosingScrollView"), "contentSize", 0)
  if width < 100 { width = 210 }
  arSet("width", cocoaNumber(width))
  let code = pane(side, 0, 0, width, 698, 18)
  themeSurface(code, themeExplorer(), 0)
  let i = 0
  while i < cocoaArrayCount(original) {
    let child = cocoaArrayGet(original, i)
    msg_1(child, "retain")  msg(child, "removeFromSuperview")
    msg_1(code, "addSubview:", child)  msg(child, "release")
    i = i + 1
  }
  msg(original, "release")
  let panels = cocoaArray()  cocoaArrayAdd(panels, code)
  let explore = arPanel(win, side, 1, 4)
  arButton(win, explore, "Symbols in File", 0, "symbols")
  arButton(win, explore, "Workspace Symbols", 1, "workspace-symbols")
  arButton(win, explore, "Search Project Text", 2, "search")
  arButton(win, explore, "Show File Info", 3, "file-info")
  cocoaArrayAdd(panels, explore)
  let history = arPanel(win, side, 2, 2)
  let git = arButton(win, history, "Source Control", 0, "git")
  msg_1(git, "setEnabled:", 1 - storeEdition())
  arButton(win, history, "Open Recent / Files", 1, "files")
  cocoaArrayAdd(panels, history)
  let security = arPanel(win, side, 3, 2)
  arButton(win, security, "Credential References", 0, "credential-search")
  arButton(win, security, "Execution References", 1, "execution-search")
  cocoaArrayAdd(panels, security)
  let intelligence = arPanel(win, side, 4, 1)
  arButton(win, intelligence, "Show File Info", 0, "file-info")
  cocoaArrayAdd(panels, intelligence)
  let extensions = arPanel(win, side, 5, 3)
  arButton(win, extensions, "Installed Extensions", 0, "extension-page")
  arButton(win, extensions, "Add / Replace VSIX…", 1, "add-extension")
  arButton(win, extensions, "Refresh Packages", 2, "refresh-extensions")
  cocoaArrayAdd(panels, extensions)
  arSet("panels", panels)
  // Outside the split: collapsing any sidebar never removes the rail.
  let rail = pane(msg(win, "contentView"), 0, 22, 48, 698, 16)
  themeSurface(rail, themeCanvas(), 0)
  let buttons = cocoaArray()  let markers = cocoaArray()
  let symbols = msg_1(nsString("doc.on.doc|point.3.connected.trianglepath.dotted|clock.arrow.circlepath|lock.shield|brain.head.profile|puzzlepiece.extension"), "componentsSeparatedByString:", nsString("|"))
  i = 0
  while i < 6 {
    let button = cocoaButton(win, "", 4, 646 - i * 48, 40, 40)
    moveView(button, rail, 4, 646 - i * 48, 40, 40, 8)
    msg_1(button, "setBordered:", 0)
    let title = arName(i)
    msg_1(button, "setImage:", msg_2(cls("NSImage"), "imageWithSystemSymbolName:accessibilityDescription:", cocoaArrayGet(symbols, i), nsString(title)))
    msg_1(button, "setImagePosition:", 1)
    msg_1(button, "setAccessibilityLabel:", nsString(title))
    msg_1(button, "setToolTip:", nsString(title + " — click to show or hide panel"))
    cocoaSetAssocKey(button, "activity.index", cocoaNumber(i))
    cocoaOnClickKeyed(button, "activity-select", funcptr(arClick))
    cocoaArrayAdd(buttons, button)
    let marker = pane(rail, 0, 652 - i * 48, 3, 28, 8)
    themeSurface(marker, themeToolbarPurple(), 1)
    cocoaArrayAdd(markers, marker)
    i = i + 1
  }
  arSet("bar", rail)  arSet("buttons", buttons)  arSet("markers", markers)
  arSet("selected", cocoaNumber(0))
  cocoaSetFrame(split, 48, 22, 992, 698)
  arSync()
  emit 1
}
func activityRegression() {
  let app = cocoaInit()
  let win = cocoaWindow(app, "Activity regression", 1040, 720)
  let editor = cocoaScrollText(win, 0, 0, 600, 400)
  let term = cocoaScrollText(win, 0, 0, 600, 180)
  cocoaSetAssocKey(app, "brain.win", win)  cocoaSetAssocKey(app, "brain.editor", editor)
  cocoaSetAssocKey(app, "brain.dir", nsString("/tmp"))
  cocoaSetAssocKey(app, "brain.curpath", nsString("/tmp/demo.k"))
  cocoaSetAssocKey(app, "brain.curtab", cocoaNumber(0 - 1))
  let tree = explorerView(win)
  cocoaSetAssocKey(app, "brain.table", tree)
  installLayout(win, tree, editor, term, 0)
  arInstall(win, msg(msg(editor, "enclosingScrollView"), "superview"))
  regressionAssert(msg(tree, "effectiveStyle") == 4, "Explorer keeps plain styling after reparenting")
  regressionAssert(msg_1(msg(tree, "backgroundColor"), "isEqual:", themeExplorer()) == 1, "Explorer document uses brand background")
  let treeScroll = msg(tree, "enclosingScrollView")
  regressionAssert(msg_1(msg(treeScroll, "backgroundColor"), "isEqual:", themeExplorer()) == 1, "Empty Explorer scroll area uses brand background")
  regressionAssert(msg_1(msg(msg(treeScroll, "contentView"), "backgroundColor"), "isEqual:", themeExplorer()) == 1, "Explorer clip uses brand background")
  exSet("test-root", nsString("/tmp/brain-activity-no-packages"))
  let i = 0
  while i < 6 {
    arActivate(i, 0)
    regressionAssert(msg(arGet("bar"), "superview") == msg(win, "contentView"), "Activity rail is independent of collapsible split")
    let j = 0
    while j < 6 {
      regressionAssert(msg(cocoaArrayGet(arGet("panels"), j), "isHidden") == (i != j), "Only selected section is shown")
      j = j + 1
    }
    arActivate(i, 1)
    regressionAssert(msg(cocoaGetAssocKey(app, "brain.sidepane"), "isHidden") == 1 && msg(arGet("bar"), "isHidden") == 0, "Rail remains when section collapses")
    i = i + 1
  }
  arActivate(5, 0)
  regressionAssert(exGet("dock") != 0 && msg(exGet("dock"), "superview") == arGet("editor-parent"), "Extensions page is docked in editor")
  arDismissPage()
  regressionAssert(msg(exGet("dock"), "isHidden") == 1 && cocoaNumberVal(arGet("selected")) == 0, "Returning to code dismisses Extensions page")
  onToggleSidebar(0, 0, 0)
  regressionAssert(msg(arGet("bar"), "isHidden") == 0, "Global sidebar toggle preserves activity rail")
  print("PASS: six activity panels, independent permanent rail, section collapse, docked Extensions")
  emit 1
}
