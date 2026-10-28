#!/usr/bin/env kr
// Package the supplied artwork as a multi-resolution macOS app icon.
import "k:sh"
import "k:env"
import "scripts/tooling.k"
just run {
    let root = repoRoot()
    let source = root + "/codebrain.png"
    if shOk("test -f " + quoteArg(source)) != "1" { print("Missing codebrain.png in repo root")  exit(1) }
    let stage = sh("mktemp -d /tmp/brain-icon.XXXXXX")
    if stage == "" { print("Could not stage icon assets")  exit(1) }
    let icons = stage + "/brain.iconset"
    checked("mkdir -p " + quoteArg(icons))
    let i = 0
    while i < 5 {
        let size = 16
        if i == 1 { size = 32 }
        if i == 2 { size = 128 }
        if i == 3 { size = 256 }
        if i == 4 { size = 512 }
        let filename = icons + "/icon_" + size + "x" + size
        checked("/usr/bin/sips -z " + size + " " + size + " " + quoteArg(source) + " --out " + quoteArg(filename + ".png"))
        let retina = size * 2
        checked("/usr/bin/sips -z " + retina + " " + retina + " " + quoteArg(source) + " --out " + quoteArg(filename + "@2x.png"))
        i = i + 1
    }
    checked("mkdir -p " + quoteArg(root + "/packaging"))
    checked("/usr/bin/iconutil -c icns " + quoteArg(icons) + " -o " + quoteArg(stage + "/brain.icns"))
    checked("cp " + quoteArg(stage + "/brain.icns") + " " + quoteArg(root + "/packaging/brain.icns"))
    checked("cp " + quoteArg(icons + "/icon_512x512@2x.png") + " " + quoteArg(root + "/packaging/store-icon-1024.png"))
    checked("rm -rf " + quoteArg(stage))
    print("Packaged supplied codebrain.png as macOS and Store icon assets")
}
