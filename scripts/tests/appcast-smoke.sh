#!/bin/zsh
# End-to-end check of the release pipeline without touching the real signing key or dist/ releases.
# Generates a throwaway EdDSA key FILE, runs make-dmg.sh as a TEST build with that key's public half
# baked into the app (output goes to dist/test/), then checks that
#   - the appcast is well-formed XML and carries the version, build number, notes and signature,
#   - sign_update --verify accepts the DMG signature in the appcast,
#   - nothing was written to dist/Downer-*.dmg or dist/appcast.xml by this run.
# Signs ad hoc (DOWNER_SIGN_IDENTITY=-, allowed for test builds only) so no certificate or login Keychain item is used.
# Takes a few minutes (a full universal Release build). Cleans up dist/test and the temp key on exit.
set -euo pipefail
setopt null_glob
cd "$(dirname "$0")/../.."

TMP="$(mktemp -d)"
KEYFILE="$TMP/throwaway.key"
trap 'rm -rf "$TMP" dist/test' EXIT

echo "==> Generating a throwaway key file (the Keychain is not used)"
cat > "$TMP/gen.swift" <<'SWIFT'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
swift "$TMP/gen.swift" > "$TMP/keys.txt"
printf '%s' "$(sed -n 1p "$TMP/keys.txt")" > "$KEYFILE"
chmod 600 "$KEYFILE"
PUBLIC_KEY="$(sed -n 2p "$TMP/keys.txt")"

# files that must not change: a real release's artifacts
before="$(ls -l dist/Downer-*.dmg dist/appcast.xml 2>/dev/null || true)"

echo "==> Running make-dmg.sh as a test build"
rm -rf dist/test
DOWNER_SIGN_IDENTITY=- \
SPARKLE_ED_KEY_FILE="$KEYFILE" \
EXTRA_XCODEBUILD_SETTINGS="DOWNER_SU_PUBLIC_ED_KEY=$PUBLIC_KEY" \
  ./scripts/make-dmg.sh

APPCAST="dist/test/appcast.xml"
DMG="$(ls dist/test/Downer-*-UNSIGNED-TEST.dmg)"
fail() { echo "FAIL: $1" >&2; exit 1; }

echo "==> Validating $APPCAST"
xmllint --noout "$APPCAST" || fail "appcast is not well-formed"
grep -q '<sparkle:version>[0-9]' "$APPCAST" || fail "no sparkle:version"
grep -q '<sparkle:shortVersionString>' "$APPCAST" || fail "no sparkle:shortVersionString"
grep -q 'sparkle:edSignature="' "$APPCAST" || fail "no edSignature"
grep -q '<description><!\[CDATA\[' "$APPCAST" || fail "no embedded release notes"
grep -q 'releaseNotesLink' "$APPCAST" && fail "unexpected releaseNotesLink"

echo "==> Verifying the DMG signature with sign_update"
SIGN_UPDATE="$(ls -d ~/Library/Developer/Xcode/DerivedData/Downer-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update | head -n 1)"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$APPCAST")"
"$SIGN_UPDATE" --verify "$DMG" "$SIGNATURE" -f "$KEYFILE" \
  || fail "sign_update --verify rejected the signature"
swift scripts/sparkle/verify-signature.swift "$DMG" "$SIGNATURE" "$PUBLIC_KEY" \
  || fail "verify-signature.swift rejected the signature"

echo "==> Checking that release artifacts were not touched"
after="$(ls -l dist/Downer-*.dmg dist/appcast.xml 2>/dev/null || true)"
[[ "$before" == "$after" ]] || fail "dist/ release files changed"

echo "PASS: appcast is valid, signature verifies, release artifacts untouched"
