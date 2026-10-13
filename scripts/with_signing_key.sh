#!/usr/bin/env bash
# Unpack the encrypted signing key (key-sign-apk.zip), run a build command
# with release signing active, then ALWAYS delete the unpacked material.
#
# Usage:
#   export KEY_SIGN_PASSWORD='...'   # never store it in a file
#   scripts/with_signing_key.sh flutter build apk --release --split-per-abi
#
# The password lives ONLY in your head (and as the GitHub Actions secret
# KEY_SIGN_PASSWORD). The unpacked keystore + android/key.properties are
# wiped on exit, success or failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${KEY_SIGN_PASSWORD:?Set KEY_SIGN_PASSWORD env var first (never store it in a file)}"
export KEY_SIGN_PASSWORD

ZIP_PATH="$ROOT/key-sign-apk.zip"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pine-signing.XXXXXX")"
KEYPROPS="$ROOT/android/key.properties"

cleanup() {
  rm -rf "$TMP"
  rm -f "$KEYPROPS"
}
trap cleanup EXIT

[ -f "$ZIP_PATH" ] || { echo "error: $ZIP_PATH not found" >&2; exit 1; }

# Extract — 7z when available, otherwise python + pyzipper.
# (Standard unzip cannot read WinZip-AES archives.)
if command -v 7z >/dev/null 2>&1; then
  7z x -y -p"$KEY_SIGN_PASSWORD" -o"$TMP" "$ZIP_PATH" > /dev/null
else
  python3 - "$ZIP_PATH" "$TMP" <<'PY'
import os, sys
import pyzipper

zip_path, out_dir = sys.argv[1], sys.argv[2]
with pyzipper.AESZipFile(zip_path) as z:
    z.setpassword(os.environ["KEY_SIGN_PASSWORD"].encode())
    z.extractall(out_dir)
PY
fi

KS_FILE="$TMP/pine-release.keystore"
[ -f "$KS_FILE" ] || { echo "error: pine-release.keystore not found — wrong password?" >&2; exit 1; }

mkdir -p "$ROOT/android"
{
  echo "storeFile=$KS_FILE"
  echo "storePassword=$KEY_SIGN_PASSWORD"
  echo "keyAlias=pine-wallet"
  echo "keyPassword=$KEY_SIGN_PASSWORD"
} > "$KEYPROPS"

echo ">> release signing active (alias pine-wallet) — material will be wiped on exit"
"$@"
