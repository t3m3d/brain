// Local App Store packaging only. Upload and submission are separate user-reviewed steps.
import "tooling.k"
func packageStore() {
    let root = repoRoot()
    let bundleID = env("STORE_BUNDLE_ID")
    let team = env("STORE_TEAM_ID")
    let applicationIdentity = env("STORE_APPLICATION_IDENTITY")
    let installerIdentity = env("STORE_INSTALLER_IDENTITY")
    let profile = env("STORE_PROVISIONING_PROFILE")
    if bundleID == "" || team == "" || applicationIdentity == "" || installerIdentity == "" || profile == "" {
        kp("Set STORE_BUNDLE_ID, STORE_TEAM_ID, STORE_APPLICATION_IDENTITY, STORE_INSTALLER_IDENTITY, and STORE_PROVISIONING_PROFILE.")
        kp("Use Mac App Store distribution identities; Developer ID is for direct distribution.")
        exit(1)
    }
    if indexOf(bundleID, "preview") >= 0 { kp("Choose a registered release bundle identifier")  exit(1) }
    let gates = readFile(root + "/docs/RELEASE_READINESS.md")
    let storeGates = indexOf(gates, "## Mac App Store gates")
    if storeGates >= 0 { gates = substring(gates, 0, storeGates) }
    if indexOf(gates, "- [ ]") >= 0 {
        kp("Complete docs/RELEASE_READINESS.md acceptance gates before release packaging")
        exit(1)
    }
    let source = root + "/dist/brain-store.app"
    if shOk("test -f " + quoteArg(source + "/Contents/Resources/brain.icns")) != "1" {
        kp("Build the Store edition with its final icon first")  exit(1)
    }
    let stage = sh("mktemp -d /tmp/brain-store-package.XXXXXX")
    if stage == "" { kp("Could not stage Store package")  exit(1) }
    let app = stage + "/brain.app"
    checked("ditto " + quoteArg(source) + " " + quoteArg(app))
    checked("security cms -D -i " + quoteArg(profile) + " > " + quoteArg(stage + "/profile.plist"))
    let appID = sh("/usr/libexec/PlistBuddy -c " + quoteArg("Print :Entitlements:com.apple.application-identifier") + " " + quoteArg(stage + "/profile.plist"))
    if appID != team + "." + bundleID { kp("Provisioning profile does not match team and bundle identifier")  exit(1) }
    let debugging = sh("/usr/libexec/PlistBuddy -c " + quoteArg("Print :Entitlements:get-task-allow") + " " + quoteArg(stage + "/profile.plist"))
    if debugging == "true" { kp("Use a distribution profile without get-task-allow")  exit(1) }
    checked("plutil -replace CFBundleIdentifier -string " + quoteArg(bundleID) + " " + quoteArg(app + "/Contents/Info.plist"))
    checked("cp " + quoteArg(profile) + " " + quoteArg(app + "/Contents/embedded.provisionprofile"))
    checked("cp " + quoteArg(root + "/packaging/store.entitlements") + " " + quoteArg(stage + "/entitlements.plist"))
    checked("/usr/libexec/PlistBuddy -c " + quoteArg("Add :com.apple.application-identifier string " + appID) + " " + quoteArg(stage + "/entitlements.plist"))
    checked("/usr/libexec/PlistBuddy -c " + quoteArg("Add :com.apple.developer.team-identifier string " + team) + " " + quoteArg(stage + "/entitlements.plist"))
    checked("codesign --force --options runtime --timestamp --sign " + quoteArg(applicationIdentity) + " --entitlements " + quoteArg(stage + "/entitlements.plist") + " " + quoteArg(app))
    checked("codesign --verify --strict " + quoteArg(app))
    let signature = exec("codesign -dv --verbose=2 " + quoteArg(app) + " 2>&1")
    if indexOf(signature, "Authority=3rd Party Mac Developer Application:") < 0 && indexOf(signature, "Authority=Apple Distribution:") < 0 {
        kp("Signed app must use an App Store distribution certificate")  exit(1)
    }
    let pkg = stage + "/brain-app-store.pkg"
    checked("productbuild --component " + quoteArg(app) + " /Applications --sign " + quoteArg(installerIdentity) + " " + quoteArg(pkg))
    let installerSignature = exec("pkgutil --check-signature " + quoteArg(pkg) + " 2>&1")
    if indexOf(installerSignature, "3rd Party Mac Developer Installer:") < 0 {
        kp("Installer must use a Mac Installer Distribution certificate")  exit(1)
    }
    checked("mkdir -p " + quoteArg(root + "/dist"))
    checked("mv " + quoteArg(pkg) + " " + quoteArg(root + "/dist/brain-app-store.pkg"))
    checked("rm -rf " + quoteArg(stage))
    kp("Built dist/brain-app-store.pkg. Review and validate before upload; nothing submitted.")
}
