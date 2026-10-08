#!/usr/bin/env kr
// Render the existing vector icon artwork; app UI remains pure Objective K.
import "k:sh"
import "k:env"
import "scripts/tooling.k"
just run {
    let root = repoRoot()
    let stage = sh("mktemp -d /tmp/brain-icon.XXXXXX")
    if stage == "" { kp("Could not stage icon renderer")  exit(1) }
    checked("xcrun clang -framework Cocoa " + quoteArg(root + "/make_icon.m") + " -o " + quoteArg(stage + "/render"))
    checked(quoteArg(stage + "/render"))
    checked("mkdir -p " + quoteArg(root + "/packaging"))
    checked("iconutil -c icns /tmp/kcode.iconset -o " + quoteArg(root + "/packaging/brain.icns"))
    checked("cp /tmp/kcode.iconset/icon_512x512@2x.png " + quoteArg(root + "/packaging/store-icon-1024.png"))
    checked("rm -rf " + quoteArg(stage))
    kp("Rendered packaging/brain.icns and Store icon from existing artwork")
}
