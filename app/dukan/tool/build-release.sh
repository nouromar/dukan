#!/usr/bin/env bash
#
# Build signed release artifacts for TestFlight (iOS) and Play Console (Android).
#
#   tool/build-release.sh           # both iOS + Android
#   tool/build-release.sh ios       # iOS only  -> build/ios/ipa/*.ipa
#   tool/build-release.sh android   # Android only -> app-release.aab
#
# - Auto-increments the build number (the +N in pubspec `version:`), so each
#   upload is unique (TestFlight + Play both reject duplicate build numbers).
#   Commit the pubspec bump together with the release.
# - Injects the hosted Supabase config from dart_defines.json (gitignored) —
#   the same values your test phone uses. Copy dart_defines.example.json first.
# - Android signing comes from android/key.properties (gitignored); without it
#   the build falls back to debug signing and Play will reject it.
#
# macOS bash (uses BSD `sed -i ''`).
set -euo pipefail
cd "$(dirname "$0")/.."   # -> app/dukan

DEFINES="dart_defines.json"
if [ ! -f "$DEFINES" ]; then
  echo "ERROR: $DEFINES is missing. Copy dart_defines.example.json -> $DEFINES and fill in your hosted Supabase URL + anon key." >&2
  exit 1
fi

TARGET="${1:-both}"

# Bump build number: version: X.Y.Z+N  ->  +(N+1)
cur="$(grep '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')"
next=$((cur + 1))
sed -i '' -E "s/^(version: [0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+/\1+${next}/" pubspec.yaml
echo "==> build number: ${cur} -> ${next}  ($(grep '^version:' pubspec.yaml))"

flutter pub get

if [ "$TARGET" = "ios" ] || [ "$TARGET" = "both" ]; then
  echo "==> Building iOS .ipa ..."
  flutter build ipa --release --dart-define-from-file="$DEFINES"
  echo "    iOS:     build/ios/ipa/*.ipa  (upload via Transporter or Xcode Organizer)"
fi

if [ "$TARGET" = "android" ] || [ "$TARGET" = "both" ]; then
  echo "==> Building Android .aab ..."
  flutter build appbundle --release --dart-define-from-file="$DEFINES"
  echo "    Android: build/app/outputs/bundle/release/app-release.aab  (upload to Play Console)"
fi

echo "==> Done. Commit the pubspec build-number bump (+${next}) with this release."
