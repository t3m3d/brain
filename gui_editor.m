// gui_editor.m — kcode, a native macOS editor for Krypton (.k / .ks).
//
// A real Cocoa app: NSTextView gives native editing, selection, scrolling,
// undo/redo, find, cut/copy/paste. We add: Krypton syntax highlighting, a File
// menu (New/Open/Save/Save As/Close), a line-number ruler, and Build/Run via the
// Krypton compiler `kcc`. The compiler + the language are Krypton; this shim is
// the native window + text surface.
//
// Build: clang -framework Cocoa -fobjc-arc -O2 gui_editor.m -o kcode-gui

#import <Cocoa/Cocoa.h>

static NSFont *gFont;
static NSColor *gBg, *gFg, *gKw, *gBuiltin, *gStr, *gCm, *gNum, *gType;
static NSString *_shq(NSString *s);   // shell-quote (defined below)

// ── Krypton token sets (mirrors kcode's highlighter) ───────────────────────
static NSSet *gKwSet, *gBuiltinSet;
static void initSyntax(void) {
    NSArray *kw = @[@"just",@"go",@"run",@"func",@"fn",@"let",@"const",@"emit",@"return",
        @"if",@"else",@"while",@"do",@"loop",@"until",@"for",@"in",@"match",@"struct",
        @"class",@"type",@"callback",@"try",@"catch",@"throw",@"module",@"import",@"export",
        @"jxt",@"cfunc",@"true",@"false",@"null",@"and",@"or",@"not",@"break",@"continue"];
    NSArray *bi = @[@"print",@"kp",@"printErr",@"readFile",@"writeFile",@"arg",@"argCount",
        @"exit",@"readLine",@"input",@"shellRun",@"exec",@"environ",@"len",@"substring",
        @"startsWith",@"endsWith",@"contains",@"indexOf",@"replace",@"trim",@"toUpper",
        @"toLower",@"reverse",@"repeat",@"charCode",@"fromCharCode",@"isDigit",@"isAlpha",
        @"toInt",@"parseInt",@"toStr",@"abs",@"pow",@"min",@"max",@"sqrt",@"floor",@"ceil",
        @"round",@"split",@"splitBy",@"join",@"sort",@"unique",@"range",@"keys",@"values",
        @"sbNew",@"sbAppend",@"sbToString",@"getLine",@"lineCount",@"type",@"assert",
        @"fdRead",@"fdWrite",@"fdClose",@"sleepUs",@"ptyMaster",@"ptyForkExec"];
    gKwSet = [NSSet setWithArray:kw];
    gBuiltinSet = [NSSet setWithArray:bi];
}

// ── TextMate grammar engine (drives highlighting from a VS Code extension) ──
static NSColor *scopeColor(NSString *sc) {
    if (!sc) return nil;
    if ([sc hasPrefix:@"comment"]) return gCm;
    if ([sc hasPrefix:@"string"]) return gStr;
    if ([sc hasPrefix:@"constant.numeric"]) return gNum;
    if ([sc hasPrefix:@"constant"] || [sc hasPrefix:@"support.constant"]) return gNum;
    if ([sc hasPrefix:@"keyword"] || [sc hasPrefix:@"storage"]) return gKw;
    if ([sc hasPrefix:@"variable.language"]) return gKw;
    if ([sc hasPrefix:@"entity.name.function"] || [sc hasPrefix:@"support.function"] || [sc hasPrefix:@"meta.function-call"]) return gBuiltin;
    if ([sc hasPrefix:@"entity.name.type"] || [sc hasPrefix:@"support.type"] || [sc hasPrefix:@"entity.name.class"] || [sc hasPrefix:@"support.class"]) return gType;
    return nil;
}

@interface TMRule : NSObject
@property NSRegularExpression *re;     // match, or begin
@property NSRegularExpression *end;    // nil for a plain match rule
@property NSString *scope, *contentScope;
@property NSDictionary *caps, *beginCaps, *endCaps;   // @(idx) -> scope string
@property NSArray<TMRule *> *subs;
@end
@implementation TMRule @end

static NSRegularExpression *tmRe(NSString *p) {
    if (!p) return nil;
    NSError *e = nil;
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:p options:0 error:&e];
    return r;   // nil on incompatible (Oniguruma-only) patterns -> rule skipped
}
static NSDictionary *tmCaps(NSDictionary *c) {
    if (!c) return nil;
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSString *k in c) { NSString *nm = c[k][@"name"]; if (nm) m[@([k intValue])] = nm; }
    return m;
}

@interface TMGrammar : NSObject
@property NSArray<TMRule *> *rules;
@property NSDictionary *repo;        // name -> raw json
@property NSMutableDictionary *cache;
@end
@implementation TMGrammar
static NSArray<TMRule *> *tmCompile(NSArray *raw, TMGrammar *g, int depth);
- (NSArray<TMRule *> *)resolve:(NSString *)inc depth:(int)depth {
    if (depth > 12) return @[];
    if ([inc isEqualToString:@"$self"]) return self.rules;
    if ([inc hasPrefix:@"#"]) {
        NSString *nm = [inc substringFromIndex:1];
        if (self.cache[nm]) return self.cache[nm];
        self.cache[nm] = @[];                                   // cycle guard
        id rep = self.repo[nm]; if (!rep) return @[];
        NSArray *raw = rep[@"patterns"] ?: @[rep];
        NSArray *r = tmCompile(raw, self, depth+1);
        self.cache[nm] = r; return r;
    }
    return @[];
}
@end

static NSArray<TMRule *> *tmCompile(NSArray *raw, TMGrammar *g, int depth) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        NSString *inc = d[@"include"];
        if (inc) { [out addObjectsFromArray:[g resolve:inc depth:depth]]; continue; }
        TMRule *r = [TMRule new];
        r.scope = d[@"name"]; r.contentScope = d[@"contentName"];
        if (d[@"match"]) { r.re = tmRe(d[@"match"]); r.caps = tmCaps(d[@"captures"]); if (!r.re) continue; }
        else if (d[@"begin"]) {
            r.re = tmRe(d[@"begin"]); r.end = tmRe(d[@"end"]);
            r.beginCaps = tmCaps(d[@"beginCaptures"] ?: d[@"captures"]);
            r.endCaps = tmCaps(d[@"endCaptures"] ?: d[@"captures"]);
            r.subs = d[@"patterns"] ? tmCompile(d[@"patterns"], g, depth+1) : @[];
            if (!r.re) continue;
        } else continue;
        [out addObject:r];
    }
    return out;
}

static TMGrammar *tmLoad(NSString *jsonPath) {
    NSData *data = [NSData dataWithContentsOfFile:jsonPath]; if (!data) return nil;
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![j isKindOfClass:[NSDictionary class]]) return nil;
    TMGrammar *g = [TMGrammar new]; g.repo = j[@"repository"] ?: @{}; g.cache = [NSMutableDictionary dictionary];
    g.rules = tmCompile(j[@"patterns"] ?: @[], g, 0);
    return g;
}

static void tmApply(NSString *text, NSRange range, NSArray<TMRule *> *rules, NSTextStorage *ts, int depth) {
    if (depth > 40 || rules.count == 0) return;
    NSUInteger pos = range.location, end = NSMaxRange(range);
    while (pos < end) {
        TMRule *best = nil; NSTextCheckingResult *bestM = nil; NSUInteger bestStart = end;
        for (TMRule *r in rules) {
            NSTextCheckingResult *m = [r.re firstMatchInString:text options:0 range:NSMakeRange(pos, end-pos)];
            if (m && m.range.location < bestStart) { bestStart = m.range.location; bestM = m; best = r; }
        }
        if (!best) break;
        if (!best.end) {                                        // simple match
            if (best.scope) { NSColor *c = scopeColor(best.scope); if (c) [ts addAttribute:NSForegroundColorAttributeName value:c range:bestM.range]; }
            if (best.caps) for (NSNumber *idx in best.caps) { if (idx.intValue < (int)bestM.numberOfRanges) { NSRange cr = [bestM rangeAtIndex:idx.intValue]; NSColor *c = scopeColor(best.caps[idx]); if (c && cr.location != NSNotFound) [ts addAttribute:NSForegroundColorAttributeName value:c range:cr]; } }
            pos = NSMaxRange(bestM.range); if (NSMaxRange(bestM.range) <= bestStart) pos = bestStart + 1;
        } else {                                                // begin/end region
            NSColor *bc = scopeColor(best.scope); if (bc) [ts addAttribute:NSForegroundColorAttributeName value:bc range:bestM.range];
            NSUInteger cStart = NSMaxRange(bestM.range);
            NSTextCheckingResult *em = [best.end firstMatchInString:text options:0 range:NSMakeRange(cStart, end-cStart)];
            NSUInteger cEnd = em ? em.range.location : end;
            NSRange content = NSMakeRange(cStart, cEnd > cStart ? cEnd - cStart : 0);
            if (best.contentScope) { NSColor *cc = scopeColor(best.contentScope); if (cc) [ts addAttribute:NSForegroundColorAttributeName value:cc range:content]; }
            else if (bc) [ts addAttribute:NSForegroundColorAttributeName value:bc range:content];
            if (best.subs.count) tmApply(text, content, best.subs, ts, depth+1);
            if (em) { NSColor *ec = scopeColor(best.scope); if (ec) [ts addAttribute:NSForegroundColorAttributeName value:ec range:em.range]; pos = NSMaxRange(em.range); }
            else pos = end;
            if (pos <= bestStart) pos = bestStart + 1;
        }
    }
}

static NSMutableDictionary<NSString *, TMGrammar *> *gExtGrammar;   // file-ext -> grammar
static TMGrammar *gActiveGrammar;
static void loadExtensions(void);

static BOOL isIdentChar(unichar c) { return (c=='_') || (c>='a'&&c<='z') || (c>='A'&&c<='Z') || (c>='0'&&c<='9'); }
static BOOL isIdentStart(unichar c) { return (c=='_') || (c>='a'&&c<='z') || (c>='A'&&c<='Z'); }

// Highlight `text` storage in place — single linear scan (comments, strings,
// numbers, keyword/builtin identifiers). No regex.
static void highlight(NSTextStorage *ts) {
    NSString *s = ts.string;
    NSUInteger n = s.length;
    [ts beginEditing];
    [ts addAttribute:NSForegroundColorAttributeName value:gFg range:NSMakeRange(0, n)];
    [ts addAttribute:NSFontAttributeName value:gFont range:NSMakeRange(0, n)];
    if (gActiveGrammar) { tmApply(ts.string, NSMakeRange(0, n), gActiveGrammar.rules, ts, 0); [ts endEditing]; return; }
    NSUInteger i = 0;
    while (i < n) {
        unichar c = [s characterAtIndex:i];
        if (c == '/' && i+1 < n && [s characterAtIndex:i+1] == '/') {            // line comment
            NSUInteger j = i; while (j < n && [s characterAtIndex:j] != '\n') j++;
            [ts addAttribute:NSForegroundColorAttributeName value:gCm range:NSMakeRange(i, j-i)];
            i = j; continue;
        }
        if (c == '"' || c == '\'' || c == '`') {                                // string
            unichar q = c; NSUInteger j = i+1;
            while (j < n) { unichar d = [s characterAtIndex:j];
                if (d == '\\' && j+1 < n) { j += 2; continue; }
                j++; if (d == q) break; }
            [ts addAttribute:NSForegroundColorAttributeName value:gStr range:NSMakeRange(i, MIN(j,n)-i)];
            i = j; continue;
        }
        if (c >= '0' && c <= '9') {                                             // number
            NSUInteger j = i; while (j < n) { unichar d=[s characterAtIndex:j]; if ((d>='0'&&d<='9')||d=='.'||d=='x'||(d>='a'&&d<='f')||(d>='A'&&d<='F')) j++; else break; }
            [ts addAttribute:NSForegroundColorAttributeName value:gNum range:NSMakeRange(i, j-i)];
            i = j; continue;
        }
        if (isIdentStart(c)) {                                                  // identifier
            NSUInteger j = i+1; while (j < n && isIdentChar([s characterAtIndex:j])) j++;
            NSString *word = [s substringWithRange:NSMakeRange(i, j-i)];
            if ([gKwSet containsObject:word]) [ts addAttribute:NSForegroundColorAttributeName value:gKw range:NSMakeRange(i, j-i)];
            else if ([gBuiltinSet containsObject:word]) [ts addAttribute:NSForegroundColorAttributeName value:gBuiltin range:NSMakeRange(i, j-i)];
            i = j; continue;
        }
        i++;
    }
    [ts endEditing];
}

// ── Line-number ruler ──────────────────────────────────────────────────────
@interface LineRuler : NSRulerView
@property (weak) NSTextView *tv;
@end
@implementation LineRuler
- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    NSTextView *tv = self.tv; if (!tv) return;
    NSLayoutManager *lm = tv.layoutManager; NSTextContainer *tc = tv.textContainer;
    NSString *s = tv.string; NSUInteger n = s.length;
    CGFloat yinset = tv.textContainerInset.height;
    NSDictionary *attr = @{ NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular],
                            NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:0.45 alpha:1] };
    NSRange vis = [lm glyphRangeForBoundingRect:[tv visibleRect] inTextContainer:tc];
    NSUInteger line = 1, idx = 0;
    // count lines before the visible range start
    NSUInteger ci = [lm characterIndexForGlyphAtIndex:vis.location];
    for (NSUInteger k = 0; k < ci && k < n; k++) if ([s characterAtIndex:k] == '\n') line++;
    idx = ci;
    while (idx <= n) {
        NSRange lr = [s lineRangeForRange:NSMakeRange(idx, 0)];
        NSRange gr = [lm glyphRangeForCharacterRange:NSMakeRange(lr.location, 0) actualCharacterRange:NULL];
        NSRect lrect = [lm lineFragmentRectForGlyphAtIndex:gr.location effectiveRange:NULL];
        CGFloat y = lrect.origin.y + yinset - NSMinY([tv visibleRect]);
        if (y > NSMaxY(rect)) break;
        NSString *ls = [NSString stringWithFormat:@"%lu", (unsigned long)line];
        NSSize sz = [ls sizeWithAttributes:attr];
        [ls drawAtPoint:NSMakePoint(self.ruleThickness - sz.width - 6, y + 1) withAttributes:attr];
        line++;
        if (NSMaxRange(lr) <= idx) break;
        idx = NSMaxRange(lr);
        if (idx > n) break;
    }
}
@end

// ── Editor controller ──────────────────────────────────────────────────────
// ── file-tree model (lazy) ──────────────────────────────────────────────────
@interface FileNode : NSObject
@property (strong) NSString *path;
@property (strong) NSString *name;
@property (assign) BOOL isDir;
@property (strong) NSMutableArray<FileNode *> *kids;
@property (assign) BOOL loaded;
@end
@implementation FileNode
+ (FileNode *)nodeWithPath:(NSString *)p {
    FileNode *n = [FileNode new]; n.path = p; n.name = p.lastPathComponent;
    BOOL d = NO; [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d]; n.isDir = d;
    return n;
}
- (NSMutableArray<FileNode *> *)children {
    if (self.loaded) return self.kids;
    self.loaded = YES; self.kids = [NSMutableArray array];
    if (!self.isDir) return self.kids;
    NSArray *items = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:nil]
        sortedArrayUsingComparator:^(NSString *a, NSString *b){ return [a caseInsensitiveCompare:b]; }];
    NSMutableArray *dirs = [NSMutableArray array], *files = [NSMutableArray array];
    for (NSString *it in items) {
        if ([it isEqualToString:@".DS_Store"] || [it isEqualToString:@".git"]) continue;
        FileNode *c = [FileNode nodeWithPath:[self.path stringByAppendingPathComponent:it]];
        if (c.isDir) [dirs addObject:c]; else [files addObject:c];
    }
    [self.kids addObjectsFromArray:dirs]; [self.kids addObjectsFromArray:files];
    return self.kids;
}
@end

// ── editor view: current-line highlight, auto-pairs, auto-indent ────────────
@interface KEditView : NSTextView
@end
@implementation KEditView
- (void)drawViewBackgroundInRect:(NSRect)rect {
    [super drawViewBackgroundInRect:rect];
    if (self.selectedRange.length > 0) return;
    NSUInteger loc = MIN(self.selectedRange.location, self.string.length);
    NSRange lr = [self.string lineRangeForRange:NSMakeRange(loc, 0)];
    NSRange gr = [self.layoutManager glyphRangeForCharacterRange:lr actualCharacterRange:NULL];
    NSRect r = [self.layoutManager boundingRectForGlyphRange:gr inTextContainer:self.textContainer];
    CGFloat y = r.origin.y + self.textContainerInset.height;
    [[NSColor colorWithCalibratedWhite:1 alpha:0.045] set];
    NSRectFillUsingOperation(NSMakeRect(0, y, self.bounds.size.width, r.size.height), NSCompositingOperationSourceOver);
}
- (void)insertText:(id)str replacementRange:(NSRange)rr {
    NSString *s = [str isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)str string] : str;
    NSString *full = self.string; NSUInteger loc = self.selectedRange.location;
    // skip over an auto-inserted closer
    if (s.length == 1 && [@")]}\"'`" containsString:s] && loc < full.length
        && [[full substringWithRange:NSMakeRange(loc,1)] isEqualToString:s]) {
        self.selectedRange = NSMakeRange(loc+1, 0); return;
    }
    NSDictionary *pairs = @{@"(":@")", @"[":@"]", @"{":@"}", @"\"":@"\"", @"'":@"'", @"`":@"`"};
    NSString *close = pairs[s];
    [super insertText:s replacementRange:rr];
    if (close && self.selectedRange.length == 0) {
        NSUInteger l2 = self.selectedRange.location;
        [super insertText:close replacementRange:NSMakeRange(l2,0)];
        self.selectedRange = NSMakeRange(l2, 0);
    }
}
- (void)insertNewline:(id)sender {
    NSString *full = self.string; NSUInteger loc = self.selectedRange.location;
    NSRange cur = [full lineRangeForRange:NSMakeRange(loc, 0)];
    NSString *pre = [full substringWithRange:NSMakeRange(cur.location, loc - cur.location)];
    NSUInteger i = 0; while (i < pre.length && ([pre characterAtIndex:i]==' ' || [pre characterAtIndex:i]=='\t')) i++;
    NSString *indent = [pre substringToIndex:i];
    NSString *trimmed = [pre stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL openBrace = [trimmed hasSuffix:@"{"] || [trimmed hasSuffix:@"("] || [trimmed hasSuffix:@"["];
    BOOL closerNext = loc < full.length && [@")]}" containsString:[full substringWithRange:NSMakeRange(loc,1)]];
    [super insertNewline:sender];
    [super insertText:[indent stringByAppendingString:(openBrace ? @"    " : @"")] replacementRange:self.selectedRange];
    if (openBrace && closerNext) {                              // {<newline-indent><cursor>\n<indent>}
        NSUInteger c = self.selectedRange.location;
        [super insertText:[@"\n" stringByAppendingString:indent] replacementRange:NSMakeRange(c,0)];
        self.selectedRange = NSMakeRange(c, 0);
    }
}
@end

@interface Editor : NSObject <NSTextStorageDelegate, NSWindowDelegate, NSToolbarDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSControlTextEditingDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSWindow *win;
@property (strong) NSTextView *tv;
@property (strong) NSString *path;     // nil = untitled
@property (strong) NSTextField *status;
@property (strong) FileNode *root;
@property (strong) NSOutlineView *outline;
@property (strong) NSPanel *qpPanel;
@property (strong) NSTableView *qpTable;
@property (strong) NSSearchField *qpField;
@property (strong) NSArray<NSString *> *qpAll;       // all project file paths
@property (strong) NSArray<NSString *> *qpHits;      // filtered
@property (strong) NSTextField *sbHeader;
@end

@implementation Editor

- (void)applyTitle {
    NSString *name = self.path ? self.path.lastPathComponent : @"Untitled";
    self.win.title = name;
    self.win.representedFilename = self.path ?: @"";
    self.win.documentEdited = self.tv.string.length > 0 && [self isDirty];
}
- (BOOL)isDirty { return self.win.documentEdited; }

- (void)loadPath:(NSString *)p {
    NSString *txt = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
    if (!txt) txt = @"";
    [self.tv setString:txt];
    gActiveGrammar = gExtGrammar[p.pathExtension.lowercaseString];   // grammar from a VS Code extension
    highlight(self.tv.textStorage);
    self.path = p;
    self.win.documentEdited = NO;
    [self applyTitle];
    [self updateStatus];
    if (!self.root && self.outline) [self setFolder:[p stringByDeletingLastPathComponent]];
    [self.win.contentView setNeedsDisplay:YES];
}

// --- menu actions ---
- (void)newDoc:(id)s    { [self.tv setString:@""]; self.path = nil; self.win.documentEdited = NO; [self applyTitle]; }
- (void)openDoc:(id)s {
    NSOpenPanel *o = [NSOpenPanel openPanel]; o.allowedFileTypes = nil; o.allowsMultipleSelection = NO;
    if ([o runModal] == NSModalResponseOK && o.URLs.count) [self loadPath:o.URLs[0].path];
}
- (BOOL)writeTo:(NSString *)p {
    NSError *e = nil;
    BOOL ok = [self.tv.string writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:&e];
    if (ok) { self.path = p; self.win.documentEdited = NO; [self applyTitle]; }
    return ok;
}
- (void)saveDoc:(id)s {
    if (self.path) [self writeTo:self.path];
    else [self saveAs:s];
}
- (void)saveAs:(id)s {
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.nameFieldStringValue = self.path ? self.path.lastPathComponent : @"untitled.k";
    if ([sp runModal] == NSModalResponseOK) [self writeTo:sp.URL.path];
}
- (void)closeDoc:(id)s { [self.win performClose:nil]; }

// Build with kcc — saves first, runs `kcc --native <file>`, shows output.
- (void)build:(id)s {
    if (!self.path) { [self saveAs:s]; if (!self.path) return; }
    else [self writeTo:self.path];
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    NSString *out = [self.path.lastPathComponent.stringByDeletingPathExtension stringByAppendingString:@""];
    t.arguments = @[@"-lc", [NSString stringWithFormat:@"kcc --native %@ -o /tmp/%@ 2>&1", _shq(self.path), _shq(out)]];
    NSPipe *pipe = [NSPipe pipe]; t.standardOutput = pipe; t.standardError = pipe;
    NSError *e = nil; if (![t launchAndReturnError:&e]) { [self showOutput:[NSString stringWithFormat:@"launch failed: %@", e]]; return; }
    [t waitUntilExit];
    NSData *d = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *log = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
    [self showOutput:[NSString stringWithFormat:@"$ kcc --native %@\n%@%@", self.path.lastPathComponent,
        log.length ? log : @"", t.terminationStatus == 0 ? @"\n✓ build ok" : [NSString stringWithFormat:@"\n✗ exit %d", t.terminationStatus]]];
}
- (void)run:(id)s {
    [self build:s];
    if (!self.path) return;
    NSString *base = self.path.lastPathComponent.stringByDeletingPathExtension;
    NSString *bin = [@"/tmp/" stringByAppendingString:base];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:bin]) return;  // build failed
    // run it in Terminal so interactive programs work
    NSString *cmd = [NSString stringWithFormat:@"tell application \"Terminal\" to do script \"%@\"\ntell application \"Terminal\" to activate",
                     [bin stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:cmd];
    [as executeAndReturnError:nil];
}
- (void)showOutput:(NSString *)txt {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Build";
    a.informativeText = txt.length > 1500 ? [txt substringToIndex:1500] : txt;
    [a addButtonWithTitle:@"OK"];
    [a beginSheetModalForWindow:self.win completionHandler:nil];
}

// status bar: Ln/Col + file type
- (void)updateStatus {
    NSString *s = self.tv.string; NSUInteger ip = self.tv.selectedRange.location;
    NSUInteger line = 1, col = 1;
    for (NSUInteger k = 0; k < ip && k < s.length; k++) { if ([s characterAtIndex:k] == '\n') { line++; col = 1; } else col++; }
    NSString *ext = self.path ? self.path.pathExtension.uppercaseString : @"";
    NSString *lang = ext.length ? ext : @"TEXT";
    self.status.stringValue = [NSString stringWithFormat:@"  Ln %lu, Col %lu      %@      %lu chars",
                               (unsigned long)line, (unsigned long)col, lang, (unsigned long)s.length];
}

// --- file-tree sidebar ---
- (void)openFolder:(id)s {
    NSOpenPanel *o = [NSOpenPanel openPanel]; o.canChooseDirectories = YES; o.canChooseFiles = NO; o.allowsMultipleSelection = NO;
    if ([o runModal] == NSModalResponseOK && o.URLs.count) [self setFolder:o.URLs[0].path];
}
- (void)setFolder:(NSString *)dir {
    self.root = [FileNode nodeWithPath:dir];
    [self.outline reloadData];
    self.sbHeader.stringValue = [@"  " stringByAppendingString:dir.lastPathComponent.uppercaseString];
}
- (void)installExtension:(id)s {
    NSOpenPanel *o = [NSOpenPanel openPanel]; o.allowedFileTypes = @[@"vsix"]; o.canChooseDirectories = NO;
    if ([o runModal] != NSModalResponseOK || !o.URLs.count) return;
    NSString *vsix = o.URLs[0].path;
    NSString *name = vsix.lastPathComponent.stringByDeletingPathExtension;
    NSString *dest = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/kcode/extensions"] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/unzip"];
    t.arguments = @[@"-o", @"-q", vsix, @"-d", dest];
    [t launchAndReturnError:nil]; [t waitUntilExit];
    loadExtensions();
    if (self.path) { gActiveGrammar = gExtGrammar[self.path.pathExtension.lowercaseString]; highlight(self.tv.textStorage); }
    NSAlert *a = [[NSAlert alloc] init]; a.messageText = [NSString stringWithFormat:@"Installed extension: %@", name];
    a.informativeText = [NSString stringWithFormat:@"%lu file types now grammar-highlighted.", (unsigned long)gExtGrammar.count];
    [a addButtonWithTitle:@"OK"]; [a beginSheetModalForWindow:self.win completionHandler:nil];
}
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    FileNode *n = item ?: self.root; return n ? n.children.count : 0;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(id)item {
    FileNode *n = item ?: self.root; return n.children[i];
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item { return ((FileNode *)item).isDir; }
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)c item:(id)item {
    FileNode *n = item;
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,200,20)]; cell.identifier = @"cell";
        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(2,2,16,16)];
        NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(22,1,172,18)];
        tf.bezeled = NO; tf.editable = NO; tf.drawsBackground = NO; tf.font = [NSFont systemFontOfSize:12];
        tf.textColor = [NSColor colorWithCalibratedWhite:0.86 alpha:1];
        [cell addSubview:iv]; [cell addSubview:tf]; cell.imageView = iv; cell.textField = tf;
    }
    cell.textField.stringValue = n.name;
    NSImage *ic = [[NSWorkspace sharedWorkspace] iconForFile:n.path]; ic.size = NSMakeSize(16,16);
    cell.imageView.image = ic;
    return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)note {
    NSInteger r = self.outline.selectedRow; if (r < 0) return;
    FileNode *n = [self.outline itemAtRow:r];
    if (n && !n.isDir) [self loadPath:n.path];
}

// --- Go to Line (⌘L) ---
- (void)goToLine:(id)s {
    NSAlert *a = [[NSAlert alloc] init]; a.messageText = @"Go to Line";
    NSTextField *inp = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,220,24)];
    a.accessoryView = inp; [a addButtonWithTitle:@"Go"]; [a addButtonWithTitle:@"Cancel"];
    [a.window setInitialFirstResponder:inp];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    int ln = inp.intValue; if (ln < 1) return;
    NSString *full = self.tv.string; NSUInteger pos = 0; int cur = 1;
    while (cur < ln && pos < full.length) { if ([full characterAtIndex:pos] == '\n') cur++; pos++; }
    NSRange lr = [full lineRangeForRange:NSMakeRange(MIN(pos, full.length), 0)];
    self.tv.selectedRange = NSMakeRange(lr.location, 0);
    [self.tv scrollRangeToVisible:NSMakeRange(lr.location, 0)];
    [self.win makeFirstResponder:self.tv];
}

// --- Quick Open (⌘P) ---
- (NSArray *)gatherFiles:(NSString *)dir {
    NSMutableArray *out = [NSMutableArray array];
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    NSString *rel;
    while ((rel = [en nextObject])) {
        if ([rel.lastPathComponent hasPrefix:@"."] || [rel hasPrefix:@"dist/"] || [rel containsString:@"node_modules"] || [rel containsString:@".git/"]) {
            if ([[en fileAttributes][NSFileType] isEqual:NSFileTypeDirectory]) [en skipDescendants];
            continue;
        }
        if (![[en fileAttributes][NSFileType] isEqual:NSFileTypeDirectory]) [out addObject:rel];
        if (out.count > 6000) break;
    }
    return out;
}
static BOOL fuzzy(NSString *hay, NSString *needle) {
    NSUInteger hi = 0, ni = 0, hn = hay.length, nn = needle.length;
    while (hi < hn && ni < nn) { if ([hay characterAtIndex:hi] == [needle characterAtIndex:ni]) ni++; hi++; }
    return ni == nn;
}
- (void)qpFilter:(NSString *)q {
    if (q.length == 0) self.qpHits = [self.qpAll subarrayWithRange:NSMakeRange(0, MIN(self.qpAll.count, 300))];
    else { NSString *lq = q.lowercaseString; NSMutableArray *m = [NSMutableArray array];
        for (NSString *p in self.qpAll) if (fuzzy(p.lowercaseString, lq)) [m addObject:p];
        self.qpHits = m; }
    [self.qpTable reloadData];
    if (self.qpHits.count) [self.qpTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}
- (void)buildQuickOpen {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,540,360)
        styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView) backing:NSBackingStoreBuffered defer:NO];
    p.titlebarAppearsTransparent = YES; p.titleVisibility = NSWindowTitleHidden; p.movableByWindowBackground = YES;
    NSSearchField *sf = [[NSSearchField alloc] initWithFrame:NSMakeRect(10,322,520,28)];
    sf.placeholderString = @"Go to file…  (fuzzy)"; sf.delegate = self;
    sf.autoresizingMask = (NSViewWidthSizable|NSViewMinYMargin);
    [p.contentView addSubview:sf];
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,540,318)];
    sv.hasVerticalScroller = YES; sv.autoresizingMask = (NSViewWidthSizable|NSViewHeightSizable);
    NSTableView *t = [[NSTableView alloc] initWithFrame:sv.bounds];
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"f"]; c.width = 520; [t addTableColumn:c];
    t.headerView = nil; t.dataSource = self; t.delegate = self; t.rowHeight = 22;
    t.target = self; t.doubleAction = @selector(qpOpenSelected);
    sv.documentView = t; [p.contentView addSubview:sv];
    self.qpPanel = p; self.qpField = sf; self.qpTable = t;
}
- (void)quickOpen:(id)s {
    if (!self.root) { [self openFolder:s]; if (!self.root) return; }
    self.qpAll = [self gatherFiles:self.root.path];
    if (!self.qpPanel) [self buildQuickOpen];
    self.qpField.stringValue = @""; [self qpFilter:@""];
    [self.win beginSheet:self.qpPanel completionHandler:nil];
    [self.qpPanel makeFirstResponder:self.qpField];
}
- (void)qpOpenSelected {
    NSInteger r = self.qpTable.selectedRow;
    [self.win endSheet:self.qpPanel];
    if (r >= 0 && r < (NSInteger)self.qpHits.count) [self loadPath:[self.root.path stringByAppendingPathComponent:self.qpHits[r]]];
}
- (void)controlTextDidChange:(NSNotification *)n { if (n.object == self.qpField) [self qpFilter:self.qpField.stringValue]; }
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    if (c != self.qpField) return NO;
    NSInteger r = self.qpTable.selectedRow, n = self.qpHits.count;
    if (sel == @selector(insertNewline:)) { [self qpOpenSelected]; return YES; }
    if (sel == @selector(cancelOperation:)) { [self.win endSheet:self.qpPanel]; return YES; }
    if (sel == @selector(moveDown:)) { if (r+1 < n) [self.qpTable selectRowIndexes:[NSIndexSet indexSetWithIndex:r+1] byExtendingSelection:NO]; [self.qpTable scrollRowToVisible:self.qpTable.selectedRow]; return YES; }
    if (sel == @selector(moveUp:))   { if (r > 0) [self.qpTable selectRowIndexes:[NSIndexSet indexSetWithIndex:r-1] byExtendingSelection:NO]; [self.qpTable scrollRowToVisible:self.qpTable.selectedRow]; return YES; }
    return NO;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return self.qpHits.count; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
    NSTableCellView *cell = [t makeViewWithIdentifier:@"qp" owner:self];
    if (!cell) { cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,520,22)]; cell.identifier = @"qp";
        NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(8,2,500,18)];
        tf.bezeled=NO; tf.editable=NO; tf.drawsBackground=NO; tf.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        [cell addSubview:tf]; cell.textField = tf; }
    cell.textField.stringValue = self.qpHits[row];
    return cell;
}

// --- toolbar ---
- (NSToolbarItem *)toolbar:(NSToolbar *)tb itemForItemIdentifier:(NSToolbarItemIdentifier)id willBeInsertedIntoToolbar:(BOOL)f {
    NSToolbarItem *it = [[NSToolbarItem alloc] initWithItemIdentifier:id];
    it.target = self;
    NSDictionary *map = @{ @"open":@[@"Open",@"folder",@"openDoc:"], @"save":@[@"Save",@"square.and.arrow.down",@"saveDoc:"],
                           @"build":@[@"Build",@"hammer",@"build:"], @"run":@[@"Run",@"play.fill",@"run:"] };
    NSArray *m = map[id]; if (!m) return it;
    it.label = m[0]; it.paletteLabel = m[0];
    it.image = [NSImage imageWithSystemSymbolName:m[1] accessibilityDescription:m[0]];
    it.action = NSSelectorFromString(m[2]);
    it.toolTip = m[0];
    return it;
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)tb {
    return @[@"open", @"save", NSToolbarFlexibleSpaceItemIdentifier, @"build", @"run"];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)tb {
    return @[@"open", @"save", @"build", @"run", NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier];
}

// --- syntax re-highlight on edit ---
- (void)textStorage:(NSTextStorage *)ts didProcessEditing:(NSTextStorageEditActions)e range:(NSRange)r changeInLength:(NSInteger)dl {
    if (!(e & NSTextStorageEditedCharacters)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ highlight(ts); self.win.documentEdited = YES; });
}
- (BOOL)windowShouldClose:(NSWindow *)w {
    if (!self.win.documentEdited) return YES;
    NSAlert *a = [[NSAlert alloc] init]; a.messageText = @"Save changes?";
    [a addButtonWithTitle:@"Save"]; [a addButtonWithTitle:@"Discard"]; [a addButtonWithTitle:@"Cancel"];
    NSModalResponse r = [a runModal];
    if (r == NSAlertFirstButtonReturn) { [self saveDoc:nil]; return !self.win.documentEdited; }
    if (r == NSAlertSecondButtonReturn) return YES;
    return NO;
}
- (void)windowWillClose:(NSNotification *)n { [NSApp terminate:nil]; }
@end

static NSString *_shq(NSString *s) { return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }

static Editor *gEd;

static NSMenuItem *mi(NSMenu *m, NSString *t, SEL a, NSString *k, id target) {
    NSMenuItem *it = [m addItemWithTitle:t action:a keyEquivalent:k]; it.target = target; return it;
}

static void buildMenu(void) {
    NSMenu *main = [[NSMenu alloc] init];
    NSMenuItem *appI = [[NSMenuItem alloc] init]; [main addItem:appI];
    NSMenu *app = [[NSMenu alloc] init];
    [app addItemWithTitle:@"About kcode" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Quit kcode" action:@selector(terminate:) keyEquivalent:@"q"];
    appI.submenu = app;
    // File
    NSMenuItem *fI = [[NSMenuItem alloc] init]; [main addItem:fI];
    NSMenu *f = [[NSMenu alloc] initWithTitle:@"File"];
    mi(f, @"New", @selector(newDoc:), @"n", gEd);
    mi(f, @"Open…", @selector(openDoc:), @"o", gEd);
    mi(f, @"Open Folder…", @selector(openFolder:), @"O", gEd).keyEquivalentModifierMask = (NSEventModifierFlagCommand|NSEventModifierFlagShift);
    [f addItem:[NSMenuItem separatorItem]];
    mi(f, @"Install Extension…", @selector(installExtension:), @"", gEd);
    [f addItem:[NSMenuItem separatorItem]];
    mi(f, @"Save", @selector(saveDoc:), @"s", gEd);
    mi(f, @"Save As…", @selector(saveAs:), @"S", gEd).keyEquivalentModifierMask = (NSEventModifierFlagCommand|NSEventModifierFlagShift);
    [f addItem:[NSMenuItem separatorItem]];
    mi(f, @"Build", @selector(build:), @"b", gEd);
    [f addItem:[NSMenuItem separatorItem]];
    mi(f, @"Close", @selector(closeDoc:), @"w", gEd);
    fI.submenu = f;
    // Edit (native NSTextView responders)
    NSMenuItem *eI = [[NSMenuItem alloc] init]; [main addItem:eI];
    NSMenu *e = [[NSMenu alloc] initWithTitle:@"Edit"];
    [e addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [[e addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"] setKeyEquivalentModifierMask:(NSEventModifierFlagCommand|NSEventModifierFlagShift)];
    [e addItem:[NSMenuItem separatorItem]];
    [e addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [e addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [e addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [e addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [e addItem:[NSMenuItem separatorItem]];
    [e addItemWithTitle:@"Find…" action:@selector(performFindPanelAction:) keyEquivalent:@"f"];
    eI.submenu = e;
    // Navigate
    NSMenuItem *nI = [[NSMenuItem alloc] init]; [main addItem:nI];
    NSMenu *nav = [[NSMenu alloc] initWithTitle:@"Navigate"];
    mi(nav, @"Quick Open…", @selector(quickOpen:), @"p", gEd);
    mi(nav, @"Go to Line…", @selector(goToLine:), @"l", gEd);
    nI.submenu = nav;
    // Window + Help
    NSMenuItem *wI = [[NSMenuItem alloc] init]; [main addItem:wI];
    NSMenu *w = [[NSMenu alloc] initWithTitle:@"Window"];
    [w addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [w addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    wI.submenu = w;
    NSMenuItem *hI = [[NSMenuItem alloc] init]; [main addItem:hI];
    NSMenu *h = [[NSMenu alloc] initWithTitle:@"Help"];
    [h addItemWithTitle:@"kcode Help" action:NULL keyEquivalent:@""];
    hI.submenu = h;
    [NSApp setMainMenu:main];
    [NSApp setWindowsMenu:w];
    [NSApp setHelpMenu:h];
}

// Scan bundled + user extension dirs for VS Code extensions; load their grammars.
static void loadExtensions(void) {
    gExtGrammar = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *be = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"extensions"]; if (be) [dirs addObject:be];
    [dirs addObject:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/kcode/extensions"]];
    for (NSString *dir in dirs) {
        for (NSString *sub in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            NSString *extDir = [dir stringByAppendingPathComponent:sub];
            NSString *pkgPath = [extDir stringByAppendingPathComponent:@"package.json"];
            if (![fm fileExistsAtPath:pkgPath]) { extDir = [extDir stringByAppendingPathComponent:@"extension"]; pkgPath = [extDir stringByAppendingPathComponent:@"package.json"]; }  // VSIX layout
            NSData *pd = [NSData dataWithContentsOfFile:pkgPath]; if (!pd) continue;
            NSDictionary *pkg = [NSJSONSerialization JSONObjectWithData:pd options:0 error:nil];
            NSDictionary *contrib = pkg[@"contributes"]; if (![contrib isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *langExts = [NSMutableDictionary dictionary];
            for (NSDictionary *l in contrib[@"languages"]) if (l[@"id"] && l[@"extensions"]) langExts[l[@"id"]] = l[@"extensions"];
            for (NSDictionary *gr in contrib[@"grammars"]) {
                if (!gr[@"path"]) continue;
                TMGrammar *g = tmLoad([extDir stringByAppendingPathComponent:gr[@"path"]]); if (!g) continue;
                for (NSString *e in langExts[gr[@"language"]]) gExtGrammar[([e hasPrefix:@"."]?[e substringFromIndex:1]:e).lowercaseString] = g;
            }
        }
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        initSyntax();
        gFont = [NSFont fontWithName:@"JetBrainsMono Nerd Font Mono" size:13]
             ?: [NSFont userFixedPitchFontOfSize:13];
        gBg = [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.14 alpha:1];
        gFg = [NSColor colorWithCalibratedRed:0.85 green:0.86 blue:0.84 alpha:1];
        gKw = [NSColor colorWithCalibratedRed:0.78 green:0.47 blue:0.87 alpha:1];
        gBuiltin = [NSColor colorWithCalibratedRed:0.36 green:0.71 blue:0.93 alpha:1];
        gStr = [NSColor colorWithCalibratedRed:0.60 green:0.80 blue:0.42 alpha:1];
        gCm = [NSColor colorWithCalibratedRed:0.45 green:0.47 blue:0.50 alpha:1];
        gNum = [NSColor colorWithCalibratedRed:0.90 green:0.62 blue:0.36 alpha:1];
        gType = [NSColor colorWithCalibratedRed:0.40 green:0.78 blue:0.74 alpha:1];
        loadExtensions();   // grammars from installed VS Code extensions

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        gEd = [[Editor alloc] init];
        buildMenu();

        NSRect frame = NSMakeRect(0, 0, 820, 560);
        NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
            styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable)
            backing:NSBackingStoreBuffered defer:NO];
        win.delegate = gEd;
        win.titlebarAppearsTransparent = NO;
        win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
        scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = NO;
        scroll.autoresizingMask = (NSViewWidthSizable|NSViewHeightSizable);
        scroll.borderType = NSNoBorder;

        KEditView *tv = [[KEditView alloc] initWithFrame:frame];
        tv.usesFindBar = YES; tv.incrementalSearchingEnabled = YES;   // ⌘F find + replace bar
        tv.minSize = NSMakeSize(0, 0); tv.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
        tv.verticallyResizable = YES; tv.horizontallyResizable = NO;
        tv.autoresizingMask = NSViewWidthSizable;
        tv.textContainer.widthTracksTextView = YES;
        tv.textContainerInset = NSMakeSize(6, 6);
        tv.font = gFont;
        tv.backgroundColor = gBg;
        tv.textColor = gFg;
        tv.insertionPointColor = [NSColor colorWithCalibratedRed:0.85 green:0.86 blue:0.84 alpha:1];
        tv.automaticQuoteSubstitutionEnabled = NO;
        tv.automaticDashSubstitutionEnabled = NO;
        tv.automaticTextReplacementEnabled = NO;
        tv.automaticSpellingCorrectionEnabled = NO;
        tv.richText = NO; tv.allowsUndo = YES;
        tv.textStorage.delegate = gEd;
        scroll.documentView = tv;

        // line-number ruler
        scroll.hasVerticalRuler = YES; scroll.rulersVisible = YES;
        LineRuler *ruler = [[LineRuler alloc] initWithScrollView:scroll orientation:NSVerticalRuler];
        ruler.tv = tv; ruler.ruleThickness = 44;
        scroll.verticalRulerView = ruler;
        [[NSNotificationCenter defaultCenter] addObserverForName:NSTextViewDidChangeSelectionNotification object:tv queue:nil usingBlock:^(NSNotification *_n){ [ruler setNeedsDisplay:YES]; [gEd updateStatus]; }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSViewBoundsDidChangeNotification object:scroll.contentView queue:nil usingBlock:^(NSNotification *_n){ [ruler setNeedsDisplay:YES]; }];
        scroll.contentView.postsBoundsChangedNotifications = YES;

        // file-tree sidebar (NSOutlineView)
        NSColor *sideBg = [NSColor colorWithCalibratedRed:0.145 green:0.145 blue:0.165 alpha:1];
        NSScrollView *sideScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,210,frame.size.height-22)];
        sideScroll.hasVerticalScroller = YES; sideScroll.drawsBackground = YES; sideScroll.backgroundColor = sideBg;
        sideScroll.borderType = NSNoBorder;
        NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:sideScroll.bounds];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"]; col.width = 196;
        [outline addTableColumn:col]; outline.outlineTableColumn = col;
        outline.headerView = nil; outline.dataSource = gEd; outline.delegate = gEd;
        outline.backgroundColor = sideBg; outline.indentationPerLevel = 13;
        outline.rowSizeStyle = NSTableViewRowSizeStyleMedium;
        outline.focusRingType = NSFocusRingTypeNone;
        sideScroll.documentView = outline;
        gEd.outline = outline;

        // sidebar = header ("EXPLORER" / project name) + tree
        NSView *leftPane = [[NSView alloc] initWithFrame:NSMakeRect(0,0,210,frame.size.height-22)];
        leftPane.autoresizesSubviews = YES;
        NSTextField *sbHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(0, leftPane.bounds.size.height-26, 210, 26)];
        sbHeader.editable=NO; sbHeader.bezeled=NO; sbHeader.selectable=NO; sbHeader.drawsBackground=YES;
        sbHeader.backgroundColor = sideBg; sbHeader.textColor=[NSColor colorWithCalibratedWhite:0.66 alpha:1];
        sbHeader.font=[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        sbHeader.stringValue=@"  EXPLORER"; sbHeader.autoresizingMask=(NSViewWidthSizable|NSViewMinYMargin);
        gEd.sbHeader = sbHeader;
        sideScroll.frame = NSMakeRect(0,0,210,leftPane.bounds.size.height-26);
        sideScroll.autoresizingMask = (NSViewWidthSizable|NSViewHeightSizable);
        [leftPane addSubview:sbHeader]; [leftPane addSubview:sideScroll];

        // split: sidebar | editor
        NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 22, frame.size.width, frame.size.height - 22)];
        split.vertical = YES; split.dividerStyle = NSSplitViewDividerStyleThin;
        split.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        [split addSubview:leftPane]; [split addSubview:scroll];
        [split adjustSubviews]; [split setPosition:210 ofDividerAtIndex:0];

        NSView *container = [[NSView alloc] initWithFrame:frame];
        container.autoresizesSubviews = YES;
        [container addSubview:split];
        NSTextField *status = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, 22)];
        status.editable = NO; status.bezeled = NO; status.selectable = NO;
        status.drawsBackground = YES;
        status.backgroundColor = [NSColor colorWithCalibratedRed:0.16 green:0.16 blue:0.19 alpha:1];
        status.textColor = [NSColor colorWithCalibratedWhite:0.62 alpha:1];
        status.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        status.autoresizingMask = (NSViewWidthSizable | NSViewMaxYMargin);
        status.stringValue = @"  Ln 1, Col 1";
        [container addSubview:status];
        win.contentView = container;
        gEd.win = win; gEd.tv = tv; gEd.status = status;

        // toolbar — makes it read as a Mac app, not a terminal
        NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"kcodeToolbar"];
        tb.delegate = gEd; tb.displayMode = NSToolbarDisplayModeIconOnly; tb.allowsUserCustomization = NO;
        win.toolbar = tb;
        if (@available(macOS 11.0, *)) win.toolbarStyle = NSWindowToolbarStyleUnified;

        // open a file OR folder passed on argv (kcode <path>)
        if (argc > 1) { NSString *p = [NSString stringWithUTF8String:argv[1]];
            if (![p hasPrefix:@"/"]) p = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:p];
            BOOL d = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d]) {
                if (d) [gEd setFolder:p]; else [gEd loadPath:p];
            }
        }
        [gEd applyTitle];
        [gEd updateStatus];

        [win center]; [win makeKeyAndOrderFront:nil]; [win makeFirstResponder:tv];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
