// Native Source Control for the developer edition. Git/gh own credentials.
// All subprocess arguments are arrays; user input never becomes shell code.
import "k:cocoa"
import "k:objc"

func scGet(key) { emit cocoaGetAssocKey(appH(), "sc." + key) }
func scSet(key, value) { cocoaSetAssocKey(appH(), "sc." + key, value)  emit "1" }
func scText(key) { emit msg(scGet(key), "UTF8String") }
func scArgs() { emit cocoaArray() }
func scArg(args, value) { cocoaArrayAdd(args, nsString(value))  emit "1" }
func scMessage(text) { cocoaSetText(scGet("message"), text)  emit "1" }
func scGh() {
  let fm = msg(cls("NSFileManager"), "defaultManager")
  if msg_1(fm, "isExecutableFileAtPath:", nsString("/opt/homebrew/bin/gh")) == 1 { emit "/opt/homebrew/bin/gh" }
  if msg_1(fm, "isExecutableFileAtPath:", nsString("/usr/local/bin/gh")) == 1 { emit "/usr/local/bin/gh" }
  emit ""
}
func scWorkspace() { emit msg(cocoaGetAssocKey(appH(), "brain.dir"), "UTF8String") }
func scDisplay(text) {
  let view = scGet("diff")
  cocoaTVSetString(view, text)
  let storage = msg(view, "textStorage")
  cocoaTSColorRange(storage, themeText(), 0, msg(storage, "length"))
  let lines = msg_1(msg(view, "string"), "componentsSeparatedByString:", nsString("\n"))
  let offset = 0  let i = 0
  while i < cocoaArrayCount(lines) && i < 12000 {
    let line = cocoaArrayGet(lines, i)
    let color = themeText()
    if msg_1(line, "hasPrefix:", nsString("+")) == 1 { color = cocoaRGB(126, 200, 144) }
    if msg_1(line, "hasPrefix:", nsString("-")) == 1 { color = cocoaRGB(227, 142, 145) }
    if msg_1(line, "hasPrefix:", nsString("@@")) == 1 { color = cocoaRGB(160, 135, 222) }
    cocoaTSColorRange(storage, color, offset, msg(line, "length"))
    offset = offset + msg(line, "length") + 1
    i = i + 1
  }
  emit "1"
}
func scStart(executable, args, mode, directory) {
  if storeEdition() == 1 { emit 0 }
  if scGet("task") != 0 { scMessage("Operation running. Use Cancel to stop it.")  emit 0 }
  let fm = msg(cls("NSFileManager"), "defaultManager")
  if executable == "" || msg_1(fm, "isExecutableFileAtPath:", nsString(executable)) == 0 {
    scMessage("Install GitHub CLI from cli.github.com to sign in.")  emit 0
  }
  let uuid = msg(msg(msg(cls("NSUUID"), "UUID"), "UUIDString"), "UTF8String")
  let temporary = msg(msg(msg(fm, "temporaryDirectory"), "path"), "UTF8String") + "/brain-git-" + uuid
  let permissions = allocInit("NSMutableDictionary")
  msg_2(permissions, "setObject:forKey:", cocoaNumber(448), nsString("NSFilePosixPermissions"))
  if msg_4(fm, "createDirectoryAtPath:withIntermediateDirectories:attributes:error:", nsString(temporary), 0, permissions, 0) == 0 {
    msg(permissions, "release")  scMessage("Could not create private task directory.")  emit 0
  }
  let log = temporary + "/output"
  msg_2(permissions, "setObject:forKey:", cocoaNumber(384), nsString("NSFilePosixPermissions"))
  msg_3(fm, "createFileAtPath:contents:attributes:", nsString(log), msg(cls("NSData"), "data"), permissions)
  msg(permissions, "release")
  let output = msg_1(cls("NSFileHandle"), "fileHandleForWritingAtPath:", nsString(log))
  if output == 0 { msg_2(fm, "removeItemAtPath:error:", nsString(temporary), 0)  emit 0 }
  let task = allocInit("NSTask")
  msg_1(task, "setExecutableURL:", msg_1(cls("NSURL"), "fileURLWithPath:", nsString(executable)))
  msg_1(task, "setArguments:", args)
  msg_1(task, "setCurrentDirectoryURL:", msg_1(cls("NSURL"), "fileURLWithPath:", nsString(directory)))
  msg_1(task, "setStandardOutput:", output)
  msg_1(task, "setStandardError:", output)
  let environment = msg(msg(msg(cls("NSProcessInfo"), "processInfo"), "environment"), "mutableCopy")
  msg_2(environment, "setObject:forKey:", nsString("0"), nsString("GIT_TERMINAL_PROMPT"))
  msg_2(environment, "setObject:forKey:", nsString("cat"), nsString("GIT_PAGER"))
  msg_2(environment, "setObject:forKey:", nsString("/usr/bin/open"), nsString("GH_BROWSER"))
  msg_2(environment, "setObject:forKey:", nsString("1"), nsString("GH_NO_UPDATE_NOTIFIER"))
  msg_2(environment, "setObject:forKey:", nsString("ssh -oBatchMode=yes"), nsString("GIT_SSH_COMMAND"))
  msg_1(task, "setEnvironment:", environment)
  msg(environment, "release")
  let input = msg(cls("NSPipe"), "pipe")
  msg_1(task, "setStandardInput:", input)
  if msg_1(task, "launchAndReturnError:", 0) == 0 {
    msg(task, "release")  msg(output, "closeFile")
    msg_2(fm, "removeItemAtPath:error:", nsString(temporary), 0)
    scMessage("Could not start Git operation.")  emit 0
  }
  // gh browser sign-in may wait for Return; all other choices are explicit flags.
  let writer = msg(input, "fileHandleForWriting")
  if mode == "login" { fdWrite(msg(writer, "fileDescriptor"), "\n", 1) }
  msg(writer, "closeFile")
  scSet("task", task)  scSet("output", output)
  scSet("temporary", nsString(temporary))  scSet("log", nsString(log))
  scSet("mode", nsString(mode))  scSet("workspace", nsString(scWorkspace()))
  let limit = 120  if mode == "login" { limit = 900 }
  scSet("deadline", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", limit))
  scSet("cancelled", cocoaNumber(0))
  scSet("truncated", cocoaNumber(0))
  scSet("loginpoll", msg(cls("NSDate"), "distantPast"))
  msg(task, "release")
  scMessage("Running " + mode + "…")
  emit 1
}
func scGit(args, mode) { emit scStart("/usr/bin/git", args, mode, scText("root")) }
func scSidebarAction(self, cmd, sender) {
  msg_1(scGet("panel"), "setHidden:", 0)
  if scGet("login") != 0 { scAccount() }
  else { scAuthenticate(self, cmd, sender) }
  emit "1"
}
func scSidebarAccount(login) {
  let title = "Sign in to GitHub"
  let detail = "Connect your account"
  scSet("login", 0)
  if len(login) > 0 {
    scSet("login", nsString(login))
    title = "GitHub · " + login
    detail = "Open Source Control"
  }
  cocoaSetText(scGet("sidebar-detail"), detail)
  msg_1(scGet("sidebar-login"), "setTitle:", nsString(title))
  cocoaSetButtonTextColor(scGet("sidebar-login"), cocoaRGB(255, 255, 255))
  emit "1"
}
func scInstallSidebar(win) {
  let side = cocoaGetAssocKey(appH(), "brain.sidepane")
  let tree = msg(cocoaGetAssocKey(appH(), "brain.table"), "enclosingScrollView")
  moveView(tree, side, 0, 92, 210, 530, 18)
  // Keep the empty-workspace action above the scroll view after reparenting it.
  let openFolder = cocoaGetAssocKey(appH(), "brain.openfolder")
  msg(openFolder, "removeFromSuperview")
  msg_1(side, "addSubview:", openFolder)
  let card = pane(side, 8, 8, 194, 76, 2)
  themeSurface(card, themeToolbarPurple(), 8)
  let button = cocoaButton(win, "Sign in to GitHub", 0, 32, 194, 36)
  moveView(button, card, 0, 32, 194, 36, 2)
  msg_1(button, "setBordered:", 0)
  cocoaSetFont(button, msg_d1(cls("NSFont"), "boldSystemFontOfSize:", 12))
  cocoaSetButtonTextColor(button, cocoaRGB(255, 255, 255))
  msg_1(button, "setToolTip:", nsString("Sign in to GitHub or open Source Control"))
  cocoaOnClickKeyed(button, "sc-sidebar-login", funcptr(scSidebarAction))
  scSet("sidebar-login", button)
  let detail = scLabel(win, card, "Connect your account", 12, 12, 170, 18, 2)
  cocoaSetTextColor(detail, cocoaRGB(229, 217, 255))
  msg_1(detail, "setAlignment:", 1)
  scSet("sidebar-detail", detail)
  emit "1"
}
func scAuthenticate(self, cmd, sender) {
  let args = scArgs()
  scArg(args, "auth")  scArg(args, "login")  scArg(args, "--web")
  scArg(args, "--hostname")  scArg(args, "github.com")
  scArg(args, "--git-protocol")  scArg(args, "https")  scArg(args, "--skip-ssh-key")
  scStart(scGh(), args, "login", scWorkspace())
  emit "1"
}
func scRefreshAccount(self, cmd, sender) { scAccount()  emit "1" }
func scAccount() {
  if scGh() == "" { cocoaSetText(scGet("account"), "GitHub CLI not installed")  scRefresh(0, 0, 0)  emit "1" }
  let args = scArgs()
  scArg(args, "auth")  scArg(args, "status")  scArg(args, "--hostname")  scArg(args, "github.com")
  scArg(args, "--active")  scArg(args, "--json")  scArg(args, "hosts")  scArg(args, "--jq")
  scArg(args, ".hosts[\"github.com\"][] | select(.active) | .login + \"\\t\" + .state")
  if scStart(scGh(), args, "account", scWorkspace()) == 0 { scRefresh(0, 0, 0) }
  emit "1"
}
func scRefresh(self, cmd, sender) {
  if scGet("task") != 0 { emit "1" }
  scSet("root", 0)  scSet("records", cocoaArray())
  cocoaReload(scGet("files"))
  if brainFlag("brain.workspace", 0) == 0 { scMessage("Open a repository folder to start.")  emit "1" }
  let args = scArgs()  scArg(args, "rev-parse")  scArg(args, "--show-toplevel")
  scStart("/usr/bin/git", args, "root", scWorkspace())
  emit "1"
}
func scWorkspaceChanged() {
  if storeEdition() == 1 || scGet("panel") == 0 { emit "1" }
  scSet("root", 0)  scSet("records", cocoaArray())
  cocoaReload(scGet("files"))
  cocoaSetText(scGet("repository"), "Open a repository folder")
  cocoaSetText(scGet("branchlabel"), "")
  scDisplay("Select a changed file to review its diff.")
  if scGet("task") == 0 && msg(scGet("panel"), "isHidden") == 0 { scRefresh(0, 0, 0) }
  emit "1"
}
func scStatus() {
  let args = scArgs()  scArg(args, "status")  scArg(args, "--porcelain=v1")
  scArg(args, "-z")  scArg(args, "--branch")  scArg(args, "--untracked-files=normal")
  scGit(args, "status")  emit "1"
}
func scParseStatus(text) {
  let zero = msg_3(msg(cls("NSString"), "alloc"), "initWithBytes:length:encoding:", fromCharCode(0), 1, 4)
  let entries = msg_1(text, "componentsSeparatedByString:", zero)
  msg(zero, "release")
  let records = cocoaArray()  let i = 0
  while i < cocoaArrayCount(entries) {
    let entry = cocoaArrayGet(entries, i)
    if msg_1(entry, "hasPrefix:", nsString("## ")) == 1 {
      scSet("branchstatus", msg_1(entry, "substringFromIndex:", 3))
      let initial = msg_1(entry, "containsString:", nsString("No commits yet"))
      if msg_1(entry, "containsString:", nsString("Initial commit")) == 1 { initial = 1 }
      scSet("unborn", cocoaNumber(initial))
    } else {
      if msg(entry, "length") >= 3 {
        let record = allocInit("NSMutableDictionary")
        let state = msg_2(entry, "substringWithRange:", 0, 2)
        msg_2(record, "setObject:forKey:", state, nsString("state"))
        msg_2(record, "setObject:forKey:", msg_1(entry, "substringFromIndex:", 3), nsString("path"))
        if msg_1(state, "containsString:", nsString("R")) == 1 || msg_1(state, "containsString:", nsString("C")) == 1 {
          i = i + 1
          if i < cocoaArrayCount(entries) { msg_2(record, "setObject:forKey:", cocoaArrayGet(entries, i), nsString("old")) }
        }
        cocoaArrayAdd(records, record)  msg(record, "release")
      }
    }
    i = i + 1
  }
  emit records
}
func scBranches() {
  let args = scArgs()  scArg(args, "branch")  scArg(args, "--format=%(refname:short)")
  scGit(args, "branches")  emit "1"
}
func scReady() {
  scMessage(cocoaArrayCount(scGet("records")) + " changed files · select a file to view its diff")
  emit "1"
}
func scRows(self, cmd, table) { emit cocoaArrayCount(scGet("records")) }
func scValue(self, cmd, table, column, row) {
  let record = cocoaArrayGet(scGet("records"), row)
  emit nsString(msg(msg_1(record, "objectForKey:", nsString("state")), "UTF8String") + "  " + msg(msg_1(record, "objectForKey:", nsString("path")), "UTF8String"))
}
func scSelected() {
  let row = msg(scGet("files"), "selectedRow")
  if row < 0 || row >= cocoaArrayCount(scGet("records")) { scMessage("Select a changed file first.")  emit 0 }
  emit cocoaArrayGet(scGet("records"), row)
}
func scPathArgs(args, record) {
  scArg(args, "--")
  let old = msg_1(record, "objectForKey:", nsString("old"))
  if old != 0 { cocoaArrayAdd(args, old) }
  cocoaArrayAdd(args, msg_1(record, "objectForKey:", nsString("path")))
  emit "1"
}
func scStage(self, cmd, sender) {
  let record = scSelected()  if record == 0 { emit "1" }
  let args = scArgs()  scArg(args, "add")  scPathArgs(args, record)
  scGit(args, "stage")  emit "1"
}
func scUnstage(self, cmd, sender) {
  let record = scSelected()  if record == 0 { emit "1" }
  let args = scArgs()
  if brainFlag("sc.unborn", 0) == 1 { scArg(args, "rm")  scArg(args, "--cached") }
  else { scArg(args, "restore")  scArg(args, "--staged") }
  scPathArgs(args, record)  scGit(args, "unstage")  emit "1"
}
func scStageAll(self, cmd, sender) {
  if scGet("root") == 0 { scMessage("Open a Git repository first.")  emit "1" }
  let args = scArgs()  scArg(args, "add")  scArg(args, "--all")  scArg(args, "--")  scArg(args, ".")
  scGit(args, "stage all")  emit "1"
}
func scDiff(self, cmd, sender) {
  let record = scSelected()  if record == 0 { emit "1" }
  let state = msg(msg_1(record, "objectForKey:", nsString("state")), "UTF8String")
  let staged = 0
  if sender != 0 { staged = brainFlag("sc.forcestaged", 0) }
  if sender == 0 && substring(state, 1, 2) == " " { staged = 1 }
  let args = scArgs()  scArg(args, "diff")  scArg(args, "--no-ext-diff")  scArg(args, "--no-textconv")
  if state == "??" {
    scArg(args, "--no-index")  scArg(args, "--")  scArg(args, "/dev/null")
    cocoaArrayAdd(args, msg_1(record, "objectForKey:", nsString("path")))
  } else {
    if staged == 1 { scArg(args, "--cached") }
    scPathArgs(args, record)
  }
  scGit(args, "diff")  emit "1"
}
func scWorkingDiff(self, cmd, sender) { scSet("forcestaged", cocoaNumber(0))  scDiff(self, cmd, sender) }
func scStagedDiff(self, cmd, sender) { scSet("forcestaged", cocoaNumber(1))  scDiff(self, cmd, sender) }
func scSelection(self, cmd, note) { if scGet("task") == 0 { scDiff(self, cmd, 0) }  emit "1" }
func scOpenFile(self, cmd, sender) {
  let record = scSelected()  if record == 0 { emit "1" }
  openPath(scText("root") + "/" + msg(msg_1(record, "objectForKey:", nsString("path")), "UTF8String"))
  onSourceControl(0, 0, 0)  emit "1"
}
func scCleanEditors() {
  saveCurTab()
  let texts = cocoaGetAssocKey(appH(), "brain.tabtexts")
  let saved = cocoaGetAssocKey(appH(), "brain.savedtexts")
  let i = 0
  while i < cocoaArrayCount(texts) {
    if msg_1(cocoaArrayGet(texts, i), "isEqualToString:", cocoaArrayGet(saved, i)) == 0 {
      scMessage("Save or close modified editors before changing branches or pulling.")  emit 0
    }
    i = i + 1
  }
  emit 1
}
func scReloadEditors() {
  let paths = cocoaGetAssocKey(appH(), "brain.tabpaths")
  let texts = cocoaGetAssocKey(appH(), "brain.tabtexts")
  let saved = cocoaGetAssocKey(appH(), "brain.savedtexts")
  let managers = cocoaGetAssocKey(appH(), "brain.tabundos")
  let i = 0
  while i < cocoaArrayCount(paths) {
    if cocoaNumberVal(cocoaGetAssocKey(cocoaArrayGet(managers, i), "brain.untitled")) == 0 {
      if msg_1(cocoaArrayGet(texts, i), "isEqualToString:", cocoaArrayGet(saved, i)) == 1 {
        let data = msg_1(cls("NSData"), "dataWithContentsOfFile:", cocoaArrayGet(paths, i))
        let text = msg_2(msg(cls("NSString"), "alloc"), "initWithData:encoding:", data, 4)
        if text != 0 {
          cocoaArraySet(texts, i, text)  cocoaArraySet(saved, i, text)
          msg(cocoaArrayGet(managers, i), "removeAllActions")  msg(text, "release")
        }
      }
    }
    i = i + 1
  }
  let active = curTabIdx()
  if active >= 0 { cocoaSetAssocKey(appH(), "brain.switching", cocoaNumber(1))  selectTab(active) }
  emit "1"
}
func scCommit(self, cmd, sender) {
  if scGet("root") == 0 { scMessage("Open a Git repository first.")  emit "1" }
  let message = msg(scGet("commit"), "stringValue")
  if len(trim(msg(message, "UTF8String"))) == 0 { scMessage("Enter a commit message. Only staged changes will be committed.")  emit "1" }
  let args = scArgs()  scArg(args, "commit")  scArg(args, "-m")  cocoaArrayAdd(args, message)
  scGit(args, "commit")  emit "1"
}
func scNetwork(self, cmd, sender) {
  if scGet("root") == 0 { scMessage("Open a Git repository first.")  emit "1" }
  let mode = msg(cocoaGetAssocKey(sender, "sc.action"), "UTF8String")
  if mode == "pull" { if scCleanEditors() == 0 { emit "1" } }
  let args = scArgs()  scArg(args, mode)
  if mode == "pull" { scArg(args, "--ff-only") }
  scGit(args, mode)  emit "1"
}
func scBranchChanged(self, cmd, note) {
  if brainFlag("sc.updating", 0) == 1 || scGet("task") != 0 { emit "1" }
  let branch = msg(scGet("branches"), "stringValue")
  if msg(branch, "length") == 0 || scGet("root") == 0 { emit "1" }
  if scCleanEditors() == 0 { emit "1" }
  let args = scArgs()  scArg(args, "switch")  scArg(args, "--no-guess")  scArg(args, "--")
  cocoaArrayAdd(args, branch)  scGit(args, "checkout")  emit "1"
}
func scCreateBranch(self, cmd, sender) {
  if scGet("root") == 0 || scCleanEditors() == 0 { emit "1" }
  let name = trim(msg(msg(scGet("newbranch"), "stringValue"), "UTF8String"))
  if name == "" || substring(name, 0, 1) == "-" { scMessage("Enter a valid new branch name.")  emit "1" }
  let args = scArgs()  scArg(args, "switch")  scArg(args, "-c")  scArg(args, name)
  scGit(args, "checkout")  emit "1"
}
func scBrowse(self, cmd, sender) {
  if scGet("root") == 0 { scMessage("Open a Git repository first.")  emit "1" }
  let destination = msg(cocoaGetAssocKey(sender, "sc.action"), "UTF8String")
  scSet("destination", nsString(destination))
  let args = scArgs()  scArg(args, "repo")  scArg(args, "view")  scArg(args, "--json")  scArg(args, "url")  scArg(args, "--jq")  scArg(args, ".url")
  scStart(scGh(), args, "browse", scText("root"))  emit "1"
}
func scRepoName(value) {
  value = trim(value)
  let prefix = "https://github.com/"
  if indexOf(value, prefix) == 0 { value = substring(value, len(prefix), len(value)) }
  if msg_1(nsString(value), "hasSuffix:", nsString(".git")) == 1 { value = substring(value, 0, len(value) - 4) }
  let slash = indexOf(value, "/")
  if slash <= 0 || slash >= len(value) - 1 { emit "" }
  let i = 0
  while i < len(value) {
    let c = charCode(substring(value, i, i + 1))
    if !((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 45 || c == 95 || c == 46 || (c == 47 && i == slash)) { emit "" }
    i = i + 1
  }
  let owner = substring(value, 0, slash)
  let repo = substring(value, slash + 1, len(value))
  if owner == "." || owner == ".." || repo == "." || repo == ".." || substring(owner, 0, 1) == "-" { emit "" }
  emit value
}
func scClone(self, cmd, sender) {
  if scGet("task") != 0 { scMessage("Wait for the current operation.")  emit "1" }
  let repo = scRepoName(msg(msg(scGet("clone"), "stringValue"), "UTF8String"))
  if repo == "" { scMessage("Enter OWNER/REPO or its https://github.com URL.")  emit "1" }
  let parent = chooseFolder()  if parent == "" { emit "1" }
  let target = parent + "/" + substring(repo, indexOf(repo, "/") + 1, len(repo))
  if msg_1(msg(cls("NSFileManager"), "defaultManager"), "fileExistsAtPath:", nsString(target)) == 1 { scMessage("Destination already exists. Choose another parent folder.")  emit "1" }
  scSet("clonetarget", nsString(target))
  let args = scArgs()  scArg(args, "repo")  scArg(args, "clone")  scArg(args, "--")  scArg(args, repo)  scArg(args, target)
  scStart(scGh(), args, "clone", parent)  emit "1"
}
func scCancel(self, cmd, sender) {
  let task = scGet("task")
  if task != 0 { scSet("cancelled", cocoaNumber(1))  msg(task, "terminate")  scMessage("Cancelling…") }
  emit "1"
}
func scReadOutput() {
  let attributes = msg_2(msg(cls("NSFileManager"), "defaultManager"), "attributesOfItemAtPath:error:", scGet("log"), 0)
  let size = msg(msg_1(attributes, "objectForKey:", nsString("NSFileSize")), "unsignedLongLongValue")
  if size > 2097152 { scSet("truncated", cocoaNumber(1))  emit nsString("Output exceeds the 2 MiB preview limit. Review this operation in Stem.") }
  let data = msg_1(cls("NSData"), "dataWithContentsOfFile:", scGet("log"))
  if data == 0 { emit 0 }
  let text = msg_2(msg(cls("NSString"), "alloc"), "initWithData:encoding:", data, 4)
  if text != 0 { emit msg(text, "autorelease") }
  emit 0
}
func scLayout() {
  let panel = scGet("panel")
  if panel == 0 || msg(panel, "isHidden") == 1 { emit "1" }
  let width = msgPointX(panel, "contentSize", 0)
  if width < 829 { width = 829 }
  if width != cocoaNumberVal(scGet("width")) {
    msg_frame(scGet("document"), "setFrame:", 0, 0, width, 630)
    scSet("width", cocoaNumber(width))
  }
  emit "1"
}
func scPoll() {
  scLayout()
  let task = scGet("task")  if task == 0 { emit "1" }
  let mode = scText("mode")
  if msg(task, "isRunning") == 1 {
    let now = msg(cls("NSDate"), "date")
    if msg_1(now, "compare:", scGet("deadline")) == 1 { scCancel(0, 0, 0) }
    if mode == "login" && msg_1(now, "compare:", scGet("loginpoll")) == 1 {
      scSet("loginpoll", msg_d1(cls("NSDate"), "dateWithTimeIntervalSinceNow:", 1))
      let output = scReadOutput()
      if output != 0 { scDisplay(msg(output, "UTF8String")) }
    }
    emit "1"
  }
  let status = msg(task, "terminationStatus")
  let output = scReadOutput()
  let invalid = 0
  if output == 0 { invalid = 1  output = nsString("Output contains binary or invalid UTF-8 data.") }
  let workspace = scGet("workspace")
  msg_1(workspace, "retain")
  let cancelled = cocoaNumberVal(scGet("cancelled"))
  msg(scGet("output"), "closeFile")
  scSet("task", 0)  scSet("output", 0)
  msg_2(msg(cls("NSFileManager"), "defaultManager"), "removeItemAtPath:error:", scGet("temporary"), 0)
  scSet("temporary", 0)  scSet("log", 0)
  let same = msg_1(workspace, "isEqualToString:", nsString(scWorkspace()))
  msg(workspace, "release")
  if cancelled == 1 { scMessage("Operation cancelled. Refresh to check repository state.")  emit "1" }
  if invalid == 1 { scDisplay(msg(output, "UTF8String"))  scMessage("Could not read Git output safely.")  emit "1" }
  if cocoaNumberVal(scGet("truncated")) == 1 { scDisplay(msg(output, "UTF8String"))  scMessage("Output too large to preview. Refresh before further actions.")  emit "1" }
  if mode != "account" && mode != "login" && same == 0 { scRefresh(0, 0, 0)  emit "1" }
  if mode == "account" {
    let value = msg(output, "UTF8String")
    let tab = indexOf(value, "\t")
    if status == 0 && tab > 0 && trim(substring(value, tab + 1, len(value))) == "success" {
      cocoaSetText(scGet("account"), "GitHub: " + substring(value, 0, tab))
      scSidebarAccount(substring(value, 0, tab))
    } else { cocoaSetText(scGet("account"), "GitHub: sign in or retry")  scSidebarAccount("") }
    scRefresh(0, 0, 0)  emit "1"
  }
  if mode == "login" {
    if status == 0 { scAccount() }
    else { scMessage("Sign-in incomplete. Retry when ready.") }
    emit "1"
  }
  if mode == "root" {
    if status != 0 { scMessage("This folder is not inside a Git repository.")  emit "1" }
    scSet("root", nsString(trim(msg(output, "UTF8String"))))
    cocoaSetText(scGet("repository"), scText("root"))
    scStatus()  emit "1"
  }
  if mode == "status" && status == 0 {
    scSet("records", scParseStatus(output))
    cocoaReload(scGet("files"))
    cocoaSetText(scGet("branchlabel"), scText("branchstatus"))
    scReady()
    scBranches()  emit "1"
  }
  if mode == "branches" && status == 0 {
    scSet("updating", cocoaNumber(1))
    let combo = scGet("branches")
    msg(combo, "removeAllItems")
    let lines = msg_1(output, "componentsSeparatedByString:", nsString("\n"))
    let i = 0
    while i < cocoaArrayCount(lines) {
      let line = cocoaArrayGet(lines, i)
      if msg(line, "length") > 0 { msg_1(combo, "addItemWithObjectValue:", line) }
      i = i + 1
    }
    let branch = scText("branchstatus")
    let dots = indexOf(branch, "...")
    if dots >= 0 { branch = substring(branch, 0, dots) }
    msg_1(combo, "setStringValue:", nsString(branch))
    scSet("updating", cocoaNumber(0))
    scReady()  emit "1"
  }
  if mode == "diff" && (status == 0 || status == 1) {
    let text = msg(output, "UTF8String")
    if text == "" { text = "No changes in this version of the selected file." }
    scDisplay(text)  scMessage("Diff ready")  emit "1"
  }
  if mode == "browse" && status == 0 {
    let suffix = scText("destination")
    let url = msg_1(cls("NSURL"), "URLWithString:", nsString(trim(msg(output, "UTF8String")) + suffix))
    if msg_1(msg(url, "scheme"), "isEqualToString:", nsString("https")) == 1 {
      msg_1(msg(cls("NSWorkspace"), "sharedWorkspace"), "openURL:", url)
      scMessage("Opened GitHub in browser")
    }
    emit "1"
  }
  if status != 0 {
    scDisplay(msg(output, "UTF8String"))  scMessage(mode + " failed (" + status + "). See details.")  emit "1"
  }
  if mode == "commit" { msg_1(scGet("commit"), "setStringValue:", nsString("")) }
  if mode == "checkout" || mode == "pull" { scReloadEditors() }
  if mode == "clone" { loadFolder(scText("clonetarget"))  scRefresh(0, 0, 0)  emit "1" }
  scDisplay(msg(output, "UTF8String"))
  scMessage(mode + " completed")  scStatus()
  emit "1"
}
func scLabel(win, parent, title, x, y, width, height, mask) {
  let label = cocoaPlainLabel(win, title, x, y, width, height)
  moveView(label, parent, x, y, width, height, mask)
  cocoaSetFont(label, cocoaMonoFont(11))  cocoaSetTextColor(label, themeText())
  emit label
}
func scButton(win, parent, title, x, y, width, action, key, value, mask) {
  let button = cocoaButton(win, title, x, y, width, 28)
  moveView(button, parent, x, y, width, 28, mask)
  msg_1(button, "setBezelStyle:", 1)
  cocoaOnClickKeyed(button, "sc-" + key, action)
  cocoaSetAssocKey(button, "sc.action", nsString(value))
  emit button
}
func scInstall(win, parent) {
  let app = appH()
  scInstallSidebar(win)
  let scroll = msg_frame(msg(cls("NSScrollView"), "alloc"), "initWithFrame:", 0, 0, 829, 466)
  msg_1(scroll, "setAutoresizingMask:", 18)
  msg_1(scroll, "setHasVerticalScroller:", 1)
  msg_1(scroll, "setHasHorizontalScroller:", 1)
  msg_1(scroll, "setBackgroundColor:", themeCanvas())
  let c = cocoaViewClassNew("BrainSourceControlDocument")
  cocoaClassAddMethod(c, "isFlipped", funcptr(rulerFlipped), "c@:")  cocoaClassRegister(c)
  let doc = msg_frame(msg(c, "alloc"), "initWithFrame:", 0, 0, 829, 630)
  scSet("document", doc)  scSet("width", cocoaNumber(829))
  themeSurface(doc, themeCanvas(), 0)
  msg_1(scroll, "setDocumentView:", doc)  msg_1(parent, "addSubview:", scroll)
  scSet("panel", scroll)  msg_1(scroll, "setHidden:", 1)
  scLabel(win, doc, "GITHUB & SOURCE CONTROL", 16, 12, 480, 22, 2)
  scSet("account", scLabel(win, doc, "GitHub: checking account…", 16, 42, 480, 22, 2))
  scButton(win, doc, "Editor", 714, 12, 96, funcptr(onSourceControl), "editor", "", 1)
  scSet("repository", scLabel(win, doc, "Open a repository folder", 16, 102, 790, 22, 2))
  scButton(win, doc, "Refresh", 714, 42, 96, funcptr(scRefreshAccount), "refresh", "", 1)
  let branches = cocoaComboBox(win, 16, 70, 240, 26)
  moveView(branches, doc, 16, 70, 240, 26, 0)
  msg_1(branches, "setEditable:", 0)  scSet("branches", branches)
  let delegateClass = cocoaClassNew("BrainSourceControlDelegate")
  cocoaClassAddMethod(delegateClass, "numberOfRowsInTableView:", funcptr(scRows), "q@:@")
  cocoaClassAddMethod(delegateClass, "tableView:objectValueForTableColumn:row:", funcptr(scValue), "@@:@@q")
  cocoaClassAddMethod(delegateClass, "tableViewSelectionDidChange:", funcptr(scSelection), "v@:@")
  cocoaClassAddMethod(delegateClass, "comboBoxSelectionDidChange:", funcptr(scBranchChanged), "v@:@")
  cocoaClassRegister(delegateClass)
  let delegate = cocoaNew(delegateClass)  scSet("delegate", delegate)  msg(delegate, "release")
  msg_1(branches, "setDelegate:", scGet("delegate"))
  let branchInput = cocoaTextField(win, 274, 70, 420, 26)
  moveView(branchInput, doc, 274, 70, 420, 26, 2)
  msg_1(branchInput, "setPlaceholderString:", nsString("New branch name"))  scSet("newbranch", branchInput)
  scButton(win, doc, "Create Branch", 706, 70, 104, funcptr(scCreateBranch), "newbranch", "", 1)
  scSet("branchlabel", scLabel(win, doc, "", 16, 192, 790, 22, 2))
  scButton(win, doc, "Fetch", 16, 132, 64, funcptr(scNetwork), "fetch", "fetch", 0)
  scButton(win, doc, "Pull", 88, 132, 64, funcptr(scNetwork), "pull", "pull", 0)
  scButton(win, doc, "Push", 160, 132, 64, funcptr(scNetwork), "push", "push", 0)
  scButton(win, doc, "Repository", 252, 132, 100, funcptr(scBrowse), "repo", "", 0)
  scButton(win, doc, "Pull Requests", 364, 132, 116, funcptr(scBrowse), "prs", "/pulls", 0)
  scButton(win, doc, "Issues", 492, 132, 80, funcptr(scBrowse), "issues", "/issues", 0)
  scButton(win, doc, "Stage All", 714, 132, 96, funcptr(scStageAll), "stageall", "", 1)
  let clone = cocoaTextField(win, 16, 166, 678, 26)
  moveView(clone, doc, 16, 166, 678, 26, 2)
  msg_1(clone, "setPlaceholderString:", nsString("Clone GitHub repository: OWNER/REPO or HTTPS URL"))  scSet("clone", clone)
  scButton(win, doc, "Clone…", 706, 166, 104, funcptr(scClone), "clone", "", 1)
  let files = cocoaTable(win, 16, 220, 260, 250)
  moveView(msg(files, "enclosingScrollView"), doc, 16, 220, 260, 250, 0)
  msg_1(files, "setHeaderView:", 0)  msg_d1(files, "setRowHeight:", 24)
  cocoaSetBg(files, themeSidebar())  cocoaSetDataSource(files, scGet("delegate"))
  msg_1(files, "setDelegate:", scGet("delegate"))  scSet("files", files)  scSet("records", cocoaArray())
  let diff = cocoaScrollText(win, 292, 220, 518, 250)
  moveView(msg(diff, "enclosingScrollView"), doc, 292, 220, 518, 250, 2)
  cocoaSetBg(diff, themeCanvas())  cocoaSetTextColor(diff, themeText())
  cocoaSetFont(diff, cocoaMonoFont(12))  msg_1(diff, "setEditable:", 0)
  cocoaTVNoWrap(diff)  scSet("diff", diff)
  scDisplay("Select a changed file to review its diff.\n\nCommits include staged changes only. Pull uses fast-forward only.")
  scButton(win, doc, "Stage", 16, 482, 80, funcptr(scStage), "stage", "", 0)
  scButton(win, doc, "Unstage", 106, 482, 80, funcptr(scUnstage), "unstage", "", 0)
  scButton(win, doc, "Open", 196, 482, 80, funcptr(scOpenFile), "open", "", 0)
  scButton(win, doc, "Working Diff", 292, 482, 120, funcptr(scWorkingDiff), "workingdiff", "", 0)
  scButton(win, doc, "Staged Diff", 424, 482, 120, funcptr(scStagedDiff), "stageddiff", "", 0)
  let commit = cocoaTextField(win, 16, 526, 644, 48)
  moveView(commit, doc, 16, 526, 644, 48, 2)
  msg_1(commit, "setPlaceholderString:", nsString("Commit message — staged changes only"))
  scSet("commit", commit)
  scButton(win, doc, "Commit Staged", 672, 536, 138, funcptr(scCommit), "commit", "", 1)
  scSet("message", scLabel(win, doc, "Ready", 16, 590, 684, 28, 2))
  scButton(win, doc, "Cancel", 714, 588, 96, funcptr(scCancel), "cancel", "", 1)
  emit "1"
}
func onSourceControl(self, cmd, sender) {
  if storeEdition() == 1 { emit "1" }
  let panel = scGet("panel")
  let hidden = msg(panel, "isHidden")
  msg_1(panel, "setHidden:", 1 - hidden)
  if hidden == 1 { scAccount() }
  else { cocoaMakeFirstResponder(cocoaGetAssocKey(appH(), "brain.win"), cocoaGetAssocKey(appH(), "brain.editor")) }
  emit "1"
}

// Native regression fixtures: no Git operation below touches the working repo.
func scTestRun(args, directory) {
  regressionAssert(scStart("/usr/bin/git", args, "regression", directory) == 1, "Git fixture task launches")
  regressionAssert(msg_1(scGet("deadline"), "compare:", msg(cls("NSDate"), "date")) == 1, "Git operation deadline remains in the future")
  let task = scGet("task")  msg(task, "waitUntilExit")
  let status = msg(task, "terminationStatus")
  let output = scReadOutput()
  msg(scGet("output"), "closeFile")  scSet("task", 0)  scSet("output", 0)
  msg_2(msg(cls("NSFileManager"), "defaultManager"), "removeItemAtPath:error:", scGet("temporary"), 0)
  scSet("temporary", 0)  scSet("log", 0)
  regressionAssert(status == 0, "Git fixture operation succeeds")
  emit output
}
func scTestGit(command, directory) {
  let args = msg_1(nsString(command), "componentsSeparatedByString:", nsString("|"))
  emit scTestRun(args, directory)
}
func scTestCompletion() {
  let steps = 0
  while scGet("task") != 0 && steps < 12 {
    msg(scGet("task"), "waitUntilExit")
    scPoll()
    steps = steps + 1
  }
  regressionAssert(scGet("task") == 0, "Git completion chain becomes idle")
  regressionAssert(indexOf(cocoaGetText(scGet("message")), "Running ") < 0, "Finished Git task clears progress status")
  regressionAssert(indexOf(cocoaGetText(scGet("message")), "changed files") >= 0, "Git operation finishes with refreshed repository status")
  emit "1"
}
func sourceControlRegression() {
  regressionAssert(scRepoName("t3m3d/kcode") == "t3m3d/kcode", "GitHub owner/repo accepted")
  regressionAssert(scRepoName("https://github.com/t3m3d/kcode.git") == "t3m3d/kcode", "GitHub HTTPS URL normalized")
  regressionAssert(scRepoName("../repo") == "", "Clone traversal rejected")
  regressionAssert(scRepoName("owner/repo/../../escape") == "", "Clone extra path rejected")
  regressionAssert(scRepoName("--upload-pack=bad/repo") == "", "Clone option injection rejected")
  regressionAssert(scRepoName("https://evil.example/owner/repo") == "", "Clone requires GitHub destination")
  let fm = msg(cls("NSFileManager"), "defaultManager")
  let directory = msg(msg(msg(fm, "temporaryDirectory"), "path"), "UTF8String") + "/brain-scm-test-" + msg(msg(msg(cls("NSUUID"), "UUID"), "UUIDString"), "UTF8String")
  msg_4(fm, "createDirectoryAtPath:withIntermediateDirectories:attributes:error:", nsString(directory), 0, 0, 0)
  scTestGit("init|-b|main", directory)
  scTestGit("config|user.name|Brain regression", directory)
  scTestGit("config|user.email|brain-test@example.invalid", directory)
  scTestGit("config|commit.gpgsign|false", directory)
  let unusual = "note space 🦋.txt"
  writeDocument(directory + "/" + unusual, nsString("fixture\n"))
  writeDocument(directory + "/line\nbreak.txt", nsString("keep unstaged\n"))
  writeDocument(directory + "/--literal.txt", nsString("keep unstaged too\n"))
  let output = scTestGit("status|--porcelain=v1|-z|--branch", directory)
  let records = scParseStatus(output)
  regressionAssert(cocoaArrayCount(records) == 3, "NUL status parses Unicode, spaces, newline, and option-like paths")
  regressionAssert(brainFlag("sc.unborn", 0) == 1, "Unborn branch detected")
  let target = 0  let i = 0
  while i < cocoaArrayCount(records) {
    let record = cocoaArrayGet(records, i)
    if msg_1(msg_1(record, "objectForKey:", nsString("path")), "isEqualToString:", nsString(unusual)) == 1 { target = record }
    i = i + 1
  }
  regressionAssert(target != 0, "Unusual filename retained exactly")
  let args = scArgs()  scArg(args, "add")  scPathArgs(args, target)  scTestRun(args, directory)
  args = scArgs()  scArg(args, "rm")  scArg(args, "--cached")  scPathArgs(args, target)  scTestRun(args, directory)
  regressionAssert(msg_1(fm, "fileExistsAtPath:", nsString(directory + "/" + unusual)) == 1, "Unstage on unborn branch preserves file")
  args = scArgs()  scArg(args, "add")  scPathArgs(args, target)  scTestRun(args, directory)
  scTestGit("commit|-m|Fixture commit", directory)
  output = scTestGit("show|--pretty=format:|--name-only|HEAD", directory)
  regressionAssert(msg_1(output, "containsString:", nsString("literal")) == 0, "Commit excludes unstaged files")
  msg_3(fm, "moveItemAtPath:toPath:error:", nsString(directory + "/" + unusual), nsString(directory + "/renamed 'file'.txt"), 0)
  scTestGit("add|--all|--|.", directory)
  records = scParseStatus(scTestGit("status|--porcelain=v1|-z|--branch", directory))
  let rename = 0  i = 0
  while i < cocoaArrayCount(records) {
    let record = cocoaArrayGet(records, i)
    if msg_1(record, "objectForKey:", nsString("old")) != 0 { rename = record }
    i = i + 1
  }
  regressionAssert(rename != 0, "Rename source and destination parsed")
  regressionAssert(msg_1(msg_1(rename, "objectForKey:", nsString("old")), "isEqualToString:", nsString(unusual)) == 1, "Rename source exact")
  args = scArgs()  scArg(args, "restore")  scArg(args, "--staged")  scPathArgs(args, rename)
  regressionAssert(cocoaArrayCount(args) == 5, "Rename unstage includes both paths after option separator")
  scTestRun(args, directory)
  regressionAssert(msg_1(fm, "fileExistsAtPath:", nsString(directory + "/renamed 'file'.txt")) == 1, "Rename unstage preserves working file")
  scTestGit("switch|-c|codex/scm-test", directory)
  output = scTestGit("branch|--show-current", directory)
  regressionAssert(trim(msg(output, "UTF8String")) == "codex/scm-test", "Create and switch branch works")
  scTestGit("switch|--no-guess|--|main", directory)
  output = scTestGit("branch|--show-current", directory)
  regressionAssert(trim(msg(output, "UTF8String")) == "main", "Select existing branch works")
  let origin = directory + "/origin.git"
  let peer = directory + "/peer"
  scTestGit("init|--bare|origin.git", directory)
  args = scArgs()  scArg(args, "remote")  scArg(args, "add")  scArg(args, "origin")  scArg(args, origin)
  scTestRun(args, directory)
  scTestGit("push|-u|origin|main", directory)
  scTestGit("clone|--branch|main|--|origin.git|peer", directory)
  scTestGit("config|user.name|Brain peer", peer)
  scTestGit("config|user.email|brain-peer@example.invalid", peer)
  scTestGit("config|commit.gpgsign|false", peer)
  writeDocument(peer + "/remote.txt", nsString("remote fixture\n"))
  scTestGit("add|--|remote.txt", peer)
  scTestGit("commit|-m|Peer fixture", peer)
  scTestGit("push", peer)
  let previous = cocoaGetAssocKey(appH(), "brain.dir")  msg(previous, "retain")
  cocoaSetAssocKey(appH(), "brain.dir", nsString(directory))
  scSet("root", nsString(directory))
  scSet("message", cocoaPlainLabel(cocoaGetAssocKey(appH(), "brain.win"), "", 0, 0, 500, 22))
  scSet("branches", allocInit("NSComboBox"))
  saveCurTab()
  let texts = cocoaGetAssocKey(appH(), "brain.tabtexts")
  let saved = cocoaGetAssocKey(appH(), "brain.savedtexts")
  i = 0
  while i < cocoaArrayCount(texts) { cocoaArraySet(saved, i, cocoaArrayGet(texts, i))  i = i + 1 }
  let sender = allocInit("NSButton")
  let editor = cocoaGetAssocKey(appH(), "brain.editor")
  let original = msg(msg(editor, "string"), "copy")
  cocoaTVSetString(editor, msg(original, "UTF8String") + "\nunsaved fixture")
  cocoaSetAssocKey(sender, "sc.action", nsString("pull"))
  scNetwork(0, 0, sender)
  regressionAssert(scGet("task") == 0, "Pull refuses unsaved editor contents")
  cocoaTVSetString(editor, msg(original, "UTF8String"))  msg(original, "release")
  saveCurTab()
  cocoaSetAssocKey(sender, "sc.action", nsString("fetch"))
  scNetwork(0, 0, sender)  scTestCompletion()
  cocoaSetAssocKey(sender, "sc.action", nsString("pull"))
  scNetwork(0, 0, sender)  scTestCompletion()
  regressionAssert(msg_1(fm, "fileExistsAtPath:", nsString(directory + "/remote.txt")) == 1, "Fast-forward pull receives remote file")
  cocoaSetAssocKey(sender, "sc.action", nsString("push"))
  scNetwork(0, 0, sender)  scTestCompletion()
  regressionAssert(msg(msg(scGet("branches"), "stringValue"), "UTF8String") == "main", "Branch picker refreshed after network task")
  msg(sender, "release")
  cocoaSetAssocKey(appH(), "brain.dir", previous)  msg(previous, "release")
  scSet("root", 0)  scSet("branches", 0)  scSet("message", 0)
  kp("PASS: Git fetch, fast-forward pull, push, branch selection, completed status against local origin")
  msg_2(fm, "removeItemAtPath:error:", nsString(directory), 0)
  kp("PASS: Git status paths, staging, unborn unstage, staged-only commit, rename, branches, clone validation")
  emit "1"
}
