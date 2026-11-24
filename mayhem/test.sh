#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Known-answer tests for the ctypes builtins, run in the normal-flags bash + ctypes.so that
# mayhem/build.sh left in mayhem/out/test (upstream's own test/*.sh need gdb, network or GTK, so the
# same checks -- struct layouts from test/structs.c, pack/unpack round trips, dlcall -- are asserted
# here against exact expected output).
T="$SRC/mayhem/out/test"
for f in bash ctypes.so structs.so fuzzlib.so; do
  [ -e "$T/$f" ] || { echo "test.sh: missing $T/$f -- run mayhem/build.sh first" >&2; emit_ctrf ctypes-sh-known-answer 0 1; exit 1; }
done
passed=0 failed=0
# check <name> <expected stdout> <script>
check() {
  local name="$1" want="$2" got
  got=$(cd "$T" && "$T/bash" --norc --noprofile -c "enable -f $T/ctypes.so callback dlcall dlclose dlopen dlsym pack unpack struct sizeof || exit 99
$3" 2>&1)
  if [ "$got" == "$want" ]; then passed=$((passed+1)); echo "PASS $name"
  else failed=$((failed+1)); echo "FAIL $name"; echo "  want: $want"; echo "  got:  $got"; fi
}

check sizeof-structs "16 24 48 128 16" \
  'dlopen ./structs.so >/dev/null; echo $(sizeof nested) $(sizeof hasunion) $(sizeof manytypes) $(sizeof hasarray) $(sizeof hasenum)'
check struct-nested "int int int int" \
  'dlopen ./structs.so >/dev/null; struct nested n; echo ${n[a]} ${n[.b]} ${n[.named.c]} ${n[.named..d]}'
check struct-union-default "int|uchar|uchar||" \
  'dlopen ./structs.so >/dev/null; struct hasunion h; echo "${h[a]}|${h[g.b]}|${h[.h]}|${h[g.f]}|${h[.i]}"'
check struct-union-select "double|ushort||" \
  'dlopen ./structs.so >/dev/null; struct -u g:f,:i hasunion h; echo "${h[g.f]}|${h[.i]}|${h[.h]}|${h[g.b]}"'
check struct-anon-typedef "int long 16" \
  'dlopen ./structs.so >/dev/null; struct -a unnamed_t u; echo ${u[a]} ${u[b]} $(sizeof -a unnamed_t)'
check struct-redefine "4 int uchar" \
  'dlopen ./structs.so >/dev/null; struct hasunion h; struct -u g:f,:i hasunion h; struct hasunion h; echo ${#h[@]} ${h[a]} ${h[g.b]}'
check pack-unpack-roundtrip "int:-7 long:1234567890123 uint32:0" \
  'dlopen ./structs.so >/dev/null; struct -a unnamed_t u; sizeof -m p -a unnamed_t; u[a]=int:-7; u[b]=long:1234567890123; u[a.__pad0]=uint32:0
   pack $p u; struct -a unnamed_t w; unpack $p w; echo ${w[a]} ${w[b]} ${w[a.__pad0]}'
check unpack-indexed-array "uint8:1 uint16:770 int:-1" \
  'dlopen ./fuzzlib.so >/dev/null; dlsym -n b buf; a=(uint8:1 uint16:770 int:-1); pack $b a; r=(uint8 uint16 int); unpack $b r; echo ${r[@]}'
check dlcall-strlen "long:5" \
  'dlcall -n r -r long strlen string:hello; echo $r'
check dlcall-abs-fabs "int:42 double:2.500000" \
  'dlopen libm.so.6 >/dev/null; dlcall -n r -r int abs int:-42; dlcall -n d -r double fabs double:-2.5; echo $r $d'
check dlcall-strtol-pointer "long:255 long:-12" \
  'dlcall -n a -r long strtol string:ff pointer:0 int:16; dlcall -n b -r long atol string:-12; echo $a $b'
check callback-qsort "int:1 int:2 int:3 int:5" \
  'dlopen ./fuzzlib.so >/dev/null; dlsym -n b buf
   cmp() { local -a x=(int) y=(int) result; unpack $2 x; unpack $3 y; x=${x##*:}; y=${y##*:}; result=(int:$((x - y))); pack $1 result; }
   a=(int:5 int:2 int:3 int:1); pack $b a; callback -n f cmp int pointer pointer
   dlcall qsort $b long:4 long:4 $f; r=(int int int int); unpack $b r; echo ${r[@]}'

emit_ctrf ctypes-sh-known-answer "$passed" "$failed"
