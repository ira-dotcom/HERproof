import XCTest
@testable import HerProofKit

final class FingerprintTests: XCTestCase {
    func testKnownVector() {
        XCTAssertEqual(
            Fingerprint.sha256(of: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testStreamedFileMatchesInMemory() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let bytes = Data((0..<(3 << 20)).map { UInt8($0 % 251) })
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Fingerprint.sha256(ofFileAt: url), Fingerprint.sha256(of: bytes))
    }
}
