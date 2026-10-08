#!/usr/bin/env kr
// Install the Objective K app. Pass a destination folder; defaults to ~/Applications.
import "k:sh"
import "k:env"
import "scripts/build.k"
just run {
    let root = repoRoot()
    let destination = env("HOME") + "/Applications"
    if argCount() > 0 { destination = arg("0") }
    if shOk("test -x " + quoteArg(root + "/brain.app/Contents/MacOS/brain")) != "1" {
        buildBrain()
    }
    checked("mkdir -p " + quoteArg(destination))
    checked("ditto " + quoteArg(root + "/brain.app") + " " + quoteArg(destination + "/brain.app"))
    kp("Installed " + destination + "/brain.app")
}
