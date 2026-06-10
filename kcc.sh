#!/usr/bin/env bash

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    SDIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$SDIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# ── Platform detection ─────────────────────────────────────────────
case "$(uname -s 2>/dev/null)" in
    Linux*)  PLATFORM=linux ;;
    Darwin*) PLATFORM=macos ;;
    *)       PLATFORM=windows ;;
esac

if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
    KCC_EXE="$SCRIPT_DIR/kcc"
    KCC_HEADERS="$SCRIPT_DIR/headers"
else
    KCC_EXE="$SCRIPT_DIR/kcc.exe"
    KCC_HEADERS_UNIX="$SCRIPT_DIR/headers"
    KCC_HEADERS="$(echo "$KCC_HEADERS_UNIX" | sed 's|^/\([a-zA-Z]\)/|\1:/|')"
fi

# Find a C compiler. Prefer $CC env var, then gcc, then clang (macOS default).
GCC_EXE="${CC:-}"
if [[ -z "$GCC_EXE" ]]; then GCC_EXE="$(command -v gcc 2>/dev/null)"; fi
if [[ -z "$GCC_EXE" ]]; then GCC_EXE="$(command -v clang 2>/dev/null)"; fi
if [[ -z "$GCC_EXE" ]]; then
    for _try in \
        "/c/TDM-GCC-64/bin/gcc.exe" \
        "/C/TDM-GCC-64/bin/gcc.exe" \
        "C:/TDM-GCC-64/bin/gcc.exe" \
        "/c/mingw64/bin/gcc.exe" \
        "/C/mingw64/bin/gcc.exe" \
        "/c/msys64/mingw64/bin/gcc.exe" \
        "/C/msys64/mingw64/bin/gcc.exe"; do
        if [[ -f "$_try" ]]; then GCC_EXE="$_try"; break; fi
    done
fi
if [[ -z "$GCC_EXE" ]]; then GCC_EXE="gcc"; fi

SRCFILE=""
OUTFILE=""
LIBS="-O2 -lm -w"
IRFLAG=""
NATIVE_MODE=0
LLVM_MODE=0
GCC_MODE=0
GCC_EXPLICIT=0
C_MODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ir)      IRFLAG="--ir"; shift ;;
        --native)  NATIVE_MODE=1; shift ;;
        --llvm)    LLVM_MODE=1; shift ;;
        --gcc)     GCC_MODE=1; GCC_EXPLICIT=1; shift ;;
        --c)       C_MODE=1; shift ;;
        -o)        OUTFILE="$2"; shift 2 ;;
        -l*|-L*|-W*) LIBS="$LIBS $1"; shift ;;
        *)         SRCFILE="$1"; shift ;;
    esac
done

if [[ -z "$SRCFILE" ]]; then
    echo "kcc: no input file" >&2; exit 1
fi

HEADERS_FLAG=""
if [[ -d "$KCC_HEADERS_UNIX" ]]; then
    HEADERS_FLAG="--headers $KCC_HEADERS"
fi

# ── --ir only: emit IR ────────────────────────────────────────────
if [[ -n "$IRFLAG" && -z "$OUTFILE" ]]; then
    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE"
    exit $?
fi

# ── --native pipeline ───────────────────────────────────────────────
if [[ $NATIVE_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
            OUTFILE="${SRCFILE%.k}"
        else
            OUTFILE="${SRCFILE%.k}.exe"
        fi
    fi
    TMPIR="/tmp/_kcc_native_$$.kir"

    if [[ "$PLATFORM" == "macos" ]]; then
        MACHO_DIR="$SCRIPT_DIR/compiler/macos_arm64"
        MACHO_BIN="$MACHO_DIR/macho_host"
        MACHO_SRC="$MACHO_DIR/macho_arm64_self.k"

        if [[ ! -f "$MACHO_BIN" || "$MACHO_SRC" -nt "$MACHO_BIN" ]]; then
            CC_HOST="${CC:-clang}"
            command -v "$CC_HOST" >/dev/null || {
                echo "kcc --native: $CC_HOST not found (need a C compiler once to build the macho host)" >&2
                exit 1
            }
            echo "kcc: building macho host..." >&2
            "$KCC_EXE" "$MACHO_SRC" > /tmp/_kcc_macho_build.c && \
            "$CC_HOST" /tmp/_kcc_macho_build.c -o "$MACHO_BIN" $LIBS && rm -f /tmp/_kcc_macho_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build macho host" >&2; exit 1; fi
        fi

        "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
        if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

        "$MACHO_BIN" --ir "$TMPIR" "$OUTFILE"
        MACHO_RET=$?
        rm -f "$TMPIR"
        if [[ $MACHO_RET -ne 0 ]]; then echo "kcc --native: macho codegen failed" >&2; exit 1; fi
        chmod +x "$OUTFILE"
        exit 0
    fi

    if [[ "$PLATFORM" == "linux" ]]; then
        # Linux: .k → kir → optimize.k → kir' → elf.k → ELF
        LINUX_DIR="$SCRIPT_DIR/compiler/linux_x86"
        ELF_BIN="$LINUX_DIR/elf_host"
        OPT_BIN="$LINUX_DIR/optimize_host"
        ELF_SRC="$LINUX_DIR/elf.k"
        OPT_SRC="$SCRIPT_DIR/compiler/optimize.k"   # shared source

        # Detect arch for prebuilt seed lookup
        case "$(uname -m 2>/dev/null)" in
            x86_64|amd64) _ARCH=x86_64 ;;
            aarch64|arm64) _ARCH=aarch64 ;;
            *) _ARCH=$(uname -m) ;;
        esac
        ELF_SEED="$SCRIPT_DIR/bootstrap/elf_host_${PLATFORM}_${_ARCH}"
        OPT_SEED="$SCRIPT_DIR/bootstrap/optimize_host_${PLATFORM}_${_ARCH}"

        if [[ ! -f "$ELF_BIN" || "$ELF_SRC" -nt "$ELF_BIN" ]]; then
            if [[ -f "$ELF_SEED" && "$ELF_SEED" -nt "$ELF_SRC" ]]; then
                cp "$ELF_SEED" "$ELF_BIN"
                chmod +x "$ELF_BIN"
            else
                if [[ -z "$GCC_EXE" || ! -x "$(command -v "$GCC_EXE" 2>/dev/null)$GCC_EXE" ]] && ! command -v "$GCC_EXE" >/dev/null 2>&1; then
                    echo "kcc --native: no prebuilt elf_host seed for ${PLATFORM}_${_ARCH} and no gcc found" >&2
                    echo "kcc --native: stale elf.k requires rebuild — run on a Linux box with gcc once, see bootstrap/REBUILD_SEED.md" >&2
                    exit 1
                fi
                echo "kcc: rebuilding elf host (one-time gcc bootstrap; goal is to drop this once self-host bug is fixed)..." >&2
                "$KCC_EXE" "$ELF_SRC" > /tmp/_kcc_elf_build.c && \
                "$GCC_EXE" /tmp/_kcc_elf_build.c -o "$ELF_BIN" $LIBS && rm -f /tmp/_kcc_elf_build.c
                if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build elf codegen" >&2; exit 1; fi
            fi
        fi

        if [[ ! -f "$OPT_BIN" || "$OPT_SRC" -nt "$OPT_BIN" ]]; then
            if [[ -f "$OPT_SEED" && "$OPT_SEED" -nt "$OPT_SRC" ]]; then
                cp "$OPT_SEED" "$OPT_BIN"
                chmod +x "$OPT_BIN"
            elif command -v "$GCC_EXE" >/dev/null 2>&1; then
                echo "kcc: rebuilding optimize host (one-time gcc bootstrap)..." >&2
                "$KCC_EXE" "$OPT_SRC" > /tmp/_kcc_opt_build.c && \
                "$GCC_EXE" /tmp/_kcc_opt_build.c -o "$OPT_BIN" $LIBS && rm -f /tmp/_kcc_opt_build.c
            fi
        fi

        # Generate IR
        "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
        if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

        # Optimize (skip silently if host not available)
        if [[ -x "$OPT_BIN" ]]; then
            TMPOPT="/tmp/_kcc_native_opt_$$.kir"
            "$OPT_BIN" "$TMPIR" > "$TMPOPT" 2>/dev/null
            if [[ -s "$TMPOPT" ]]; then
                mv "$TMPOPT" "$TMPIR"
            else
                rm -f "$TMPOPT"
            fi
        fi

        "$ELF_BIN" "$TMPIR" "$OUTFILE"
        ELF_RET=$?
        rm -f "$TMPIR"
        if [[ $ELF_RET -ne 0 ]]; then echo "kcc --native: elf codegen failed" >&2; exit 1; fi
        chmod +x "$OUTFILE"
        exit 0
    fi

    # Windows: PE/COFF backend
    TMPOPT="/tmp/_kcc_native_opt_$$.kir"
    WIN_DIR="$SCRIPT_DIR/compiler/windows_x86"
    OPT_BIN="$WIN_DIR/optimize_host.exe"
    X64_BIN="$WIN_DIR/x64_host.exe"
    X64_SRC="$WIN_DIR/x64.k"
    OPT_SRC="$SCRIPT_DIR/compiler/optimize.k"   # shared source
    OPT_SEED="$SCRIPT_DIR/bootstrap/optimize_host_windows_x86_64.exe"
    X64_SEED="$SCRIPT_DIR/bootstrap/x64_host_windows_x86_64.exe"

    if [[ ! -f "$OPT_BIN" || "$OPT_SRC" -nt "$OPT_BIN" ]]; then
        if [[ -f "$OPT_SEED" && "$OPT_SEED" -nt "$OPT_SRC" ]]; then
            cp "$OPT_SEED" "$OPT_BIN"
        else
            echo "kcc: rebuilding optimize host (one-time gcc bootstrap)..." >&2
            "$KCC_EXE" "$OPT_SRC" > /tmp/_kcc_opt_build.c && \
            "$GCC_EXE" /tmp/_kcc_opt_build.c -o "$OPT_BIN" $LIBS && rm -f /tmp/_kcc_opt_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build optimizer" >&2; exit 1; fi
        fi
    fi
    if [[ ! -f "$X64_BIN" || "$X64_SRC" -nt "$X64_BIN" ]]; then
        if [[ -f "$X64_SEED" && "$X64_SEED" -nt "$X64_SRC" ]]; then
            cp "$X64_SEED" "$X64_BIN"
        else
            echo "kcc: rebuilding x64 host (one-time gcc bootstrap)..." >&2
            "$KCC_EXE" "$X64_SRC" > /tmp/_kcc_x64_build.c && \
            "$GCC_EXE" /tmp/_kcc_x64_build.c -o "$X64_BIN" $LIBS && rm -f /tmp/_kcc_x64_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build x64 codegen" >&2; exit 1; fi
        fi
    fi

    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
    if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

    "$OPT_BIN" "$TMPIR" > "$TMPOPT"
    if [[ $? -ne 0 ]]; then echo "kcc --native: optimizer failed" >&2; rm -f "$TMPIR" "$TMPOPT"; exit 1; fi

    "$X64_BIN" "$TMPOPT" "$OUTFILE"
    X64_RET=$?
    rm -f "$TMPIR" "$TMPOPT"
    if [[ $X64_RET -ne 0 ]]; then echo "kcc --native: x64 codegen failed" >&2; exit 1; fi

    RT_DLL="$SCRIPT_DIR/runtime/krypton_rt.dll"
    OUT_DIR="$(dirname "$OUTFILE")"
    if [[ -f "$RT_DLL" && "$OUT_DIR" != "$(dirname "$RT_DLL")" ]]; then
        cp "$RT_DLL" "$OUT_DIR/krypton_rt.dll" 2>/dev/null || true
        echo "kcc: copied runtime DLL to $OUT_DIR" >&2
    fi
    exit 0
fi

# ── --llvm pipeline: .k → .kir → optimize → llvm IR (.ll) ────────
if [[ $LLVM_MODE -eq 1 ]]; then
    TMPIR="/tmp/_kcc_llvm_$$.kir"
    TMPOPT="/tmp/_kcc_llvm_opt_$$.kir"

    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
    if [[ $? -ne 0 ]]; then echo "kcc --llvm: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

    "$KCC_EXE" "$SCRIPT_DIR/compiler/optimize.k" "$TMPIR" > "$TMPOPT"
    if [[ $? -ne 0 ]]; then echo "kcc --llvm: optimizer failed" >&2; rm -f "$TMPIR" "$TMPOPT"; exit 1; fi

    # Emit LLVM IR
    if [[ -n "$OUTFILE" ]]; then
        "$KCC_EXE" "$SCRIPT_DIR/compiler/llvm.k" "$TMPOPT" > "$OUTFILE"
    else
        "$KCC_EXE" "$SCRIPT_DIR/compiler/llvm.k" "$TMPOPT"
    fi
    RET=$?
    rm -f "$TMPIR" "$TMPOPT"
    exit $RET
fi

# ── --c (legacy): emit C source ──────────────────────────────────
if [[ $C_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        "$KCC_EXE" $HEADERS_FLAG "$SRCFILE"
        exit $?
    else
        "$KCC_EXE" $HEADERS_FLAG "$SRCFILE" > "$OUTFILE"
        exit $?
    fi
fi

# ── Default: produce a native binary ─────────────────────────────
if [[ -z "$OUTFILE" ]]; then
    if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
        OUTFILE="${SRCFILE%.k}"
    else
        OUTFILE="${SRCFILE%.k}.exe"
    fi
fi

if [[ "$GCC_MODE" -ne 1 ]]; then
    if [[ "$PLATFORM" == "macos" ]]; then
        GCC_MODE=1
    else
        NATIVE_MODE=1
        exec "$0" --native -o "$OUTFILE" "$SRCFILE"
    fi
fi

if [[ "$GCC_EXPLICIT" -eq 1 ]]; then
    echo "kcc: warning: --gcc is deprecated; native is the default and goal." >&2
    echo "kcc: see bootstrap/REBUILD_SEED.md for the path to gcc-free." >&2
fi
TMPFILE="${OUTFILE}__kcc_tmp.c"
"$KCC_EXE" $HEADERS_FLAG "$SRCFILE" > "$TMPFILE"
if [[ $? -ne 0 ]]; then
    rm -f "$TMPFILE"
    echo "kcc: Krypton compilation failed" >&2
    exit 1
fi

"$GCC_EXE" "$TMPFILE" -o "$OUTFILE" $LIBS
GCC_RET=$?
rm -f "$TMPFILE"
if [[ $GCC_RET -ne 0 ]]; then echo "kcc: C compilation failed" >&2; exit 1; fi
exit 0
