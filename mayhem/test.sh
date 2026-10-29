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

# Run upstream's own test programs (built by build.sh). A test counts as passed only if it exits 0
# AND prints its success marker, so a neutered binary that exits 0 silently still fails.
T="$SRC/build/tests"
D="$SRC/mayhem/testdata"
passed=0; failed=0

run_test() {  # run_test <name> <expected-output-regex> [args...]
  local name="$1" marker="$2"; shift 2
  [ -x "$T/$name" ] || { echo "FAIL $name: $T/$name missing (build.sh bug)" >&2; failed=$((failed+1)); return; }
  local out rc=0
  out="$("$T/$name" "$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq "$marker"; then
    echo "PASS $name"; passed=$((passed+1))
  else
    echo "FAIL $name (rc=$rc)"; printf '%s\n' "$out" | tail -5; failed=$((failed+1))
  fi
}

run_test case             'utf8proc case conversion tests SUCCEEDED\.'
run_test charwidth        'Character-width tests SUCCEEDED\.'
run_test custom           'map_custom tests SUCCEEDED\.'
run_test iterate          'utf8proc_iterate tests SUCCEEDED, \([0-9]+\) tests passed\.'
run_test maxdecomposition 'SUCCEEDED: maximum decomposed size = [0-9]+ chars'
run_test misc             'Misc tests SUCCEEDED\.'
run_test valid            'Validity tests SUCCEEDED\.'
run_test normtest         'Passed tests after [0-9]+ lines!' "$D/NormalizationTest.txt"
run_test graphemetest     'Passed regression tests!' "$D/GraphemeBreakTest.txt"
run_test iscase           'utf8proc iscase tests SUCCEEDED\.' "$D/Lowercase.txt" "$D/Uppercase.txt"

# Known-answer check on printproperty: exact property dump for U+0041 and U+00E9 (golden file).
if "$T/printproperty" 0x41 0xe9 2>&1 | diff -u "$SRC/mayhem/testdata/printproperty.golden" - ; then
  echo "PASS printproperty golden"; passed=$((passed+1))
else
  echo "FAIL printproperty golden"; failed=$((failed+1))
fi

emit_ctrf "utf8proc-tests" "$passed" "$failed" 0
