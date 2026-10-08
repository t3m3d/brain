#!/usr/bin/env kr
// Compatibility entry point: package the pure Objective K editor.
import "k:sh"
import "k:env"
import "scripts/build.k"
just run {
    let root = repoRoot()
    buildBrain()
    checked("mkdir -p " + quoteArg(root + "/dist"))
    checked("rm -rf " + quoteArg(root + "/dist/brain.app") + " && cp -R " + quoteArg(root + "/brain.app") + " " + quoteArg(root + "/dist/brain.app"))
    kp("Built dist/brain.app")
}
