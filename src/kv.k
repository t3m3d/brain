// kv.k — pure-Krypton key/value store (replaces the env* builtins, which only
// existed in the retired C path). Encoding is length-prefixed so a value may
// contain any bytes (the whole file text is stored as one value):
//
//   record := <klen> "|" <key bytes> <vlen> "|" <value bytes>
//   store  := record*
//
// Values are stored as strings (callers toInt numeric fields). Last-write wins:
// kvSet removes any existing record for the key, then appends the new one.

module kv

func kvNew() { emit "" }

func _enc(s) { emit "" + len(s) + "|" + s }   // "" first: force string concat (int+string is int-add)

// Remove the record for `k` (if present); return the store without it.
func _kvDel(e, k) {
    let n = len(e)
    let p = 0
    let out = ""
    while p < n {
        let rest = substring(e, p, n)
        let b1 = indexOf(rest, "|")
        if b1 < 0 { emit out }                      // malformed -> stop
        let klen = toInt(substring(e, p, p + b1))
        let ks = p + b1 + 1
        let key = substring(e, ks, ks + klen)
        let vp = ks + klen
        let rest2 = substring(e, vp, n)
        let b2 = indexOf(rest2, "|")
        if b2 < 0 { emit out }
        let vlen = toInt(substring(e, vp, vp + b2))
        let vs = vp + b2 + 1
        let recEnd = vs + vlen
        if key != k { out = out + substring(e, p, recEnd) }
        p = recEnd
    }
    emit out
}

func kvSet(e, k, v) {
    let cleaned = _kvDel(e, k)
    let sv = "" + v                 // coerce int|string -> string (toStr crashes on int params here)
    emit cleaned + _enc(k) + _enc(sv)
}

// Keys whose values are integers (kvSet stored them as decimal strings). kvGet
// returns these as ints so the value behaves like the old env* did — toInt()
// wrappers stay valid (toInt(int) is a no-op) and bare numeric uses work too.
func _isNum(k) {
    let nums = "|row|col|scrollRow|scrollCol|dirty|goalCol|atBoundary|rows|cols|running|overlayScroll|pkOpen|pkCursor|"
    if indexOf(nums, "|" + k + "|") >= 0 { emit 1 }
    emit 0
}

func kvGet(e, k) {
    let n = len(e)
    let p = 0
    while p < n {
        let rest = substring(e, p, n)
        let b1 = indexOf(rest, "|")
        if b1 < 0 { emit _kvMiss(k) }
        let klen = toInt(substring(e, p, p + b1))
        let ks = p + b1 + 1
        let key = substring(e, ks, ks + klen)
        let vp = ks + klen
        let rest2 = substring(e, vp, n)
        let b2 = indexOf(rest2, "|")
        if b2 < 0 { emit _kvMiss(k) }
        let vlen = toInt(substring(e, vp, vp + b2))
        let vs = vp + b2 + 1
        let val = substring(e, vs, vs + vlen)
        if key == k {
            if _isNum(k) == 1 { emit toInt(val) }
            emit val
        }
        p = vs + vlen
    }
    emit _kvMiss(k)
}

func _kvMiss(k) {
    if _isNum(k) == 1 { emit 0 }
    emit ""
}
