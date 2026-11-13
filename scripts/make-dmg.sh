#!/bin/zsh
# Builds dist/Downer-<version>.dmg from the current checkout:
#   universal Release build -> signature with the stable "Downer Code Signing" identity -> designed installer window
#   -> Sparkle EdDSA signature -> dist/appcast.xml.
# Needs Xcode and python3. dmgbuild is installed into dist/.venv on first run.
#
# Signing key: sign_update reads the private EdDSA key from the login Keychain (created once with
# Sparkle's generate_keys). Set SPARKLE_ED_KEY_FILE=/path/to/key to use an exported key file instead.
# The build is refused while SUPublicEDKey is still the placeholder.
#
# Code signing: the app and Sparkle's helpers are signed with the self-signed certificate named by
# DOWNER_SIGN_IDENTITY (default "Downer Code Signing"; a 40-character certificate hash also works). Create it once with
# scripts/signing/create-identity.sh (see the README, "Making a release build"). The certificate's hash is part of the app's
# designated requirement, so macOS privacy grants (Full Disk Access, Files & Folders, Keychain "Always Allow") survive
# updates only while every release is signed with the SAME certificate. An ad-hoc signature changes with every build.
# DOWNER_SIGN_KEYCHAIN=/path/to/file.keychain-db makes codesign look in that keychain (used by tests with a temporary one).
# DOWNER_SIGN_IDENTITY=- signs ad hoc; that is only accepted for test builds (see below).
#
# Test builds (never publish these): ALLOW_PLACEHOLDER_KEY=1, or overriding the public key with
#   EXTRA_XCODEBUILD_SETTINGS="DOWNER_SU_PUBLIC_ED_KEY=<base64>" SPARKLE_ED_KEY_FILE=<its private key file>
# write dist/test/Downer-<version>-UNSIGNED-TEST.dmg and dist/test/appcast.xml, never dist/Downer-*.
#
# Release notes come from docs/release-notes/<version>.md (required for a real release).
# Build number guard: the new CFBundleVersion must exceed every sparkle:version in the appcast that is
# currently published; SKIP_BUILD_NUMBER_CHECK=1 turns it off.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="dsameendra/downer"
PLACEHOLDER_KEY="REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
DIST="$PWD/dist"
OUT="$DIST"
TEST_BUILD=0
if [[ "${ALLOW_PLACEHOLDER_KEY:-}" == "1" || "${EXTRA_XCODEBUILD_SETTINGS:-}" == *DOWNER_SU_PUBLIC_ED_KEY=* ]]; then
  TEST_BUILD=1
  OUT="$DIST/test"
fi
if (( TEST_BUILD )) && [[ -z "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  # without a key file sign_update would use the real private key from the login Keychain on a test build
  echo "error: test builds need SPARKLE_ED_KEY_FILE (a throwaway key file); they never use the Keychain key." >&2
  exit 1
fi
# build outside the checkout: folders like ~/Documents get Finder metadata that codesign rejects
BUILD="$(mktemp -d)/build"
IDENTITY="${DOWNER_SIGN_IDENTITY:-Downer Code Signing}"
SIGN_KEYCHAIN="${DOWNER_SIGN_KEYCHAIN:-}"
KC_ARGS=()
[[ -n "$SIGN_KEYCHAIN" ]] && KC_ARGS=(--keychain "$SIGN_KEYCHAIN")

echo "==> Checking the signing identity"
if [[ "$IDENTITY" == "-" ]]; then
  if (( TEST_BUILD )); then
    echo "    ad-hoc signature (test build only)"
  else
    echo "error: DOWNER_SIGN_IDENTITY=- (ad hoc) is only allowed for test builds: an ad-hoc app loses its privacy grants on every update." >&2
    exit 1
  fi
else
  # No -v on purpose: a self-signed certificate that is not marked trusted is listed under "Matching identities"
  # (CSSMERR_TP_NOT_TRUSTED) and codesign signs with it fine. Trust settings are not needed for signing.
  FOUND=$(security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} || true)
  if ! print -r -- "$FOUND" | grep -F -q -e "\"$IDENTITY\"" -e " $IDENTITY \""; then
    echo "error: no code-signing identity named \"$IDENTITY\" was found in your keychains." >&2
    echo "Create it once with ./scripts/signing/create-identity.sh (README, \"Making a release build\")," >&2
    echo "or import your backed-up .p12. To use another identity set DOWNER_SIGN_IDENTITY." >&2
    exit 1
  fi
  echo "    using \"$IDENTITY\""
fi
mkdir -p "$DIST" "$OUT"

echo "==> Building Downer (Release, universal)"
xcodebuild -project Downer.xcodeproj -scheme Downer -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  ${=EXTRA_XCODEBUILD_SETTINGS:-} \
  build | tail -n 3

APP="$BUILD/Build/Products/Release/Downer.app"
PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
VERSION=$(plist CFBundleShortVersionString)
BUILD_NUMBER=$(plist CFBundleVersion)
MIN_OS=$(plist LSMinimumSystemVersion)
[[ "$MIN_OS" == *.*.* ]] || MIN_OS="$MIN_OS.0"   # Sparkle wants major.minor.patch
PUBLIC_KEY=$(plist SUPublicEDKey)
FEED_URL=$(plist SUFeedURL)
DMG_NAME="Downer-$VERSION.dmg"
(( TEST_BUILD )) && DMG_NAME="Downer-$VERSION-UNSIGNED-TEST.dmg"
DMG="$OUT/$DMG_NAME"

echo "==> Checking the update settings"
if [[ "$PUBLIC_KEY" == "$PLACEHOLDER_KEY" || -z "$PUBLIC_KEY" ]]; then
  if [[ "${ALLOW_PLACEHOLDER_KEY:-}" == "1" ]]; then
    echo "WARNING: SUPublicEDKey is the placeholder. This build can't update and must NOT be published."
  else
    echo "error: SUPublicEDKey is still the placeholder (DOWNER_SU_PUBLIC_ED_KEY in Downer.xcodeproj)." >&2
    echo "Generate the key once with Sparkle's generate_keys and paste the public key there." >&2
    exit 1
  fi
fi
echo "    version $VERSION (build $BUILD_NUMBER), feed $FEED_URL"
if (( TEST_BUILD )); then
  echo "################################################################################" >&2
  echo "# TEST BUILD: output goes to $OUT" >&2
  echo "# These files are NOT release artifacts. Never upload them to a GitHub release." >&2
  echo "################################################################################" >&2
fi

echo "==> Checking the build number against the published appcast"
if (( TEST_BUILD )); then
  echo "    skipped for a test build"
elif [[ "${SKIP_BUILD_NUMBER_CHECK:-}" == "1" ]]; then
  echo "    skipped (SKIP_BUILD_NUMBER_CHECK=1)"
else
  PUBLISHED="$(mktemp)"
  HTTP=$(curl -sSL -o "$PUBLISHED" -w '%{http_code}' \
    "https://github.com/$REPO/releases/latest/download/appcast.xml" || echo "000")
  case "$HTTP" in
    200)
      python3 scripts/sparkle/check-build-number.py "$PUBLISHED" "$BUILD_NUMBER" || {
        echo "error: raise CURRENT_PROJECT_VERSION in Downer.xcodeproj (or set SKIP_BUILD_NUMBER_CHECK=1)." >&2
        exit 1
      } ;;
    404)
      echo "    notice: no appcast is published yet (HTTP 404), so there is nothing to compare with." ;;
    *)
      echo "error: could not fetch the published appcast (HTTP $HTTP). Check the network, or set SKIP_BUILD_NUMBER_CHECK=1." >&2
      exit 1 ;;
  esac
  rm -f "$PUBLISHED"
fi

echo "==> Reading the release notes"
NOTES_MD="docs/release-notes/$VERSION.md"
NOTES_HTML=""
if [[ -f "$NOTES_MD" ]]; then
  NOTES_HTML=$(python3 scripts/sparkle/notes-to-html.py "$NOTES_MD")
elif (( TEST_BUILD )); then
  echo "    notice: $NOTES_MD is missing (fine for a test build)"
else
  echo "error: $NOTES_MD is missing. Write the release notes before building a release." >&2
  exit 1
fi

echo "==> Signing with \"$IDENTITY\" (nested code first)"
# Sparkle's documented order (sparkle-project.org/documentation/sandboxing): innermost helpers, then the
# framework, then the app. --deep is avoided so each piece is signed exactly once.
# Hardened runtime (--options runtime) is deliberately NOT enabled: it turns on library validation, which only loads
# frameworks signed by Apple or with the SAME Team ID as the app. A self-signed certificate has no Team ID, so the app
# could not load its own Sparkle.framework. (Notarization would need hardened runtime and a paid Developer ID.)
xattr -cr "$APP"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for nested in \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/Autoupdate" \
  "$SPARKLE/Versions/B/Updater.app" \
  "$SPARKLE"; do
  # a missing piece means Sparkle changed its layout: stop instead of shipping an unsigned helper
  [[ -e "$nested" ]] || { echo "error: expected Sparkle component is missing: $nested" >&2; exit 1; }
  codesign --force --timestamp=none --sign "$IDENTITY" "${KC_ARGS[@]}" "$nested"
done
codesign --force --timestamp=none --sign "$IDENTITY" "${KC_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Designated requirement (what macOS privacy grants are keyed on)"
DR=$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^\(# \)\{0,1\}designated => //p')
echo "    $DR"
[[ -n "$DR" ]] || { echo "error: could not read the designated requirement." >&2; exit 1; }
if [[ "$DR" == *cdhash* ]]; then
  if (( TEST_BUILD )); then
    echo "    notice: cdhash-based requirement (ad hoc); fine for a test build only"
  else
    echo "error: the designated requirement is cdhash-based, so privacy grants would reset on every update." >&2
    exit 1
  fi
fi

echo "==> Drawing the installer background"
swift scripts/dmg/make_background.swift "$DIST"

echo "==> Packaging $DMG"
if [[ ! -x "$DIST/.venv/bin/dmgbuild" ]]; then
  python3 -m venv "$DIST/.venv"
  "$DIST/.venv/bin/pip" install --quiet dmgbuild
fi
rm -f "$DMG"
"$DIST/.venv/bin/dmgbuild" -s scripts/dmg/dmg_settings.py \
  -D app="$APP" \
  -D icon="$APP/Contents/Resources/Downer.icns" \
  -D background="$DIST/background.png" \
  "Downer $VERSION" "$DMG"

hdiutil verify "$DMG" | tail -n 1
( cd "$OUT" && shasum -a 256 "$DMG_NAME" | tee "$DMG_NAME.sha256" )

echo "==> Signing the DMG for Sparkle (EdDSA)"
SIGN_UPDATE="$BUILD/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "$SIGN_UPDATE" ]] || { echo "error: sign_update not found at $SIGN_UPDATE" >&2; exit 1; }
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  SIGNATURE=$("$SIGN_UPDATE" -p -f "$SPARKLE_ED_KEY_FILE" "$DMG")
else
  SIGNATURE=$("$SIGN_UPDATE" -p "$DMG")
fi
LENGTH=$(stat -f%z "$DMG")
[[ -n "$SIGNATURE" && "$LENGTH" -gt 0 ]] || { echo "error: signing failed" >&2; exit 1; }
# the key that signed must be the key baked into the app, or installed copies could never update
if ! swift scripts/sparkle/verify-signature.swift "$DMG" "$SIGNATURE" "$PUBLIC_KEY"; then
  if [[ "$PUBLIC_KEY" == "$PLACEHOLDER_KEY" && "${ALLOW_PLACEHOLDER_KEY:-}" == "1" ]]; then
    echo "WARNING: signature does not match the placeholder key (expected for a test build)."
  else
    echo "error: the signature does not verify against SUPublicEDKey ($PUBLIC_KEY)." >&2
    echo "The private key used for signing is not the pair of the public key in the app." >&2
    exit 1
  fi
fi

echo "==> Writing $OUT/appcast.xml"
PUB_DATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Downer</title>
    <item>
      <title>Downer $VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[
$NOTES_HTML
      ]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$DMG_NAME" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT/appcast.xml"

if (( TEST_BUILD )); then
  echo "==> Done (TEST BUILD). Do NOT upload anything from $OUT."
else
  echo "==> Done. Create the GitHub release v$VERSION as a DRAFT, upload these three files, then publish it:"
fi
echo "    $DMG"
echo "    $DMG.sha256"
echo "    $OUT/appcast.xml"
