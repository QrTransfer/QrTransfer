import QrCore
import XCTest

final class FrameEncoderTests: XCTestCase {
    private func roundTrip(_ data: Data, chunk: Int = 700, file: StaticString = #filePath, line: UInt = #line) {
        let enc = FrameEncoder.encode(data: data, name: "a.bin", chunkSize: chunk)
        XCTAssertEqual(enc.frames.count, enc.total, file: file, line: line)
        let asm = FrameAssembler()
        var result = FrameAssembler.Result.incomplete
        // Feed in reverse to prove order independence.
        for f in enc.frames.reversed() { result = asm.ingest(f) }
        XCTAssertEqual(result, .done(name: "a.bin", data: data), file: file, line: line)
    }

    func testRoundTripCompressible() {
        roundTrip(Data(String(repeating: "hello qr ", count: 5000).utf8))
    }

    func testRoundTripRandomNotCompressed() {
        let data = Data((0 ..< 20000).map { _ in UInt8.random(in: 0 ... 255) })
        let enc = FrameEncoder.encode(data: data, name: "r", chunkSize: 700)
        XCTAssertFalse(enc.meta.z)
        XCTAssertEqual(enc.total, 1 + Int((20000.0 / 700).rounded(.up)))
        roundTrip(data)
    }

    func testEmptyAndTiny() {
        roundTrip(Data())
        roundTrip(Data([42]))
    }

    func testPlaylistInterleavesMeta() {
        let data = Data((0 ..< 10000).map { _ in UInt8.random(in: 0 ... 255) })
        let enc = FrameEncoder.encode(data: data, name: "r", chunkSize: 200)
        XCTAssertEqual(enc.playlist.first, 0)
        XCTAssertGreaterThan(enc.playlist.filter { $0 == 0 }.count, 1)
        XCTAssertEqual(Set(enc.playlist), Set(0 ..< enc.total))
    }

    func testSessionChangeResets() {
        let data = Data((0 ..< 3000).map { _ in UInt8.random(in: 0 ... 255) })
        let a = FrameEncoder.encode(data: data, name: "x", chunkSize: 500, sessionID: "aaaaaaaa")
        let b = FrameEncoder.encode(data: data, name: "x", chunkSize: 500, sessionID: "bbbbbbbb")
        let asm = FrameAssembler()
        a.frames.dropLast().forEach { asm.ingest($0) }
        asm.ingest(b.frames[1])
        XCTAssertEqual(asm.sessionID, "bbbbbbbb")
        XCTAssertEqual(asm.chunks.count, 1)
    }

    func testMaxChunkFitsQR() {
        let data = Data((0 ..< 3000).map { _ in UInt8.random(in: 0 ... 255) })
        let enc = FrameEncoder.encode(data: data, name: "a-long-file-name.bin", chunkSize: 1500)
        for f in enc.frames {
            XCTAssertLessThanOrEqual(f.utf8.count, 2953)
            XCTAssertNotNil(QRRenderer.image(for: f))
        }
    }
}
