import CryptoKit
import Foundation

/// SHA-256 over the bytes as imported.
///
/// The fingerprint is what lets an attorney say the file in the packet is the
/// file that came off the phone, so it is taken once at import and never
/// recomputed from a resized, re-encoded or stripped copy.
public enum Fingerprint {
    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hash a file without reading all of it into memory, for a long video or a
    /// large export sitting in the Files app.
    public static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
