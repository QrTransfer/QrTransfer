import CoreImage
import QrCore
import XCTest

final class FountainTests: XCTestCase {
    private func random(_ n: Int) -> Data { Data((0 ..< n).map { _ in UInt8.random(in: 0 ... 255) }) }

    /// Streams frames through a lossy channel until decoded; returns data symbols the decoder received.
    @discardableResult
    private func transfer(_ data: Data, block: Int = 700, loss: Double = 0, seed: UInt64 = 1,
                          file: StaticString = #filePath, line: UInt = #line) -> Int {
        let enc = FountainEncoder(data: data, name: "a.bin", blockSize: block, seed: seed)
        let dec = FountainDecoder()
        var lossRNG = SplitMix64(seed: seed &+ 99)
        for _ in 0 ..< max(200, enc.meta.k * 4) {
            let frame = enc.next()
            if Double.random(in: 0 ..< 1, using: &lossRNG) < loss { continue }
            XCTAssertLessThanOrEqual(frame.utf8.count, 2953, "frame exceeds QR capacity", file: file, line: line)
            switch dec.ingest(frame) {
            case .incomplete: continue
            case let .done(name, out):
                XCTAssertEqual(name, "a.bin", file: file, line: line)
                XCTAssertEqual(out, data, file: file, line: line)
                return dec.received
            case let .failed(reason):
                XCTFail(reason, file: file, line: line); return 0
            }
        }
        XCTFail("did not complete (k=\(enc.meta.k), known=\(dec.known.count))", file: file, line: line)
        return 0
    }

    func testCompressibleAndRandom() {
        transfer(Data(String(repeating: "hello qr ", count: 5000).utf8))
        transfer(random(50000))
    }

    func testEmptyAndTiny() {
        transfer(Data())
        transfer(Data([42]))
        transfer(random(701))
    }

    func testSurvivesHeavyLoss() {
        transfer(random(100_000), loss: 0.4)
    }

    func testOverheadIsModest() {
        let data = random(350_000) // k = 500
        var total = 0
        for seed in 1 ... 5 { total += transfer(data, seed: UInt64(seed)) }
        let overhead = Double(total) / 5 / 500
        print("average symbols / k = \(overhead)")
        XCTAssertLessThan(overhead, 1.3)
    }

    func testMaxBlockFitsQR() {
        let enc = FountainEncoder(data: random(300_000), name: "a-long-file-name.bin", blockSize: 1500)
        for _ in 0 ..< 300 {
            let f = enc.next()
            XCTAssertLessThanOrEqual(f.utf8.count, 2953)
        }
        XCTAssertNotNil(QRRenderer.image(for: enc.next()))
    }

    func testSessionChangeResets() {
        let a = FountainEncoder(data: random(5000), name: "x", blockSize: 500, sessionID: "aaaaaaaa")
        let b = FountainEncoder(data: random(5000), name: "x", blockSize: 500, sessionID: "bbbbbbbb")
        let dec = FountainDecoder()
        for _ in 0 ..< 5 { dec.ingest(a.next()) }
        dec.ingest(b.next())
        XCTAssertEqual(dec.sessionID, "bbbbbbbb")
        XCTAssertNotNil(dec.meta)
        XCTAssertEqual(dec.received, 0)
    }

    /// Mirrors the receiver: split RGB channels to grayscale and decode each QR independently.
    func testColorImageChannelsDecode() throws {
        let enc = FountainEncoder(data: random(20000), name: "c.bin", blockSize: 700)
        let texts = (0 ..< 3).map { _ in enc.next() }
        let image = try XCTUnwrap(QRRenderer.colorImage(texts))
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let source = CIImage(cgImage: cg)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for (channel, expected) in texts.enumerated() {
            let v = CIVector(x: channel == 0 ? 1 : 0, y: channel == 1 ? 1 : 0, z: channel == 2 ? 1 : 0, w: 0)
            let gray = source.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": v, "inputGVector": v, "inputBVector": v,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            let decoded = detector.features(in: gray).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(decoded, [expected], "channel \(channel)")
        }
    }
}
