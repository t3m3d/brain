// Shared Objective K bundle builder.
import "tooling.k"

func buildBrain() {
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
    let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>" +
        "<key>CFBundleName</key><string>brain</string>" +
        "<key>CFBundleExecutable</key><string>brain</string>" +
        "<key>CFBundleIdentifier</key><string>org.krypton-lang.brain</string>" +
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
    checked("codesign --deep -s - -f " + quoteArg(app))
    checked("rm -rf " + quoteArg(root + "/brain.app") + " && cp -R " + quoteArg(app) + " " + quoteArg(root + "/brain.app"))
    checked("rm -rf " + quoteArg(stage))
    kp("Built brain.app — open brain.app")
}
