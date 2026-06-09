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
@interface Editor : NSObject <NSTextStorageDelegate, NSWindowDelegate, NSToolbarDelegate>
@property (strong) NSWindow *win;
@property (strong) NSTextView *tv;
@property (strong) NSString *path;     // nil = untitled
@property (strong) NSTextField *status;
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
    highlight(self.tv.textStorage);
    self.path = p;
    self.win.documentEdited = NO;
    [self applyTitle];
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

        NSTextView *tv = [[NSTextView alloc] initWithFrame:frame];
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

        // container: scroll view above a status bar
        NSView *container = [[NSView alloc] initWithFrame:frame];
        container.autoresizesSubviews = YES;
        scroll.frame = NSMakeRect(0, 22, frame.size.width, frame.size.height - 22);
        [container addSubview:scroll];
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

        // open a file passed on argv (kcode <file>)
        if (argc > 1) { NSString *p = [NSString stringWithUTF8String:argv[1]];
            if (![p hasPrefix:@"/"]) p = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:p];
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) [gEd loadPath:p]; }
        [gEd applyTitle];
        [gEd updateStatus];

        [win center]; [win makeKeyAndOrderFront:nil]; [win makeFirstResponder:tv];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
