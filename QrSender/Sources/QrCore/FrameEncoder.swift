import CryptoKit
import Foundation

/// Wire format (v1): `QRT1|<sid>|<idx>|<total>|<base64>`
/// idx 0 = metadata JSON, idx 1..<total = data chunks (zlib/raw-deflate if `z`).
public struct FileMeta: Codable, Equatable {
    public let name: String
    public let size: Int
    public let z: Bool
    public let sha256: String
}

public struct EncodedFile {
    public let sessionID: String
    public let meta: FileMeta
    public let total: Int
    /// Unique frames, indexed by frame idx.
    public let frames: [String]
    /// Play order (frame indices), with metadata interleaved periodically.
    public let playlist: [Int]
}

public enum FrameEncoder {
    public static let prefix = "QRT1"
    public static let metaRepeatInterval = 10

    public static func randomSessionID() -> String {
        String(format: "%08x", UInt32.random(in: .min ... .max))
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func encode(data: Data, name: String, chunkSize: Int, sessionID: String = randomSessionID()) -> EncodedFile {
        var payload = data
        var compressed = false
        if !data.isEmpty, let c = try? (data as NSData).compressed(using: .zlib) as Data, c.count < data.count {
            payload = c
            compressed = true
        }

        let size = max(1, chunkSize)
        let chunks = stride(from: 0, to: payload.count, by: size).map {
            payload.subdata(in: $0 ..< min($0 + size, payload.count))
        }
        let total = chunks.count + 1
        let meta = FileMeta(name: name, size: data.count, z: compressed, sha256: sha256Hex(data))
        let metaJSON = (try? JSONEncoder().encode(meta)) ?? Data()

        func frame(_ idx: Int, _ body: Data) -> String {
            "\(prefix)|\(sessionID)|\(idx)|\(total)|\(body.base64EncodedString())"
        }
        let frames = [frame(0, metaJSON)] + chunks.enumerated().map { frame($0.offset + 1, $0.element) }

        var playlist = [0]
        for idx in 1 ..< total {
            playlist.append(idx)
            if idx % metaRepeatInterval == 0, idx != total - 1 { playlist.append(0) }
        }
        return EncodedFile(sessionID: sessionID, meta: meta, total: total, frames: frames, playlist: playlist)
    }
}

/// Reference receiver logic (mirrors what the iOS app must do).
public final class FrameAssembler {
    public enum Result: Equatable { case incomplete, done(name: String, data: Data), failed(String) }

    public private(set) var sessionID: String?
    public private(set) var total = 0
    public private(set) var meta: FileMeta?
    public private(set) var chunks: [Int: Data] = [:]

    public init() {}

    public var missing: [Int] { total > 1 ? (1 ..< total).filter { chunks[$0] == nil } : [] }

    @discardableResult
    public func ingest(_ text: String) -> Result {
        let parts = text.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == FrameEncoder.prefix,
              let idx = Int(parts[2]), let tot = Int(parts[3]), idx >= 0, idx < tot,
              let body = Data(base64Encoded: String(parts[4])) else { return .incomplete }
        let sid = String(parts[1])
        if sid != sessionID { sessionID = sid; total = tot; meta = nil; chunks = [:] }
        if idx == 0 { meta = try? JSONDecoder().decode(FileMeta.self, from: body) } else { chunks[idx] = body }

        guard let meta, missing.isEmpty else { return .incomplete }
        var joined = Data()
        for i in 1 ..< max(total, 1) { joined.append(chunks[i]!) }
        if meta.z {
            guard let d = try? (joined as NSData).decompressed(using: .zlib) as Data else { return .failed("decompress failed") }
            joined = d
        }
        guard FrameEncoder.sha256Hex(joined) == meta.sha256 else { return .failed("sha256 mismatch") }
        return .done(name: meta.name, data: joined)
    }
}
