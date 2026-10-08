// Shared KryptScript process helpers. Commands retain their exit status.
import "k:sh"
import "k:env"

// POSIX single-quote escaping, including apostrophes in paths.
func quoteArg(s) {
    let out = "'"
    let i = 0
    while i < len(s) {
        let c = substring(s, i, i + 1)
        if c == "'" { out = out + "'\"'\"'" } else { out = out + c }
        i = i + 1
    }
    emit out + "'"
}
func checked(command) {
    // Capture diagnostics and a status marker together; exec returns stdout only.
    let out = exec("( " + command + " ) 2>&1; result=$?; printf '\n__KCODE_STATUS_%s' \"$result\"")
    let marker = indexOf(out, "\n__KCODE_STATUS_")
    if marker < 0 { kp(out)  exit(1) }
    let message = substring(out, 0, marker)
    if len(message) > 0 { kp(message) }
    let status = substring(out, marker + 16, len(out))
    if status != "0" { exit(toInt(status)) }
    emit "1"
}
func repoRoot() {
    let root = env("KCODE_ROOT")
    if root == "" { root = sh("pwd") }
    if shOk("test -f " + quoteArg(root + "/brain.ks")) != "1" {
        kp("Run from the kcode checkout, or set KCODE_ROOT to it.")
        exit(1)
    }
    emit root
}
func kryptonRoot() {
    let root = envOr("KRYPTON", env("KRYPTON_ROOT"))
    if root != "" { emit root }
    if shOk("test -d /usr/local/krypton/stdlib") == "1" { emit "/usr/local/krypton" }
    emit env("HOME") + "/Documents/GitHub/krypton"
}
