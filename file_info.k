// Local, bounded file-role inspection. Never executes the selected file.
import "k:cocoa"
import "k:objc"

func infoGet(key) { emit cocoaGetAssocKey(appH(), "info." + key) }
func infoSet(key, value) { cocoaSetAssocKey(appH(), "info." + key, value)  emit 1 }
func infoRegex(pattern) {
  let cached = infoGet("regex." + pattern)
  if cached != 0 { emit cached }
  let expression = msg_3(cls("NSRegularExpression"), "regularExpressionWithPattern:options:error:", nsString(pattern), 0, 0)
  infoSet("regex." + pattern, expression)
  emit expression
}
func infoHits(pattern, text) {
  let size = msg(text, "length")
  if size > 131072 { size = 131072 }
  emit msg_4(infoRegex(pattern), "matchesInString:options:range:", text, 0, 0, size)
}
func infoHas(pattern, text) { emit cocoaArrayCount(infoHits(pattern, text)) > 0 }
func infoLanguage(ext) {
  if ext == "k" || ext == "ks" { emit "Krypton / Objective K" }
  if ext == "h" || ext == "c" { emit "C / Objective-C" }
  if ext == "hpp" || ext == "hh" || ext == "hxx" || ext == "cpp" || ext == "cc" || ext == "cxx" { emit "C++" }
  if ext == "m" || ext == "mm" { emit "Objective-C / Objective-C++" }
  if ext == "swift" { emit "Swift" }
  if ext == "py" { emit "Python" }
  if ext == "js" || ext == "jsx" || ext == "mjs" || ext == "cjs" { emit "JavaScript" }
  if ext == "ts" || ext == "tsx" { emit "TypeScript" }
  if ext == "rs" { emit "Rust" }
  if ext == "go" { emit "Go" }
  if ext == "sh" || ext == "zsh" || ext == "bash" { emit "Shell" }
  if ext == "md" || ext == "rst" { emit "Documentation" }
  if ext == "json" || ext == "toml" || ext == "yaml" || ext == "yml" || ext == "plist" || ext == "xml" || ext == "ini" { emit "Structured data / configuration" }
  if ext == "html" || ext == "htk" { emit "Markup" }
  if ext == "css" || ext == "scss" { emit "Stylesheet" }
  if ext == "txt" || ext == "" { emit "Plain text / unrecognized" }
  emit ext
}
func infoCode(text) {
  let size = msg(text, "length")
  if size > 131072 { size = 131072 }
  let sample = msg_1(text, "substringToIndex:", size)
  // Preserve import strings; ignore C-style comments and standalone hash comments.
  let expression = infoRegex("(?s:/\\*.*?\\*/)|(?m:^[ \\t]*(?://|#(?!include|import|!)).*$)")
  emit msg_5(expression, "stringByReplacingMatchesInString:options:range:withTemplate:", sample, 0, 0, msg(sample, "length"), nsString(""))
}
func infoRole(path, text) {
  let lower = msg(msg(nsString(path), "lowercaseString"), "UTF8String")
  let name = baseName(lower)
  let ext = extOf(lower)
  let code = infoCode(text)
  let role = "Text file"
  let purpose = "Stores text. No more specific role was identified."
  let evidence = "File extension and local source patterns."
  if ext == "k" || ext == "ks" || ext == "c" || ext == "cpp" || ext == "cc" || ext == "cxx" || ext == "m" || ext == "mm" || ext == "swift" || ext == "py" || ext == "js" || ext == "jsx" || ext == "ts" || ext == "tsx" || ext == "mjs" || ext == "cjs" || ext == "go" || ext == "rs" {
    role = "Source module"
    purpose = "Contains implementation or reusable definitions used by other project files."
  }
  if ext == "json" || ext == "toml" || ext == "yaml" || ext == "yml" || ext == "ini" || ext == "plist" || ext == "xml" || ext == "entitlements" || name == ".env" || name == ".gitignore" {
    role = "Configuration / data"
    purpose = "Stores settings, metadata, or structured data read by an app or tool."
  }
  if ext == "html" || ext == "htk" { role = "Page / template"  purpose = "Defines document structure or an interface rendered by a browser or app." }
  if ext == "css" || ext == "scss" { role = "Stylesheet"  purpose = "Controls visual presentation, spacing, colors, and layout." }
  if ext == "md" || ext == "rst" || startsWith(name, "readme") || startsWith(name, "license") || startsWith(name, "changelog") {
    role = "Documentation"
    purpose = "Explains the project, its usage, licensing, or changes."
  }
  if ext == "sh" || ext == "zsh" || ext == "bash" || ext == "ks" {
    role = "Script / program"
    purpose = "Runs a sequence of operations when invoked by the runtime or shell."
  }
  if ext == "h" || ext == "hh" || ext == "hpp" || ext == "hxx" {
    role = "Header / interface"
    purpose = "Exposes declarations, types, macros, and possibly inline definitions for other source files."
    evidence = "Header extension ." + ext + "; may contain implementation too."
  } else {
    if infoHas("(?m)^\\s*(?:(?:int|void|auto)\\s+main\\s*\\(|(?:pub\\s+)?(?:fn|func)\\s+main\\s*\\(|just\\s+run\\b|if\\s+__name__\\s*==|@main\\b)", code) == 1 {
      role = "Main program / entry point"
      purpose = "Contains a startup entry pattern that can begin program execution."
      evidence = "Detected main/startup syntax in source; execution is not verified."
    } else {
      if name == "main.k" || name == "main.ks" || name == "main.c" || name == "main.cpp" || name == "main.py" || name == "main.swift" || name == "index.js" || name == "index.ts" {
        role = "Likely entry module"
        purpose = "May assemble or start the application; this is a filename convention."
        evidence = "Conventional entry filename; no recognized startup syntax found."
      }
    }
  }
  if name == "package.json" || name == "cargo.toml" || name == "pyproject.toml" || name == "go.mod" {
    role = "Project manifest"
    purpose = "Describes package identity, dependencies, and build/runtime settings."
    evidence = "Recognized project manifest filename."
  }
  if name == "makefile" || name == "cmakelists.txt" || startsWith(name, "build.") || startsWith(name, "release.") {
    role = "Build / release automation"
    purpose = "Coordinates compilation, packaging, or release steps for the project."
    evidence = "Recognized build/release filename convention."
  }
  if indexOf(lower, "/tests/") >= 0 || indexOf(lower, "/test/") >= 0 || startsWith(name, "test_") || indexOf(name, "_test.") >= 0 || indexOf(name, ".test.") >= 0 || indexOf(name, ".spec.") >= 0 {
    role = "Test file"
    purpose = "Checks behavior with fixtures, assertions, or automated scenarios."
    evidence = "Test directory or filename convention."
  }
  if indexOf(lower, "/generated/") >= 0 || infoHas("(?im)^\\s*(?://|#|/\\*)?\\s*(?:auto[ -]?generated|generated file|do not edit)\\b", text) == 1 {
    role = "Likely generated file"
    purpose = "Appears to be produced by tooling; edit its generator or source template when appropriate."
    evidence = "Generated directory or source marker; inferred locally."
  }
  emit role + "\n\n" + purpose + "\n\nWHY\n" + evidence
}
func infoList(pattern, text) {
  let hits = infoHits(pattern, text)
  let output = ""
  let i = 0
  while i < cocoaArrayCount(hits) && i < 8 {
    let hit = cocoaArrayGet(hits, i)
    let value = msg_4(infoRegex(pattern), "replacementStringForResult:inString:offset:template:", hit, text, 0, nsString("$0"))
    let line = msg(msg_1(value, "stringByTrimmingCharactersInSet:", msg(cls("NSCharacterSet"), "whitespaceAndNewlineCharacterSet")), "UTF8String")
    output = output + "• " + ccClip(line, 96) + "\n"
    i = i + 1
  }
  if cocoaArrayCount(hits) > 8 { output = output + "… " + (cocoaArrayCount(hits) - 8) + " more\n" }
  if i == 0 { output = "None recognized in scanned source.\n" }
  emit output
}
func infoSummary(path, text) {
  let code = infoCode(text)
  let report = baseName(path) + "\n\n" + infoRole(path, text)
  report = report + "\n\nLANGUAGE\n" + infoLanguage(extOf(msg(msg(nsString(path), "lowercaseString"), "UTF8String")))
  report = report + "\n\nSIZE\n" + msg_1(text, "lengthOfBytesUsingEncoding:", 4) + " UTF-8 bytes"
  if msg(text, "length") <= 131072 { report = report + "\n" + cocoaArrayCount(msg_1(text, "componentsSeparatedByString:", nsString("\n"))) + " lines" }
  report = report + "\n\nIMPORTS / INCLUDES\n" + infoList("(?m)^[ \\t]*(?:import\\b|from\\s+\\S+\\s+import\\b|#\\s*(?:include|import)\\b|use\\s+|require\\s*\\().*$", code)
  report = report + "\nDECLARATIONS\n" + infoList("(?m)^[ \\t]*(?:(?:export|pub|public|private|static|async)\\s+)*(?:(?:func|fn|def|function|class|struct|enum|interface|trait|module|type|method)\\s+|objk\\s+(?:object|protocol)\\s+)[A-Za-z_$][A-Za-z0-9_$]*[^\\n]*", code)
  report = report + "\nPATH\n" + path
  report = report + "\n\nLocal inference from filename and source; not a verified description of runtime behavior. Uses current editor contents, including unsaved edits."
  if msg(text, "length") > 131072 { report = report + "\nLarge file: analysis covers only its first portion." }
  emit report
}
func infoRefresh() {
  if infoGet("text") == 0 || brainFlag("brain.fileinfo", 1) == 0 || brainFlag("brain.switching", 0) == 1 { emit 1 }
  let path = cocoaGetAssocKey(appH(), "brain.curpath")
  let text = msg(cocoaGetAssocKey(appH(), "brain.editor"), "string")
  if path == 0 { cocoaTVSetString(infoGet("text"), "Select a file to see its purpose and details.")  emit 1 }
  if infoGet("last-path") != 0 && msg_1(path, "isEqualToString:", infoGet("last-path")) == 1 && msg_1(text, "isEqualToString:", infoGet("last-text")) == 1 { emit 1 }
  cocoaTVSetString(infoGet("text"), infoSummary(msg(path, "UTF8String"), text))
  infoSet("last-path", path)
  infoSet("last-text", msg(msg(text, "copy"), "autorelease"))
  msg_d2(msg(msg(infoGet("text"), "enclosingScrollView"), "contentView"), "scrollToPoint:", 0, 0)
  emit 1
}
func onFileInfo(self, cmd, sender) {
  let visible = 1 - brainFlag("brain.fileinfo", 1)
  cocoaSetAssocKey(appH(), "brain.fileinfo", cocoaNumber(visible))
  msg_1(infoGet("pane"), "setHidden:", 1 - visible)
  msg(cocoaGetAssocKey(appH(), "brain.hsplit"), "adjustSubviews")
  infoSet("last-path", 0)  infoRefresh()
  emit 1
}
func infoInstall(win, split) {
  let panel = pane(split, 780, 0, 260, 698, 16)
  themeSurface(panel, themeSidebar(), 0)
  let title = cocoaPlainLabel(win, "FILE INFO", 12, 670, 200, 24)
  moveView(title, panel, 12, 670, 200, 24, 10)
  cocoaSetFont(title, msg_d1(cls("NSFont"), "boldSystemFontOfSize:", 11))
  cocoaSetTextColor(title, themeToolbarPurple())
  let close = cocoaButton(win, "×", 226, 670, 26, 24)
  moveView(close, panel, 226, 670, 26, 24, 9)
  msg_1(close, "setBordered:", 0)
  msg_1(close, "setToolTip:", nsString("Hide File Info; reopen from View"))
  cocoaOnClickKeyed(close, "file-info-close", funcptr(onFileInfo))
  let text = cocoaScrollText(win, 0, 0, 260, 664)
  moveView(msg(text, "enclosingScrollView"), panel, 0, 0, 260, 664, 18)
  msg_1(text, "setEditable:", 0)  msg_1(text, "setSelectable:", 1)
  msg_1(text, "setRichText:", 0)
  msg_1(text, "setAutoresizingMask:", 2)
  msg_1(text, "setVerticallyResizable:", 1)
  msg_1(text, "setHorizontallyResizable:", 0)
  msg_1(msg(text, "textContainer"), "setWidthTracksTextView:", 1)
  msg_d2(text, "setTextContainerInset:", 12, 10)
  cocoaSetFont(text, msg_d1(cls("NSFont"), "systemFontOfSize:", 12))
  cocoaSetBg(text, themeSidebar())  cocoaSetTextColor(text, themeText())
  cocoaTVSetString(text, "Select a file to see its purpose and details.")
  infoSet("pane", panel)  infoSet("text", text)
  msg(split, "adjustSubviews")
  emit 1
}
func infoRegression() {
  regressionAssert(startsWith(infoRole("/src/types.hpp", nsString("int main();")), "Header / interface"), "Header role wins over main declaration")
  regressionAssert(startsWith(infoRole("/src/app.k", nsString("just run { print(1) }")), "Main program / entry point"), "Krypton entry point identified")
  regressionAssert(startsWith(infoRole("/src/util.c", nsString("/* int main() {} */\nint helper() {}")), "Source module"), "Commented main is not an entry point")
  regressionAssert(startsWith(infoRole("/tests/main.py", nsString("if __name__ == '__main__':\n pass")), "Test file"), "Test convention takes precedence")
  regressionAssert(startsWith(infoRole("/project/package.json", nsString("{}")), "Project manifest"), "Manifest purpose identified")
  regressionAssert(startsWith(infoRole("/generated/api.k", nsString("")), "Likely generated file"), "Generated role is qualified")
  regressionAssert(indexOf(infoSummary("/src/model.k", nsString("import \"k:cocoa\"\nfunc sample() {}")), "func sample") >= 0, "Summary includes declarations")
  print("PASS: File Info roles, comments, entry patterns, manifests, declarations")
  emit 1
}
