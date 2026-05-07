import "hl.k"

just run {
    let lines = "func main() {\nlet x = 42  // a number\nkp(`hello {x}`)\n}"
    let i = 0
    while i < lineCount(lines) {
        kp(hlLine(getLine(lines, i), 1))
        i += 1
    }
}
