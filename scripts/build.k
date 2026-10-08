// Shared Objective K bundle builder.
import "tooling.k"

func buildBrain() { buildEdition(0) }
func buildStore() { buildEdition(1) }

func buildEdition(store) {
    let root = repoRoot()
    let krypton = kryptonRoot()
    if sh("uname -s") != "Darwin" { kp("brain.app requires macOS.")  exit(1) }
    if shOk("test -d " + quoteArg(krypton + "/stdlib")) != "1" {
        kp("Set KRYPTON to a Krypton checkout.")  exit(1)
    }
    // Assemble in a unique staging directory; preserve the previous app on failure.
    let stage = sh("mktemp -d /tmp/brain-build.XXXXXX")
    if stage == "" { kp("Could not create build staging directory.")  exit(1) }
    let app = stage + "/brain.app"
    checked("mkdir -p " + quoteArg(app + "/Contents/MacOS") + " " + quoteArg(app + "/Contents/Resources"))
    checked("env KRYPTON_ROOT=" + quoteArg(krypton) + " kcc --native " + quoteArg(root + "/brain.ks") + " -o " + quoteArg(app + "/Contents/MacOS/brain"))
    let icon = ""
    if shOk("test -f " + quoteArg(root + "/brain.icns")) == "1" {
        checked("cp " + quoteArg(root + "/brain.icns") + " " + quoteArg(app + "/Contents/Resources/brain.icns"))
        icon = "<key>CFBundleIconFile</key><string>brain</string>"
    }
    let bundleID = "org.krypton-lang.brain"
    let storeFlag = ""
    if store == 1 {
        bundleID = "org.krypton-lang.brain.store-preview"
        storeFlag = "<key>BrainStoreEdition</key><true/><key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>"
    }
    let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>" +
        "<key>CFBundleName</key><string>brain</string>" +
        "<key>CFBundleExecutable</key><string>brain</string>" +
        "<key>CFBundleIdentifier</key><string>" + bundleID + "</string>" + storeFlag +
        "<key>CFBundlePackageType</key><string>APPL</string>" +
        "<key>CFBundleVersion</key><string>0.4.0</string>" +
        "<key>CFBundleShortVersionString</key><string>0.4.0</string>" +
        "<key>LSMinimumSystemVersion</key><string>13.0</string>" +
        "<key>NSHighResolutionCapable</key><true/>" + icon +
        "<key>CFBundleDocumentTypes</key><array><dict>" +
        "<key>CFBundleTypeName</key><string>Source code</string>" +
        "<key>CFBundleTypeRole</key><string>Editor</string>" +
        "<key>CFBundleTypeExtensions</key><array><string>k</string><string>ks</string><string>htk</string></array>" +
        "</dict></array></dict></plist>\n"
    writeFile(app + "/Contents/Info.plist", plist)
    checked("plutil -lint " + quoteArg(app + "/Contents/Info.plist"))
    let destination = root + "/brain.app"
    if store == 1 {
        checked("mkdir -p " + quoteArg(root + "/dist"))
        destination = root + "/dist/brain-store.app"
        checked("codesign -s - -f --entitlements " + quoteArg(root + "/packaging/store.entitlements") + " " + quoteArg(app))
    } else { checked("codesign -s - -f " + quoteArg(app)) }
    checked("codesign --verify --strict " + quoteArg(app))
    checked("rm -rf " + quoteArg(destination) + " && cp -R " + quoteArg(app) + " " + quoteArg(destination))
    checked("rm -rf " + quoteArg(stage))
    if store == 1 { kp("Built sandboxed dist/brain-store.app (ad-hoc test build; not submission-ready)") }
    else { kp("Built brain.app — open brain.app") }
}
