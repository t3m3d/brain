// make_icon.m — render kcode.icns (violet squircle + code glyph).
// clang -framework Cocoa make_icon.m -o /tmp/mkicon && /tmp/mkicon
#import <Cocoa/Cocoa.h>

static NSData *renderPNG(int S) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:S pixelsHigh:S
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:ctx];
    CGFloat m = S*0.085, r = S*0.225;
    NSRect box = NSMakeRect(m, m, S-2*m, S-2*m);
    NSBezierPath *sq = [NSBezierPath bezierPathWithRoundedRect:box xRadius:r yRadius:r];
    NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithCalibratedRed:0.55 green:0.20 blue:0.95 alpha:1], 0.0,
        [NSColor colorWithCalibratedRed:0.36 green:0.10 blue:0.78 alpha:1], 1.0, nil];
    [g drawInBezierPath:sq angle:-90];
    // code glyph " </> " in a bold mono-ish font, centered
    NSString *glyph = @"</>";
    NSFont *f = [NSFont fontWithName:@"Menlo-Bold" size:S*0.30] ?: [NSFont boldSystemFontOfSize:S*0.30];
    NSDictionary *at = @{ NSFontAttributeName:f, NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:1 alpha:0.96] };
    NSSize ts = [glyph sizeWithAttributes:at];
    [glyph drawAtPoint:NSMakePoint((S-ts.width)/2, (S-ts.height)/2 + S*0.015) withAttributes:at];
    // a small caret underline (editor cursor) below
    [[NSColor colorWithCalibratedRed:0.40 green:0.85 blue:0.55 alpha:0.95] set];
    NSRectFill(NSMakeRect((S-ts.width)/2 + ts.width*0.30, (S-ts.height)/2 - S*0.02, ts.width*0.40, S*0.030));
    [NSGraphicsContext restoreGraphicsState];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
int main(void) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *iconset = @"/tmp/kcode.iconset"; [fm removeItemAtPath:iconset error:nil];
        [fm createDirectoryAtPath:iconset withIntermediateDirectories:YES attributes:nil error:nil];
        NSArray *specs = @[@[@"icon_16x16.png",@16], @[@"icon_16x16@2x.png",@32], @[@"icon_32x32.png",@32], @[@"icon_32x32@2x.png",@64],
                           @[@"icon_128x128.png",@128], @[@"icon_128x128@2x.png",@256], @[@"icon_256x256.png",@256], @[@"icon_256x256@2x.png",@512],
                           @[@"icon_512x512.png",@512], @[@"icon_512x512@2x.png",@1024]];
        for (NSArray *sp in specs) [renderPNG([sp[1] intValue]) writeToFile:[iconset stringByAppendingPathComponent:sp[0]] atomically:YES];
        printf("wrote %s\n", iconset.UTF8String);
    }
    return 0;
}
