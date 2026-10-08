#!/usr/bin/env kr
// Run the native app's document-model regressions and propagate failures.
import "k:sh"
import "k:env"
import "../scripts/tooling.k"
just run {
    checked(quoteArg(repoRoot() + "/brain.app/Contents/MacOS/brain") + " --self-test")
}
