#!/usr/bin/env bash
# UEFITool/mayhem/test.sh — golden-output functional oracle for the FFS/UEFI-volume parser.
#
# UEFITool ships no in-tree unit-test suite for this revision, so this is a KNOWN-ANSWER /
# golden-output harness: it runs the NORMAL-flags UEFIExtract (built by mayhem/build.sh, with
# the project's normal flags — NOT the fuzz sanitizer flags) on a crafted FFSv2 firmware volume
# and asserts the parsed report EXACTLY matches mayhem/test/expected_report.txt.
#
# Why this is an honest PATCH oracle (anti-reward-hacking): the expected report enumerates the
# reconstructed firmware tree — Image/UEFI, Volume/FFSv2, File/Freeform, Section/Raw, Free space,
# with stable sizes, GUIDs and CRC32s. A no-op / exit(0) "patch" to the parser cannot reproduce
# that exact tree, so it FAILS the diff. It asserts parser BEHAVIOUR, not merely exit status.
#
# It does NOT compile — build.sh already produced /mayhem/build-tests/UEFIExtract.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

UEFIEXTRACT="$SRC/build-tests/UEFIExtract"
[ -x "$UEFIEXTRACT" ] || { echo "missing $UEFIEXTRACT — run mayhem/build.sh first" >&2; exit 2; }

SEED="$SRC/mayhem/ffsparser_fuzzer/testsuite/fv_ffs2_file_section.fd"
GOLDEN="$SRC/mayhem/test/expected_report.txt"
[ -f "$SEED" ]   || { echo "missing seed $SEED" >&2; exit 2; }
[ -f "$GOLDEN" ] || { echo "missing golden $GOLDEN" >&2; exit 2; }

WORK="$(mktemp -d)"
cp "$SEED" "$WORK/img.fd"
# UEFIExtract writes <input>.report.txt next to the input when given the `report` action.
"$UEFIEXTRACT" "$WORK/img.fd" report >/dev/null 2>&1 || true
GOT="$WORK/img.fd.report.txt"

passed=0; failed=0
if [ -f "$GOT" ] && diff -u "$GOLDEN" "$GOT" >&2; then
  echo "test.sh: golden report matches" >&2
  passed=1
else
  echo "test.sh: golden report MISMATCH (parser output differs from expected)" >&2
  failed=1
fi
rm -rf "$WORK"

emit_ctrf "uefitool-golden" "$passed" "$failed"
