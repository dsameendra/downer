#!/bin/zsh
# Creates the self-signed "Downer Code Signing" certificate that make-dmg.sh signs releases with, imports it into
# your login keychain and writes a password-protected .p12 backup. Run it yourself, ONCE per Mac.
#
#   ./scripts/signing/create-identity.sh [backup-file.p12]      (default: ~/Downer-Code-Signing-backup.p12)
#
# Why: macOS keys privacy grants (Full Disk Access, Files & Folders, Keychain "Always Allow") on the app's designated
# requirement. With a stable certificate that requirement is the same for every release, so grants survive Sparkle updates.
# An ad-hoc signature changes with every build, which resets the grants.
#
# What it does, step by step (each step is printed):
#   1. makes an RSA key and a 10-year self-signed certificate (Code Signing only) in a private temp folder,
#   2. bundles them into a .p12 protected by a password you type, saved as the backup file,
#   3. imports that .p12 into ~/Library/Keychains/login.keychain-db, allowing /usr/bin/codesign to use the key,
#   4. deletes the temp folder.
# No trust step is needed: codesign signs with a certificate that is not marked trusted (verified; see the README).
# Nothing else on the system is touched: no trust settings, no other keychain.
#
# Environment: DOWNER_SIGN_IDENTITY (certificate name, default "Downer Code Signing"),
#              DOWNER_SIGN_KEYCHAIN (default login.keychain-db).
set -euo pipefail

NAME="${DOWNER_SIGN_IDENTITY:-Downer Code Signing}"
KEYCHAIN="${DOWNER_SIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
BACKUP="${1:-$HOME/Downer-Code-Signing-backup.p12}"
# the system LibreSSL writes a .p12 that macOS can import; Homebrew's OpenSSL 3 does not (MAC verification failed)
OPENSSL=/usr/bin/openssl

[[ -x "$OPENSSL" ]] || { echo "error: $OPENSSL not found" >&2; exit 1; }
[[ -f "$KEYCHAIN" ]] || { echo "error: keychain not found: $KEYCHAIN" >&2; exit 1; }

echo "==> Checking for an existing \"$NAME\" identity"
if security find-identity -p codesigning "$KEYCHAIN" | grep -F -q "\"$NAME\""; then
  echo "error: \"$NAME\" already exists in $KEYCHAIN. Creating a second one would change the signature of future" >&2
  echo "releases (and reset privacy grants). Delete it in Keychain Access first only if you really mean to." >&2
  exit 1
fi
[[ ! -e "$BACKUP" ]] || { echo "error: $BACKUP already exists; pass another path." >&2; exit 1; }

echo "==> Choose a password for the backup file (needed to restore the identity on another Mac)"
read -rs "PW?Password: "; echo
read -rs "PW2?Repeat:   "; echo
[[ -n "$PW" && "$PW" == "$PW2" ]] || { echo "error: empty or different passwords" >&2; exit 1; }

TMP="$(mktemp -d)"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

echo "==> 1/4 Generating the key and a 10-year self-signed Code Signing certificate"
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

echo "==> 2/4 Writing the password-protected backup: $BACKUP"
PW="$PW" "$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$BACKUP" -passout env:PW
chmod 600 "$BACKUP"

echo "==> 3/4 Importing it into $KEYCHAIN (codesign may use the key)"
echo "    (the password is passed to 'security import -P', so it is briefly visible to other processes of yours)"
security import "$BACKUP" -k "$KEYCHAIN" -P "$PW" -T /usr/bin/codesign

echo "==> 4/4 Removing the temporary key material"
rm -rf "$TMP"

echo
security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\"" || true
cat <<DONE

Done. "CSSMERR_TP_NOT_TRUSTED" next to the name is expected and harmless for signing.
- Keep $BACKUP somewhere safe (password manager, encrypted disk) and do not commit it.
  Lose the identity and the next release is signed with a different certificate: every user's privacy grants reset once more.
- The first build may show "codesign wants to use the key": click Always Allow.
DONE
