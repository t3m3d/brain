import "tree.k"

just run {
    let t = treeNew(".")
    let n = treeRows(t)
    kp("rows: " + n)
    let i = 0
    while i < n {
        let row = treeRowAt(t, i)
        kp("[" + i + "] depth=" + treeFieldOf(row, 0) + " dir=" + treeFieldOf(row, 1) + " open=" + treeFieldOf(row, 2) + " name=" + treeFieldOf(row, 3) + " full=" + treeFieldOf(row, 4))
        i += 1
    }
}
