// Sanity check buf.k parses + basic ops work.
import "buf.k"

just run {
    let b = bufNewEmpty()
    b = bufInsertChar(b, "h")
    b = bufInsertChar(b, "i")
    b = bufInsertNewline(b)
    b = bufInsertChar(b, "x")
    print("text=[" + envGet(b, "text") + "]")
    print("row=" + envGet(b, "row") + " col=" + envGet(b, "col") + " lines=" + bufNumLines(b))

    b = bufBackspace(b)
    print("after bs: text=[" + envGet(b, "text") + "] row=" + envGet(b, "row") + " col=" + envGet(b, "col"))

    b = bufUndo(b)
    print("undo: text=[" + envGet(b, "text") + "]")
    b = bufUndo(b)
    print("undo2: text=[" + envGet(b, "text") + "]")
    b = bufRedo(b)
    print("redo: text=[" + envGet(b, "text") + "]")
}
