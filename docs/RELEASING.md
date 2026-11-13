# Releasing Downer

How to build, sign and publish a release. This is for the maintainer; to build Downer for yourself, see
[Building from source](../README.md#building-from-source).

## In short

1. Write `docs/release-notes/<version>.md`.
2. Raise `MARKETING_VERSION` and **always** `CURRENT_PROJECT_VERSION` in the Xcode project.
3. Run `./scripts/make-dmg.sh`.
4. Create the GitHub release `v<version>` as a **draft**, upload the three files from `dist/`, then publish it.

The rest of this page explains each part and the one-time setup.

## One-time setup

### The code-signing certificate

macOS remembers privacy grants (Full Disk Access, Files & Folders, the Keychain "Always Allow" for Chrome Safe
Storage) by the app's *designated requirement*. An ad-hoc signature makes that requirement the hash of each build,
so every update would reset the grants. A self-signed certificate makes it "this bundle id and this certificate",
which stays the same for every release signed with it.

1. Run `./scripts/signing/create-identity.sh`. It asks for a backup password, creates a 10-year self-signed Code
   Signing certificate named "Downer Code Signing", writes the backup `~/Downer-Code-Signing-backup.p12` and imports
   the identity into your login Keychain.
   - Nothing needs to be "trusted". `security find-identity -p codesigning` lists it as `CSSMERR_TP_NOT_TRUSTED`,
     which does not stop `codesign` or the app from working.
   - By hand instead: Keychain Access → Certificate Assistant → Create a Certificate…, name `Downer Code Signing`,
     Identity Type **Self Signed Root**, Certificate Type **Code Signing**.
2. Keep the `.p12` backup safe (a password manager or an encrypted disk, never in git). To restore it on another Mac,
   double-click it.
3. Use another identity name with `DOWNER_SIGN_IDENTITY` if you need to.

If the certificate is ever lost, sign with a new one: Sparkle still installs the update (its EdDSA key vouches for it),
but every user's privacy grants reset once. Hardened runtime is not enabled, because it needs library validation,
which requires a Team ID that a self-signed certificate does not have.

### The Sparkle update key

Updates are delivered by [Sparkle](https://sparkle-project.org) and signed with an EdDSA key.

1. Run `generate_keys` from the Sparkle package. After one Xcode build it is at
   `<DerivedData>/Downer-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`. It stores the private key in
   your login Keychain and prints the public key.
2. Put the public key in `DOWNER_SU_PUBLIC_ED_KEY` (the app target's build settings). `make-dmg.sh` refuses to build
   while it is still the placeholder.
3. Back up the private key with `generate_keys -x key-file` and keep it safe. **Without it, installed copies can never
   be updated.**

## Building the release

```bash
./scripts/make-dmg.sh
```

It needs Xcode and Python 3 (the DMG tool is installed into `dist/.venv` the first time). The script:

- builds a universal Release app and signs it with "Downer Code Signing", nested code first, and refuses a release
  whose designated requirement is hash based. The first build may show "codesign wants to use the key": choose
  **Always Allow**.
- checks the build number against the published appcast and refuses one that is not higher. Sparkle compares
  `CURRENT_PROJECT_VERSION`, not the version name, and never downgrades. (`SKIP_BUILD_NUMBER_CHECK=1` turns the
  check off.)
- writes `dist/Downer-<version>.dmg` and its `.sha256`.
- signs the DMG with the Sparkle key (from the Keychain, or from `SPARKLE_ED_KEY_FILE`), checks that signature
  against the app's public key, and writes `dist/appcast.xml` with the release notes from
  `docs/release-notes/<version>.md` embedded. The build stops if that file is missing.

## Publishing

Do it in this order, so installed copies never see a release that is missing its files:

1. Create the release as a draft:
   ```bash
   gh release create v<version> --draft --title "Downer <version>" --notes-file docs/release-notes/<version>.md
   ```
   The tag must be exactly `v<version>`: the download link in the appcast uses it. Tag the merged commit on `main`.
2. Upload `dist/Downer-<version>.dmg`, `dist/Downer-<version>.dmg.sha256` and `dist/appcast.xml` to the draft. Always
   upload all three from the same build; a rebuild changes the signature and the file size.
3. Publish it as **Latest**, not as a pre-release. Installed copies read
   `releases/latest/download/appcast.xml`, which only points at a release that is neither a draft nor a pre-release.

## Testing the pipeline

```bash
./scripts/tests/appcast-smoke.sh
```

This runs the whole pipeline with a throwaway key and an ad-hoc signature, then checks the appcast and its signature.
CI runs it on every pull request. Test builds (made with `ALLOW_PLACEHOLDER_KEY=1`, or with
`EXTRA_XCODEBUILD_SETTINGS="DOWNER_SU_PUBLIC_ED_KEY=<key>"` plus `SPARKLE_ED_KEY_FILE`) always need
`SPARKLE_ED_KEY_FILE`, may sign ad hoc with `DOWNER_SIGN_IDENTITY=-`, and write to `dist/test/` with
`-UNSIGNED-TEST` in the file name. Never upload them.
