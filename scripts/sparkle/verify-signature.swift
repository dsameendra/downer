// Usage: swift verify-signature.swift <file> <base64 EdDSA signature> <base64 SUPublicEDKey>
// Exits 0 only when the signature is valid for the file under that public key. make-dmg.sh uses it to
// prove that the key that signed the DMG matches the SUPublicEDKey baked into the app, because an app
// whose key doesn't match can never accept an update again.
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
    let data = FileManager.default.contents(atPath: args[1]),
    let signature = Data(base64Encoded: args[2]),
    let keyBytes = Data(base64Encoded: args[3]),
    let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
else {
    FileHandle.standardError.write(Data("verify-signature: bad arguments or malformed key\n".utf8))
    exit(2)
}
exit(key.isValidSignature(signature, for: data) ? 0 : 1)
