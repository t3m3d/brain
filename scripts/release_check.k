// Static distribution gates. A passed preflight still needs UI and TestFlight testing.
import "tooling.k"
func releaseCheck() {
    let root = repoRoot()
    let app = root + "/dist/brain-store.app"
    let problems = 0
    if shOk("test -d " + quoteArg(app)) != "1" {
        kp("BLOCKED: build Store preview first: kr build_store.ks")
        exit(1)
    }
    if shOk("codesign --verify --strict " + quoteArg(app)) != "1" {
        kp("BLOCKED: bundle signature verification failed")
        problems = problems + 1
    }
    let signature = exec("codesign -dv --verbose=2 " + quoteArg(app) + " 2>&1")
    if indexOf(signature, "Signature=adhoc") >= 0 {
        kp("BLOCKED: ad-hoc signature; App Store distribution signing required")
        problems = problems + 1
    }
    if shOk("test -f " + quoteArg(app + "/Contents/Resources/brain.icns")) != "1" {
        kp("BLOCKED: final app icon missing")
        problems = problems + 1
    }
    let gates = readFile(root + "/docs/RELEASE_READINESS.md")
    if indexOf(gates, "- [ ]") >= 0 {
        kp("BLOCKED: release acceptance gates remain unchecked; see docs/RELEASE_READINESS.md")
        problems = problems + 1
    }
    if problems > 0 { kp("Release preflight: " + problems + " blocker(s)")  exit(1) }
    kp("Static preflight passed. Validate signed archive and TestFlight before submission.")
}
