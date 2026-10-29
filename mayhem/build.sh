#!/usr/bin/env bash
# Builds (1) the sanitized libutf8proc + the upstream OSS-Fuzz harness test/fuzzer.c (libFuzzer and
# standalone reproducer) and (2) the upstream functional tests with normal flags.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE COVERAGE_FLAGS

cd "$SRC"

# build/ is gitignored upstream, so `git clean -ffdX` removes everything here.
mkdir -p build/fuzz build/tests

# 1) sanitized project + harness. The libFuzzer binary needs the *library* coverage-instrumented too
#    (fuzzer-no-link), else libFuzzer only sees the harness's own handful of edges; the standalone
#    reproducer gets an uninstrumented-for-coverage copy so it links without the libFuzzer runtime.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1 -I"$SRC" -DUTF8PROC_STATIC -c utf8proc.c -o build/fuzz/utf8proc.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -I"$SRC" -DUTF8PROC_STATIC -c utf8proc.c -o build/fuzz/utf8proc-standalone.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.c -o build/fuzz/lsan_off.o

$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -I"$SRC" \
    test/fuzzer.c build/fuzz/utf8proc.o build/fuzz/lsan_off.o -o /mayhem/utf8proc_fuzzer
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -I"$SRC" \
    "$STANDALONE_FUZZ_MAIN" test/fuzzer.c build/fuzz/utf8proc-standalone.o build/fuzz/lsan_off.o \
    -o /mayhem/utf8proc_fuzzer-standalone

# 2) upstream test programs, project's normal flags (no sanitizers)
$CC -O2 $COVERAGE_FLAGS -DUTF8PROC_STATIC -I"$SRC" -c utf8proc.c -o build/tests/utf8proc.o
$CC -O2 $COVERAGE_FLAGS -c test/tests.c -o build/tests/tests.o
UNICODE_VERSION="$(sed -n 's/^UNICODE_VERSION=//p' data/Makefile)"
for t in case charwidth custom graphemetest iscase iterate maxdecomposition misc normtest printproperty valid; do
  $CC -O2 $COVERAGE_FLAGS -DUNICODE_VERSION="\"$UNICODE_VERSION\"" -I"$SRC" \
      "test/$t.c" build/tests/tests.o build/tests/utf8proc.o -o "build/tests/$t"
done
