import CryptoKit
import Foundation

// Verify with the app's public key only; validation never needs Keychain access.
struct SignatureCheck: Decodable {
    let path: String
    let signature: String
    let length: Int
}
do {
    guard CommandLine.arguments.count == 3,
          let keyData = Data(base64Encoded: CommandLine.arguments[1]) else {
        throw NSError(domain: "UpdateValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected public key and signature-check JSON file"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let checks = try JSONDecoder().decode([SignatureCheck].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    for check in checks {
        let data = try Data(contentsOf: URL(fileURLWithPath: check.path))
        guard check.length >= 0, check.length <= data.count,
              let signature = Data(base64Encoded: check.signature),
              key.isValidSignature(signature, for: data.prefix(check.length)) else {
            throw NSError(domain: "UpdateValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Ed25519 signature: \(check.path)"])
        }
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
