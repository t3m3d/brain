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
@class TMGrammar;
static NSMutableDictionary *gExtGrammar;           // VSIX-provided ext -> grammar
static TMGrammar *gActiveGrammar;
static NSDictionary *gExtLang, *gScopeLang;        // manifest: ext->lang, scopeName->lang
static NSString *gGrammarDir;
static NSMutableDictionary *gLangCache;            // lang -> TMGrammar (or NSNull)
static void loadExtensions(void);
static TMGrammar *loadGrammarForLang(NSString *lang);
static TMGrammar *grammarForScope(NSString *scope);

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
    // cross-grammar include: "source.css", "text.html.basic#tag", etc.
    NSArray *parts = [inc componentsSeparatedByString:@"#"];
    NSString *scope = parts[0];
    if (scope.length) {
        TMGrammar *other = grammarForScope(scope);
        if (other && other != self) {
            if (parts.count > 1) return [other resolve:[@"#" stringByAppendingString:parts[1]] depth:depth+1];
            return other.rules;
        }
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

// Lazily load + compile a bundled grammar by language name (cycle-guarded).
static TMGrammar *loadGrammarForLang(NSString *lang) {
    if (!lang) return nil;
    id c = gLangCache[lang]; if (c) return (c == [NSNull null]) ? nil : c;
    NSData *data = [NSData dataWithContentsOfFile:[gGrammarDir stringByAppendingPathComponent:[lang stringByAppendingString:@".json"]]];
    if (!data) { gLangCache[lang] = [NSNull null]; return nil; }
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![j isKindOfClass:[NSDictionary class]]) { gLangCache[lang] = [NSNull null]; return nil; }
    TMGrammar *g = [TMGrammar new]; g.repo = j[@"repository"] ?: @{}; g.cache = [NSMutableDictionary dictionary];
    gLangCache[lang] = g;                          // cache BEFORE compile (cross-grammar cycle guard)
    g.rules = tmCompile(j[@"patterns"] ?: @[], g, 0);
    return g;
}
static TMGrammar *grammarForScope(NSString *scope) { return loadGrammarForLang(gScopeLang[scope]); }

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

// ── open document + tab bar ─────────────────────────────────────────────────
@class Editor;
@interface KDoc : NSObject
@property (strong) NSTextStorage *storage;
@property (strong) NSString *path;       // nil = untitled
@property (assign) BOOL dirty;
@property (assign) NSRange sel;
@property (strong) NSUndoManager *undo;
@property (strong) TMGrammar *grammar;
- (NSString *)title;
@end
@implementation KDoc
- (NSString *)title { return self.path ? self.path.lastPathComponent : @"untitled"; }
@end

@interface KTabBar : NSView
@property (weak) Editor *ed;
@property (strong) NSMutableArray *hit;   // tab frames (NSValue) parallel to docs
@end

// ── integrated terminal: hosts the kryoterm engine, renders its frames ──────
static NSColor *term256(int n) {
    static const unsigned char base[16][3] = {{30,30,30},{205,49,49},{13,188,121},{229,229,16},{36,114,200},{188,63,188},{17,168,205},{204,204,204},{102,102,102},{241,76,76},{35,209,139},{245,245,67},{59,142,234},{214,112,214},{41,184,219},{255,255,255}};
    if (n < 0) n = 7;
    if (n < 16) return [NSColor colorWithCalibratedRed:base[n][0]/255.0 green:base[n][1]/255.0 blue:base[n][2]/255.0 alpha:1];
    if (n < 232) { int c=n-16,r=c/36,g=(c%36)/6,b=c%6; int s[6]={0,95,135,175,215,255}; return [NSColor colorWithCalibratedRed:s[r]/255.0 green:s[g]/255.0 blue:s[b]/255.0 alpha:1]; }
    int v = 8 + (n-232)*10; return [NSColor colorWithCalibratedRed:v/255.0 green:v/255.0 blue:v/255.0 alpha:1];
}
static NSAttributedString *parseTermSGR(NSData *data, NSFont *font) {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    const unsigned char *b = data.bytes; NSUInteger n = data.length, i = 0, run = 0;
    NSColor *fg = [NSColor colorWithCalibratedWhite:0.82 alpha:1], *cur = fg;
    while (i < n) {
        if (b[i] == 0x1b && i+1 < n && b[i+1] == '[') {
            if (i > run) { NSString *s = [[NSString alloc] initWithBytes:b+run length:i-run encoding:NSUTF8StringEncoding]; if (s) [out appendAttributedString:[[NSAttributedString alloc] initWithString:s attributes:@{NSForegroundColorAttributeName:cur, NSFontAttributeName:font}]]; }
            NSUInteger j = i+2; int code = 0, have = 0, stage = 0, newc = -2;
            while (j < n) { unsigned char p = b[j];
                if (p>='0'&&p<='9'){code=code*10+(p-'0');have=1;}
                else if (p==';'||(p>=0x40&&p<=0x7e)){ if(stage==2){newc=code;stage=0;} else if(stage==1){stage=(code==5)?2:0;} else if(code==38)stage=1; else if(code==0)newc=-1; else if(code>=30&&code<=37)newc=code-30; else if(code>=90&&code<=97)newc=code-90+8; code=0;have=0; if(p>=0x40&&p<=0x7e){ if(p=='m'){ cur=(newc==-1)?fg:(newc>=0?term256(newc):cur);} j++; break;} }
                j++; }
            i = j; run = i;
        } else i++;
    }
    if (i > run) { NSString *s = [[NSString alloc] initWithBytes:b+run length:i-run encoding:NSUTF8StringEncoding]; if (s) [out appendAttributedString:[[NSAttributedString alloc] initWithString:s attributes:@{NSForegroundColorAttributeName:cur, NSFontAttributeName:font}]]; }
    return out;
}

@interface KTermView : NSTextView
@property (assign) int wfd, rfd; @property (assign) pid_t child;
@property (assign) int cols, rows; @property (strong) NSFont *mono;
- (void)spawn:(NSString *)engine;
- (void)sendResize;
@end
@implementation KTermView
- (BOOL)isEditable { return NO; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)spawn:(NSString *)engine {
    int inp[2], outp[2]; if (pipe(inp) || pipe(outp)) return;
    pid_t pid = fork(); if (pid < 0) return;
    if (pid == 0) { dup2(inp[0],0); dup2(outp[1],1); dup2(outp[1],2);
        close(inp[0]);close(inp[1]);close(outp[0]);close(outp[1]);
        setenv("TERM","xterm-256color",1);
        execl(engine.fileSystemRepresentation, engine.fileSystemRepresentation, "-i", (char*)NULL); _exit(127); }
    close(inp[0]); close(outp[1]); _wfd = inp[1]; _rfd = outp[0]; _child = pid;
    [NSThread detachNewThreadSelector:@selector(readLoop) toTarget:self withObject:nil];
}
- (void)readLoop {
    NSMutableData *frame = [NSMutableData data]; unsigned char buf[8192]; ssize_t got; int rfd = _rfd;
    while ((got = read(rfd, buf, sizeof buf)) > 0)
        for (ssize_t i = 0; i < got; i++) { if (buf[i] == 0x0c) { NSData *s = [frame copy]; dispatch_async(dispatch_get_main_queue(), ^{ [self render:s]; }); [frame setLength:0]; } else [frame appendBytes:&buf[i] length:1]; }
}
- (void)render:(NSData *)snap {
    const unsigned char *p = snap.bytes; NSUInteger n = snap.length, body = 0;
    if (n > 0 && p[0] == 1) { NSUInteger k = 1; while (k < n && p[k] != 1) k++; if (k < n) body = k+1; }
    NSData *bd = [snap subdataWithRange:NSMakeRange(body, n-body)];
    [self.textStorage setAttributedString:parseTermSGR(bd, self.mono)];
}
- (void)keyDown:(NSEvent *)e {
    if (_wfd < 0) return; const char *seq = NULL;
    switch (e.keyCode) { case 126: seq="\x1b[A";break; case 125: seq="\x1b[B";break; case 124: seq="\x1b[C";break; case 123: seq="\x1b[D";break;
        case 115: seq="\x1b[H";break; case 119: seq="\x1b[F";break; case 117: seq="\x1b[3~";break; }
    if (seq) { write(_wfd, seq, strlen(seq)); return; }
    NSString *ch = e.characters; if (ch.length) { const char *b = [ch UTF8String]; write(_wfd, b, strlen(b)); }
}
- (void)sendResize {
    if (_wfd < 0) return;
    int cols = (int)(self.bounds.size.width / 7.2), rows = (int)(self.bounds.size.height / 15.0);
    if (cols < 8) cols = 8; if (rows < 2) rows = 2;
    if (cols == _cols && rows == _rows) return; _cols = cols; _rows = rows;
    char m[48]; int l = snprintf(m, sizeof m, "\036R,%d,%d\036", cols, rows); write(_wfd, m, l);
}
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self sendResize]; }
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

@interface Editor : NSObject <NSTextStorageDelegate, NSWindowDelegate, NSToolbarDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSControlTextEditingDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (strong) NSWindow *win;
@property (strong) NSTextView *tv;
@property (strong) NSString *path;     // nil = untitled (mirrors cur.path)
@property (strong) NSMutableArray<KDoc *> *docs;
@property (strong) KDoc *cur;
@property (strong) KTabBar *tabBar;
@property (strong) KTermView *term;
@property (strong) NSSplitView *vsplit;
@property (assign) BOOL termShown;
@property (strong) NSTextField *status;
@property (strong) FileNode *root;
@property (strong) NSOutlineView *outline;
@property (strong) NSPanel *qpPanel;
@property (strong) NSTableView *qpTable;
@property (strong) NSSearchField *qpField;
@property (strong) NSArray<NSString *> *qpAll;       // all project file paths
@property (strong) NSArray<NSString *> *qpHits;      // filtered display strings
@property (assign) NSInteger qpMode;                 // 0 = files, 1 = commands, 2 = find-in-files
@property (strong) NSArray *cmdLabels, *cmdSels;     // command palette
@property (strong) NSArray *cmdHitSels;              // selectors parallel to qpHits in cmd mode
@property (strong) NSMutableArray *fifPaths, *fifLines;  // find-in-files result locations
@property (strong) NSTextField *sbHeader;
@end

@implementation Editor

- (void)applyTitle {
    self.win.title = self.cur.title;
    self.win.representedFilename = self.cur.path ?: @"";
    self.win.documentEdited = self.cur.dirty;
}
- (BOOL)isDirty { return self.cur.dirty; }

- (TMGrammar *)grammarForPath:(NSString *)p {
    NSString *ext = p.pathExtension.lowercaseString;
    TMGrammar *g = gExtGrammar[ext];
    if (!g) g = loadGrammarForLang(gExtLang[ext] ?: gExtLang[p.lastPathComponent.lowercaseString]);
    return g;
}
// switch the visible document (swap the text view's storage; per-doc undo/selection/grammar)
- (void)showDoc:(KDoc *)d {
    if (self.cur && self.cur != d) self.cur.sel = self.tv.selectedRange;
    _cur = d;
    [self.tv.layoutManager replaceTextStorage:d.storage];
    d.storage.delegate = self;
    self.tv.selectedRange = NSMakeRange(MIN(d.sel.location, d.storage.length), 0);
    self.path = d.path;
    gActiveGrammar = d.grammar;
    highlight(d.storage);
    [self.tv scrollRangeToVisible:self.tv.selectedRange];
    [self applyTitle]; [self updateStatus]; [self.tabBar setNeedsDisplay:YES];
    [self.win makeFirstResponder:self.tv];
}
- (void)loadPath:(NSString *)p {
    for (KDoc *d in self.docs) if (d.path && [d.path isEqualToString:p]) { [self showDoc:d]; return; }
    NSString *txt = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil] ?: @"";
    KDoc *d = [KDoc new];
    d.storage = [[NSTextStorage alloc] initWithString:txt];
    d.path = p; d.sel = NSMakeRange(0,0); d.undo = [NSUndoManager new]; d.grammar = [self grammarForPath:p];
    [self.docs addObject:d];
    if (!self.root && self.outline) [self setFolder:[p stringByDeletingLastPathComponent]];
    [self showDoc:d];
}
- (void)selectDocAt:(NSInteger)i { if (i >= 0 && i < (NSInteger)self.docs.count) [self showDoc:self.docs[i]]; }
- (void)nextTab:(id)s { if (self.docs.count < 2) return; NSInteger i = [self.docs indexOfObject:self.cur]; [self selectDocAt:(i+1) % self.docs.count]; }
- (void)prevTab:(id)s { if (self.docs.count < 2) return; NSInteger i = [self.docs indexOfObject:self.cur]; [self selectDocAt:(i - 1 + self.docs.count) % self.docs.count]; }
- (void)closeDocAt:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.docs.count) return;
    KDoc *d = self.docs[i];
    if (d.dirty) {
        KDoc *was = self.cur; [self showDoc:d];
        NSAlert *a = [[NSAlert alloc] init]; a.messageText = [NSString stringWithFormat:@"Save %@?", d.title];
        [a addButtonWithTitle:@"Save"]; [a addButtonWithTitle:@"Discard"]; [a addButtonWithTitle:@"Cancel"];
        NSModalResponse r = [a runModal];
        if (r == NSAlertFirstButtonReturn) { [self saveDoc:nil]; if (d.dirty) { if (was && [self.docs containsObject:was]) [self showDoc:was]; return; } }
        else if (r == NSAlertThirdButtonReturn) { if (was && [self.docs containsObject:was]) [self showDoc:was]; return; }
    }
    BOOL wasCur = (d == self.cur);
    [self.docs removeObjectAtIndex:i];
    if (self.docs.count == 0) { [self newDoc:nil]; return; }
    if (wasCur) [self showDoc:self.docs[MIN(i, (NSInteger)self.docs.count - 1)]];
    else [self.tabBar setNeedsDisplay:YES];
}

// --- menu actions ---
- (void)newDoc:(id)s {
    KDoc *d = [KDoc new]; d.storage = [[NSTextStorage alloc] initWithString:@""]; d.undo = [NSUndoManager new]; d.sel = NSMakeRange(0,0);
    [self.docs addObject:d]; [self showDoc:d];
}
- (void)openDoc:(id)s {
    NSOpenPanel *o = [NSOpenPanel openPanel]; o.allowedFileTypes = nil; o.allowsMultipleSelection = NO;
    if ([o runModal] == NSModalResponseOK && o.URLs.count) [self loadPath:o.URLs[0].path];
}
- (BOOL)writeTo:(NSString *)p {
    BOOL ok = [self.tv.string writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (ok) { self.cur.path = p; self.cur.dirty = NO; self.path = p;
        self.cur.grammar = [self grammarForPath:p]; gActiveGrammar = self.cur.grammar; highlight(self.cur.storage);
        [self applyTitle]; [self.tabBar setNeedsDisplay:YES]; }
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
- (void)closeDoc:(id)s { [self closeDocAt:[self.docs indexOfObject:self.cur]]; }
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)v { return self.cur.undo ?: v.undoManager; }

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
- (void)toggleTerminal:(id)s {
    CGFloat H = self.vsplit.bounds.size.height;
    if (self.termShown) {
        [self.vsplit setPosition:H ofDividerAtIndex:0]; self.termShown = NO; [self.win makeFirstResponder:self.tv];
    } else {
        if (self.term.wfd < 0) {
            NSString *macos = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
            NSString *eng = [macos stringByAppendingPathComponent:@"kryoterm"];
            if (![[NSFileManager defaultManager] isExecutableFileAtPath:eng]) eng = @"../kryoterm/kryoterm";  // dev
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:eng]) [self.term spawn:eng];
        }
        [self.vsplit setPosition:H-220 ofDividerAtIndex:0]; self.termShown = YES;
        [self.win makeFirstResponder:self.term]; [self.term sendResize];
    }
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
    if (self.qpMode == 2) return;   // find-in-files results come from grep, not type-filter
    NSArray *src = (self.qpMode == 1) ? self.cmdLabels : self.qpAll;
    NSArray *sels = (self.qpMode == 1) ? self.cmdSels : nil;
    NSString *lq = q.lowercaseString;
    NSMutableArray *hits = [NSMutableArray array], *hsel = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)src.count; i++) {
        if (q.length == 0 || fuzzy([src[i] lowercaseString], lq)) {
            [hits addObject:src[i]]; if (sels) [hsel addObject:sels[i]];
            if (q.length == 0 && self.qpMode == 0 && hits.count >= 300) break;
        }
    }
    self.qpHits = hits; self.cmdHitSels = (self.qpMode == 1) ? hsel : nil;
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
    self.qpMode = 0; self.qpField.placeholderString = @"Go to file…  (fuzzy)";
    self.qpField.stringValue = @""; [self qpFilter:@""];
    [self.win beginSheet:self.qpPanel completionHandler:nil];
    [self.qpPanel makeFirstResponder:self.qpField];
}
- (void)commandPalette:(id)s {
    self.cmdLabels = @[@"New File", @"Open File…", @"Open Folder…", @"Save", @"Save As…", @"Build", @"Run",
                       @"Quick Open…", @"Go to Line…", @"Install Extension…", @"Next Tab", @"Previous Tab", @"Close Tab", @"New Window"];
    self.cmdSels   = @[@"newDoc:", @"openDoc:", @"openFolder:", @"saveDoc:", @"saveAs:", @"build:", @"run:",
                       @"quickOpen:", @"goToLine:", @"installExtension:", @"nextTab:", @"prevTab:", @"closeDoc:", @"newWindowCmd:"];
    if (!self.qpPanel) [self buildQuickOpen];
    self.qpMode = 1; self.qpField.placeholderString = @"Run a command…";
    self.qpField.stringValue = @""; [self qpFilter:@""];
    [self.win beginSheet:self.qpPanel completionHandler:nil];
    [self.qpPanel makeFirstResponder:self.qpField];
}
- (void)newWindowCmd:(id)s { /* single-window for now */ [self newDoc:s]; }
- (void)findInFiles:(id)s {
    if (!self.root) { [self openFolder:s]; if (!self.root) return; }
    if (!self.qpPanel) [self buildQuickOpen];
    self.qpMode = 2; self.qpField.placeholderString = @"Search in files…  (Enter)";
    self.qpField.stringValue = @""; self.qpHits = @[];
    self.fifPaths = [NSMutableArray array]; self.fifLines = [NSMutableArray array];
    [self.qpTable reloadData];
    [self.win beginSheet:self.qpPanel completionHandler:nil];
    [self.qpPanel makeFirstResponder:self.qpField];
}
- (void)fifRun {
    NSString *q = self.qpField.stringValue; if (q.length == 0) return;
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/grep"];
    t.arguments = @[@"-rnI", @"--exclude-dir=.git", @"--exclude-dir=node_modules", @"--exclude-dir=dist", @"-e", q, self.root.path];
    NSPipe *pipe = [NSPipe pipe]; t.standardOutput = pipe; t.standardError = [NSPipe pipe];
    if (![t launchAndReturnError:nil]) return;
    NSData *d = [pipe.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    NSString *out = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableArray *hits = [NSMutableArray array], *paths = [NSMutableArray array], *lines = [NSMutableArray array];
    NSUInteger rootLen = self.root.path.length + 1;
    for (NSString *ln in [out componentsSeparatedByString:@"\n"]) {
        if (ln.length == 0) continue;
        NSRange c1 = [ln rangeOfString:@":"]; if (c1.location == NSNotFound) continue;
        NSRange c2 = [ln rangeOfString:@":" options:0 range:NSMakeRange(NSMaxRange(c1), ln.length-NSMaxRange(c1))]; if (c2.location == NSNotFound) continue;
        NSString *path = [ln substringToIndex:c1.location];
        NSString *lno = [ln substringWithRange:NSMakeRange(NSMaxRange(c1), c2.location-NSMaxRange(c1))];
        NSString *txt = [[ln substringFromIndex:NSMaxRange(c2)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *rel = path.length > rootLen ? [path substringFromIndex:rootLen] : path;
        [hits addObject:[NSString stringWithFormat:@"%@:%@   %@", rel, lno, txt.length>90?[txt substringToIndex:90]:txt]];
        [paths addObject:path]; [lines addObject:@(lno.intValue)];
        if (hits.count >= 500) break;
    }
    self.qpHits = hits; self.fifPaths = paths; self.fifLines = lines;
    [self.qpTable reloadData];
    if (hits.count) [self.qpTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}
- (void)gotoLineNumber:(int)ln {
    NSString *full = self.tv.string; NSUInteger pos = 0; int cur = 1;
    while (cur < ln && pos < full.length) { if ([full characterAtIndex:pos] == '\n') cur++; pos++; }
    NSRange lr = [full lineRangeForRange:NSMakeRange(MIN(pos, full.length), 0)];
    self.tv.selectedRange = NSMakeRange(lr.location, 0);
    [self.tv scrollRangeToVisible:self.tv.selectedRange];
    [self.win makeFirstResponder:self.tv];
}
- (void)qpOpenSelected {
    NSInteger r = self.qpTable.selectedRow;
    [self.win endSheet:self.qpPanel];
    if (r < 0 || r >= (NSInteger)self.qpHits.count) return;
    if (self.qpMode == 1) {
        SEL sel = NSSelectorFromString(self.cmdHitSels[r]);
        if ([self respondsToSelector:sel]) { IMP imp = [self methodForSelector:sel]; void (*fn)(id, SEL, id) = (void *)imp; fn(self, sel, nil); }
    } else if (self.qpMode == 2) {
        if (r < (NSInteger)self.fifPaths.count) { [self loadPath:self.fifPaths[r]]; [self gotoLineNumber:[self.fifLines[r] intValue]]; }
    } else [self loadPath:[self.root.path stringByAppendingPathComponent:self.qpHits[r]]];
}
- (void)controlTextDidChange:(NSNotification *)n { if (n.object == self.qpField) [self qpFilter:self.qpField.stringValue]; }
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    if (c != self.qpField) return NO;
    NSInteger r = self.qpTable.selectedRow, n = self.qpHits.count;
    if (sel == @selector(insertNewline:)) { if (self.qpMode == 2) [self fifRun]; else [self qpOpenSelected]; return YES; }
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
    dispatch_async(dispatch_get_main_queue(), ^{ highlight(ts); self.cur.dirty = YES; self.win.documentEdited = YES; [self.tabBar setNeedsDisplay:YES]; });
}
- (BOOL)windowShouldClose:(NSWindow *)w {
    BOOL any = NO; for (KDoc *d in self.docs) if (d.dirty) any = YES;
    if (!any) return YES;
    NSAlert *a = [[NSAlert alloc] init]; a.messageText = @"Save all changes before closing?";
    [a addButtonWithTitle:@"Save All"]; [a addButtonWithTitle:@"Discard"]; [a addButtonWithTitle:@"Cancel"];
    NSModalResponse r = [a runModal];
    if (r == NSAlertSecondButtonReturn) return YES;
    if (r == NSAlertThirdButtonReturn) return NO;
    for (KDoc *d in [self.docs copy]) if (d.dirty) { [self showDoc:d]; [self saveDoc:nil]; }
    BOOL still = NO; for (KDoc *d in self.docs) if (d.dirty) still = YES;
    return !still;
}
- (void)windowWillClose:(NSNotification *)n { [NSApp terminate:nil]; }
@end

@implementation KTabBar
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.13 alpha:1] set]; NSRectFill(self.bounds);
    self.hit = [NSMutableArray array];
    Editor *ed = self.ed; if (!ed) return;
    CGFloat x = 0, h = self.bounds.size.height;
    NSDictionary *act = @{NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:0.92 alpha:1], NSFontAttributeName:[NSFont systemFontOfSize:12]};
    NSDictionary *ina = @{NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:0.56 alpha:1], NSFontAttributeName:[NSFont systemFontOfSize:12]};
    NSColor *xc = [NSColor colorWithCalibratedWhite:0.6 alpha:1];
    for (KDoc *d in ed.docs) {
        BOOL cur = (d == ed.cur); NSString *nm = d.title;
        CGFloat tw = MIN([nm sizeWithAttributes:act].width + 48, 220);
        NSRect tab = NSMakeRect(x, 0, tw, h);
        [self.hit addObject:[NSValue valueWithRect:tab]];
        if (cur) { [[NSColor colorWithCalibratedRed:0.145 green:0.145 blue:0.165 alpha:1] set]; NSRectFill(tab);
                   [[NSColor colorWithCalibratedRed:0.24 green:0.60 blue:0.95 alpha:1] set]; NSRectFill(NSMakeRect(x, h-2, tw, 2)); }
        [nm drawAtPoint:NSMakePoint(x+12, (h-15)/2) withAttributes:(cur?act:ina)];
        if (d.dirty) { [[NSColor colorWithCalibratedWhite:0.78 alpha:1] set]; NSRectFill(NSMakeRect(x+tw-18, (h-7)/2, 7, 7)); }
        else { [@"⨯" drawAtPoint:NSMakePoint(x+tw-19, (h-16)/2) withAttributes:@{NSForegroundColorAttributeName:xc, NSFontAttributeName:[NSFont systemFontOfSize:13]}]; }
        [[NSColor colorWithCalibratedWhite:0.07 alpha:1] set]; NSRectFill(NSMakeRect(x+tw-1, 0, 1, h));
        x += tw;
    }
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    for (NSInteger i = 0; i < (NSInteger)self.hit.count; i++) {
        NSRect t = [self.hit[i] rectValue];
        if (NSPointInRect(p, t)) {
            if (p.x > NSMaxX(t) - 24) [self.ed closeDocAt:i]; else [self.ed selectDocAt:i];
            [self setNeedsDisplay:YES]; return;
        }
    }
}
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
    mi(nav, @"Command Palette…", @selector(commandPalette:), @"p", gEd).keyEquivalentModifierMask = (NSEventModifierFlagCommand|NSEventModifierFlagShift);
    mi(nav, @"Quick Open…", @selector(quickOpen:), @"p", gEd);
    mi(nav, @"Find in Files…", @selector(findInFiles:), @"f", gEd).keyEquivalentModifierMask = (NSEventModifierFlagCommand|NSEventModifierFlagShift);
    mi(nav, @"Go to Line…", @selector(goToLine:), @"l", gEd);
    [nav addItem:[NSMenuItem separatorItem]];
    mi(nav, @"Next Tab", @selector(nextTab:), @"]", gEd).keyEquivalentModifierMask = (NSEventModifierFlagCommand|NSEventModifierFlagShift);
    mi(nav, @"Previous Tab", @selector(prevTab:), @"[", gEd).keyEquivalentModifierMask = (NSEventModifierFlagCommand|NSEventModifierFlagShift);
    [nav addItem:[NSMenuItem separatorItem]];
    mi(nav, @"Toggle Terminal", @selector(toggleTerminal:), @"`", gEd).keyEquivalentModifierMask = NSEventModifierFlagControl;
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
        gLangCache = [NSMutableDictionary dictionary];
        gGrammarDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"grammars"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:gGrammarDir]) gGrammarDir = @"grammars";  // dev: cwd
        NSData *md = [NSData dataWithContentsOfFile:[gGrammarDir stringByAppendingPathComponent:@"manifest.json"]];
        if (md) { NSDictionary *m = [NSJSONSerialization JSONObjectWithData:md options:0 error:nil]; gExtLang = m[@"ext"]; gScopeLang = m[@"scope"]; }
        loadExtensions();   // VS Code extensions (Krypton VSIX etc.)

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
        // right pane = tab bar (top) + editor
        NSView *rightPane = [[NSView alloc] initWithFrame:NSMakeRect(0,0,frame.size.width-210, frame.size.height-22)];
        rightPane.autoresizesSubviews = YES;
        KTabBar *tabBar = [[KTabBar alloc] initWithFrame:NSMakeRect(0, rightPane.bounds.size.height-28, rightPane.bounds.size.width, 28)];
        tabBar.ed = gEd; tabBar.autoresizingMask = (NSViewWidthSizable|NSViewMinYMargin); gEd.tabBar = tabBar;
        // editor / terminal vertical split below the tab bar
        CGFloat rpw = rightPane.bounds.size.width, rph = rightPane.bounds.size.height;
        NSSplitView *vsplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0,0,rpw,rph-28)];
        vsplit.vertical = NO; vsplit.dividerStyle = NSSplitViewDividerStyleThin;
        vsplit.autoresizingMask = (NSViewWidthSizable|NSViewHeightSizable);
        scroll.frame = vsplit.bounds; scroll.autoresizingMask = (NSViewWidthSizable|NSViewHeightSizable);
        NSScrollView *termScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,rpw,1)];
        termScroll.hasVerticalScroller = YES; termScroll.borderType = NSNoBorder;
        KTermView *term = [[KTermView alloc] initWithFrame:termScroll.bounds];
        term.wfd = -1; term.rfd = -1;
        term.mono = [NSFont fontWithName:@"JetBrainsMono Nerd Font Mono" size:12] ?: [NSFont userFixedPitchFontOfSize:12];
        term.backgroundColor = [NSColor colorWithCalibratedRed:0.09 green:0.09 blue:0.11 alpha:1];
        term.minSize = NSMakeSize(0,0); term.maxSize = NSMakeSize(FLT_MAX,FLT_MAX);
        term.verticallyResizable = YES; term.horizontallyResizable = NO; term.textContainer.widthTracksTextView = YES;
        term.textContainerInset = NSMakeSize(6,4);
        termScroll.documentView = term;
        [vsplit addSubview:scroll]; [vsplit addSubview:termScroll];
        gEd.term = term; gEd.vsplit = vsplit;
        [vsplit adjustSubviews]; [vsplit setPosition:rph-28 ofDividerAtIndex:0];   // terminal collapsed initially
        [rightPane addSubview:tabBar]; [rightPane addSubview:vsplit];
        [split addSubview:leftPane]; [split addSubview:rightPane];
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
        gEd.docs = [NSMutableArray array]; tv.delegate = gEd;   // multi-document tabs + per-doc undo

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
        if (gEd.docs.count == 0) [gEd newDoc:nil];     // always one open document
        [gEd applyTitle];
        [gEd updateStatus];

        [win center]; [win makeKeyAndOrderFront:nil]; [win makeFirstResponder:tv];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
