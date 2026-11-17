#!/bin/sh
# Format, analyze and test with short output (only failures and a summary),
# so a check doesn't flood an agent's context.
#
#   tool/check.sh          changed files only: format them, analyze, then the
#                          tests that import a changed lib file (plus changed
#                          tests)
#   tool/check.sh full     the same, then the whole test suite
#
# "Changed" = differs from HEAD, plus untracked files. Only changed files are
# formatted (formatting all of lib/ and test/ touches unrelated files).
set -u
cd "$(dirname "$0")/.."
export PATH=/opt/flutter/bin:$PATH
# The tools' "running as root" banner is noise here.
export BOT=true CI=true

changed=$( (git diff --name-only HEAD; git ls-files --others --exclude-standard) \
  | sort -u | grep '\.dart$' | while read -r f; do [ -f "$f" ] && echo "$f"; done)

status=0
if [ -n "$changed" ]; then
  # shellcheck disable=SC2086
  dart format $changed | grep -v '^Formatted [0-9]* files' | sed 's/^/format: /'
fi

if ! out=$(flutter analyze 2>&1); then
  echo "$out" | grep -E '^\s*(error|warning|info) ' | head -40
  echo "ANALYZE: issues found"
  status=1
else
  echo "ANALYZE: ok"
fi

# Prints failing tests (name, expectation, our stack line) and the summary.
run_tests() {
  flutter test -r expanded "$@" 2>&1 | awk '
    /\[E\]$/ { print; fail=1; n=0; next }
    fail && /(Expected|Actual|Which|Error|Exception|test\/[^ ]*\.dart [0-9]+:[0-9]+)/ { print "    " $0; if (++n > 12) fail=0; next }
    /^[0-9:]+ \+[0-9]+.*: (Some tests failed|All tests passed)/ { print; fail=0 }
    /No tests ran|Compilation failed/ { print }
  '
}

tests=$(echo "$changed" | grep '^test/.*_test\.dart$' || true)
for f in $(echo "$changed" | grep '^lib/' || true); do
  rel=${f#lib/}
  tests="$tests
$(grep -rl --include='*_test.dart' -e "package:better_betteruntis/$rel'" -e "/$(basename "$f")'" test 2>/dev/null)"
done
tests=$(echo "$tests" | grep . | sort -u | while read -r t; do [ -f "$t" ] && echo "$t"; done)

if [ -n "$tests" ]; then
  echo "TESTS (affected, $(echo "$tests" | wc -l) files):"
  # shellcheck disable=SC2086
  r=$(run_tests $tests); echo "$r"
  echo "$r" | grep -q 'All tests passed' || status=1
fi

if [ "${1:-}" = full ]; then
  echo "TESTS (full suite):"
  r=$(run_tests); echo "$r"
  echo "$r" | grep -q 'All tests passed' || status=1
fi

[ $status = 0 ] && echo "CHECK: ok" || echo "CHECK: FAILED"
exit $status
