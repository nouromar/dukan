#!/usr/bin/env bash
#
# Fast/targeted test helper for the Dukan Flutter app.
#
# The full `flutter test` suite (~85 files, ~50 of them widget tests
# that pump screens and pumpAndSettle) is the slow part of the inner
# loop. Use this during development; run the full suite before committing.
#
#   tool/test.sh            # FAST: unit tests only (files with no testWidgets)
#   tool/test.sh full       # the whole suite (pre-commit gate)
#   tool/test.sh test/sync  # targeted: any path(s) you pass through to flutter test
#
# It also refuses to start if another `flutter test` is already running
# — two concurrent runs share build/ + .dart_tool/ and corrupt each
# other, producing phantom "_pendingExceptionDetails" failures.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # -> app/dukan

if pgrep -f flutter_tester >/dev/null 2>&1; then
  echo "A 'flutter test' run is already in progress." >&2
  echo "Wait for it to finish — concurrent runs corrupt the shared build cache." >&2
  exit 1
fi

mode="${1:-fast}"

case "$mode" in
  fast)
    # Unit tests = every *_test.dart that does NOT pump widgets.
    # `grep -L` lists the files missing the pattern; widget/screen tests
    # (the slow ones) are skipped automatically as they're added.
    # (Word-split is safe — test paths contain no spaces. Stay
    # compatible with macOS's stock bash 3.2, which lacks `mapfile`.)
    files=$(grep -rL "testWidgets(" test --include='*_test.dart' | sort)
    if [ -z "$files" ]; then
      echo "No unit-only test files found."
      exit 0
    fi
    echo "Fast loop — $(printf '%s\n' "$files" | wc -l | tr -d ' ') unit test file(s):"
    # shellcheck disable=SC2086
    exec flutter test -r compact $files
    ;;
  full)
    exec flutter test -r compact
    ;;
  *)
    # Anything else: treat the args as paths/flags for flutter test.
    exec flutter test -r compact "$@"
    ;;
esac
