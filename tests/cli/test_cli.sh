#!/usr/bin/env bash
# Command-line tests: asmgrep (SIMD and scalar) against GNU grep -F -a.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${ASMGREP_BIN:-$ROOT/build/asmgrep}"
TMP="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0
fail=0

note_fail() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }
note_pass() { pass=$((pass + 1)); }

# compare_search <file> <pattern> [options...]
compare_search() {
    local file=$1 pat=$2
    shift 2
    local rc_want rc_got engine
    if [ -z "$pat" ]; then
        grep -a "$@" -- "$pat" "$file" > "$TMP/want.out"; rc_want=$?
    else
        grep -F -a "$@" -- "$pat" "$file" > "$TMP/want.out"; rc_want=$?
    fi
    for engine in "" "--scalar"; do
        # shellcheck disable=SC2086
        "$BIN" $engine "$@" -- "$pat" "$file" > "$TMP/got.out"; rc_got=$?
        if [ "$rc_want" = "$rc_got" ] && cmp -s "$TMP/want.out" "$TMP/got.out"; then
            note_pass
        else
            note_fail "pattern '$pat' options '$* $engine' on $(basename "$file")"
        fi
    done
}

compare_all() {
    local file=$1 pat=$2
    compare_search "$file" "$pat"
    compare_search "$file" "$pat" -n
    compare_search "$file" "$pat" -c
    compare_search "$file" "$pat" -n -c
}

expect_rc() {
    local want=$1
    shift
    "$@" >/dev/null 2>&1
    local rc=$?
    if [ "$rc" = "$want" ]; then note_pass; else note_fail "expected exit $want, got $rc: $*"; fi
}

# --- fixed cases --------------------------------------------------------------
: > "$TMP/empty"
printf 'x' > "$TMP/onebyte"
printf 'ERROR\n' > "$TMP/begin"
printf 'a\nb\nERROR' > "$TMP/end_nonl"
printf 'a ERROR b ERROR c ERROR\nplain\nERRORERROR\n' > "$TMP/multi"
printf 'aaaaaaaa\naaa\n' > "$TMP/overlap"
printf 'no trailing newline here' > "$TMP/nonl"
printf '\n\n\nx\n\n' > "$TMP/blank"
printf 'bin\000ary ERROR \377\376 data\nsecond\000 ERROR\n' > "$TMP/binary"
printf 'CRLF ERROR\r\nnext\r\n' > "$TMP/crlf"

for f in empty onebyte begin end_nonl multi overlap nonl blank binary crlf; do
    for pat in ERROR a aa aaa x e '' ' ' 'ERRORERROR' 'zzz' 'ary ERROR'; do
        compare_all "$TMP/$f" "$pat"
    done
done

# --- every alignment around SIMD block boundaries -----------------------------
for pad in $(seq 0 70); do
    {
        printf '%*s' "$pad" '' | tr ' ' '.'
        printf 'NEEDLE-12345678901234567890-end\n'
        printf '%*s' "$pad" '' | tr ' ' '-'
        printf 'NEEDLE'
    } > "$TMP/align"
    compare_all "$TMP/align" 'NEEDLE'
    compare_all "$TMP/align" 'NEEDLE-12345678901234567890-end'
    compare_all "$TMP/align" 'N'
done

# pattern lengths 1..40 anchored at the file end
for len in $(seq 1 40); do
    s=$(printf '%*s' 5 '' | tr ' ' 'q')$(printf '%*s' "$len" '' | tr ' ' 'Z')
    printf '%s' "$s" > "$TMP/tail"
    compare_all "$TMP/tail" "$(printf '%*s' "$len" '' | tr ' ' 'Z')"
done

# --- randomized differential ---------------------------------------------------
RANDOM=20240229
alphabets=(ab abc $'a\nb' $'ab\n\n')
for i in $(seq 1 150); do
    alpha=${alphabets[$((RANDOM % 4))]}
    n=$((RANDOM % 120))
    data=""
    for _ in $(seq 1 "$n"); do
        data+="${alpha:$((RANDOM % ${#alpha})):1}"
    done
    printf '%s' "$data" > "$TMP/rnd"
    plen=$((1 + RANDOM % 5))
    pat=""
    for _ in $(seq 1 "$plen"); do pat+="${alpha:$((RANDOM % ${#alpha})):1}"; done
    case "$pat" in *$'\n'*) continue ;; esac
    compare_all "$TMP/rnd" "$pat"
done

# --- larger inputs -------------------------------------------------------------
seq 1 2000000 > "$TMP/big"
compare_all "$TMP/big" '99999'
compare_all "$TMP/big" '1999999'
compare_all "$TMP/big" '2000000'
compare_all "$TMP/big" 'nomatchatall'
yes 'dense ERROR line with filler text' | head -n 300000 > "$TMP/dense"
compare_all "$TMP/dense" 'ERROR'

# --- option handling -----------------------------------------------------------
printf -- '-n flag\nplain\n' > "$TMP/dash"
compare_search "$TMP/dash" '-n'
out=$("$BIN" -nc ERROR "$TMP/multi"); [ "$out" = "$(grep -c -F ERROR "$TMP/multi")" ] && note_pass || note_fail "-nc"
out=$("$BIN" ERROR -n "$TMP/multi"); [ "$out" = "$(grep -n -F ERROR "$TMP/multi")" ] && note_pass || note_fail "options after pattern"
"$BIN" --help | grep -q '^Usage:' && note_pass || note_fail "--help"
"$BIN" --version | grep -q '^asmgrep ' && note_pass || note_fail "--version"

# --- exit codes and diagnostics --------------------------------------------------
expect_rc 0 "$BIN" ERROR "$TMP/begin"
expect_rc 1 "$BIN" zzz "$TMP/begin"
expect_rc 1 "$BIN" -c zzz "$TMP/begin"
expect_rc 2 "$BIN" ERROR "$TMP/does-not-exist"
expect_rc 2 "$BIN" ERROR "$TMP"
expect_rc 2 "$BIN"
expect_rc 2 "$BIN" ERROR
expect_rc 2 "$BIN" -z ERROR "$TMP/begin"
expect_rc 2 "$BIN" --bogus ERROR "$TMP/begin"
expect_rc 2 "$BIN" ERROR "$TMP/begin" extra
expect_rc 2 "$BIN" $'a\nb' "$TMP/begin"
expect_rc 0 "$BIN" --help

msg=$("$BIN" ERROR "$TMP/does-not-exist" 2>&1 >/dev/null)
case "$msg" in *"No such file or directory"*) note_pass ;; *) note_fail "ENOENT message: $msg" ;; esac
msg=$("$BIN" ERROR "$TMP" 2>&1 >/dev/null)
case "$msg" in *"Is a directory"*) note_pass ;; *) note_fail "EISDIR message: $msg" ;; esac

if [ "$(id -u)" != 0 ]; then
    : > "$TMP/locked"; chmod 000 "$TMP/locked"
    msg=$("$BIN" x "$TMP/locked" 2>&1 >/dev/null); rc=$?
    [ "$rc" = 2 ] && case "$msg" in *"Permission denied"*) note_pass ;; *) note_fail "EACCES message" ;; esac
fi

# mapping failure: address space too small for the file
if [ "$(stat -c %s "$TMP/big")" -gt 12000000 ]; then
    msg=$( (ulimit -v 10000; "$BIN" 99999 "$TMP/big") 2>&1 >/dev/null); rc=$?
    if [ "$rc" = 2 ] && case "$msg" in *"Cannot allocate memory"*) true ;; *) false ;; esac; then
        note_pass
    else
        note_fail "mmap failure not reported (rc=$rc msg=$msg)"
    fi
fi

# closed stdout is reported, not ignored
if [ -w /dev/full ]; then
    "$BIN" ERROR "$TMP/dense" > /dev/full 2>/dev/null
    [ $? = 2 ] && note_pass || note_fail "write error exit code"
fi

# no descriptors or mappings survive: repeated runs must keep succeeding
for _ in $(seq 1 200); do "$BIN" -c ERROR "$TMP/multi" >/dev/null || { note_fail "repeated run"; break; }; done
note_pass

echo "CLI tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
