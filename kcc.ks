#!/usr/bin/env kr
// Forward to the toolchain's native compiler driver instead of maintaining a
// stale copy of its platform backends in the editor repository.
import "scripts/tooling.k"
just run {
    let driver = which("kcc")
    if driver == "" {
        kp("Install the current Krypton macOS toolchain (kcc must be on PATH).")
        exit(1)
    }
    let command = quoteArg(driver)
    let i = 0
    while i < argCount() { command = command + " " + quoteArg(arg(i))  i = i + 1 }
    checked(command)
}
