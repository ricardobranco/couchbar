#!/bin/zsh
# Builds "Couchbar.app" into build/. Signs with the Apple Development identity of TEAM_ID
# (or SIGN_IDENTITY), falling back to an ad-hoc signature.
set -euo pipefail

cd "${0:A:h}/.."
CONFIGURATION="${CONFIGURATION:-release}"
TEAM_ID="${TEAM_ID:-KB29RSZ4EN}"
APP="build/Couchbar.app"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Couchbar" "$APP/Contents/MacOS/Couchbar"
cp Support/Info.plist "$APP/Contents/Info.plist"
[[ -f Support/AppIcon.icns ]] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

find_identity() {
  security find-identity -v -p codesigning | awk '/Apple Development/ { print $2 }' | while read -r hash; do
    if security find-certificate -a -Z -p | awk -v h="$hash" '
        /^SHA-1 hash:/ { found = ($3 == h) } found { print }' | openssl x509 -noout -subject 2>/dev/null | grep -q "OU=$TEAM_ID"; then
      echo "$hash"
      return
    fi
  done
}

IDENTITY="${SIGN_IDENTITY:-$(find_identity)}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "No Apple Development identity for team $TEAM_ID, signing ad-hoc." >&2
  codesign --force --sign - "$APP"
fi

echo "Built $APP"
