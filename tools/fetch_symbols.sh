#!/usr/bin/env bash
# Downloads the APRS symbol sprite sheets used by the app from the upstream
# hessu/aprs-symbols repository (pinned commit, SHA-256 verified).
#
# The images are NOT stored in this repository because most of them have an
# unknown or mixed upstream licence (see assets/symbols/hessu/CREDITS.md).
#
# Usage: tools/fetch_symbols.sh            (run once after cloning)
#        SYMBOLS_DEST=/some/dir tools/fetch_symbols.sh   (override target, used by tests)
set -euo pipefail

COMMIT="f2286a9cd43eb6ba4501250b4c39fff111e3796c"
BASE="https://raw.githubusercontent.com/hessu/aprs-symbols/${COMMIT}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${SYMBOLS_DEST:-${ROOT}/assets/symbols/hessu}"

# name  upstream-path  sha256
FILES=(
  "aprs-symbols-128-0.png|png/aprs-symbols-128-0.png|6458fb4364893f94a032a5a6f4f98850f9b5a78c29943a1971ac58416a64da66"
  "aprs-symbols-128-1.png|png/aprs-symbols-128-1.png|bf0518c70d819fabd8f138841edabbc7be584feb0ef5cb2bf9206f0bc36f7d46"
  "aprs-symbols-128-2.png|png/aprs-symbols-128-2.png|a841ccc807c73667cfc8c988880627ac87b1ef7cdd903715d5a5af8f01f44f4b"
  "COPYRIGHT_UPSTREAM.md|COPYRIGHT.md|203aa7bcc9d7d2e2c4f788e85a08ff8715e9eef2d798f11d105700f6cb0eceed"
)

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for entry in "${FILES[@]}"; do
  IFS='|' read -r name path want <<<"$entry"
  curl -fsSL "${BASE}/${path}" -o "${tmp}/${name}"
  got="$(sha256 "${tmp}/${name}")"
  if [ "$got" != "$want" ]; then
    echo "ERROR: checksum mismatch for ${name}" >&2
    echo "  expected ${want}" >&2
    echo "  got      ${got}" >&2
    exit 1
  fi
  mv "${tmp}/${name}" "${DEST}/${name}"
  echo "ok  ${name}"
done
echo "Symbols installed in ${DEST}"
