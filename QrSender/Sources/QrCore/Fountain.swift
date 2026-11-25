import CryptoKit
import Foundation

/// Wire format (v2, LT fountain code):
///   `QRT2|<sid>|M|<base64 JSON FileMeta>`         metadata
///   `QRT2|<sid>|D|<i1,i2,...>|<base64 block>`     XOR of source blocks i1, i2, ... (0-based)
public struct FileMeta: Codable, Equatable {
    public let name: String
    public let size: Int
    public let z: Bool
    public let sha256: String
    /// Number of source blocks.
    public let k: Int
    /// Block size in bytes (last block zero-padded).
    public let b: Int
    /// Payload length before padding (after optional compression).
    public let len: Int
}

public enum Fountain {
    public static let prefix = "QRT2"
    /// Caps the index list so every frame fits in one QR code.
    public static let maxDegree = 100

    public static func randomSessionID() -> String {
        String(format: "%08x", UInt32.random(in: .min ... .max))
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Robust soliton distribution (c = 0.03, delta = 0.5) as a CDF over degrees 1...min(k, maxDegree).
    static func robustSolitonCDF(k: Int, c: Double = 0.03, delta: Double = 0.5) -> [Double] {
        guard k > 0 else { return [] }
        let kk = Double(k)
        let r = c * log(kk / delta) * kk.squareRoot()
        let maxD = min(k, maxDegree)
        let pivot = max(1, min(maxD, Int(kk / r)))
        let weights = (1 ... maxD).map { d -> Double in
            let rho = d == 1 ? 1 / kk : 1 / (Double(d) * Double(d - 1))
            let tau = d < pivot ? r / (Double(d) * kk) : d == pivot ? r * log(r / delta) / kk : 0
            return rho + max(0, tau)
        }
        let total = weights.reduce(0, +)
        var acc = 0.0
        return weights.map { acc += $0 / total; return acc }
    }
}

public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Data {
    mutating func xor(with other: Data) {
        withUnsafeMutableBytes { dst in
            other.withUnsafeBytes { src in
                for i in 0 ..< Swift.min(dst.count, src.count) { dst[i] ^= src[i] }
            }
        }
    }
}

/// Produces an endless stream of frames; the metadata frame is interleaved every `metaInterval`.
public final class FountainEncoder {
    public static let metaInterval = 10

    public let sessionID: String
    public let meta: FileMeta
    public let metaFrame: String
    public private(set) var emitted = 0

    private let blocks: [Data]
    private let cdf: [Double]
    private var rng: SplitMix64

    public init(data: Data, name: String, blockSize: Int,
                sessionID: String = Fountain.randomSessionID(), seed: UInt64 = .random(in: .min ... .max)) {
        var payload = data
        var compressed = false
        if !data.isEmpty, let c = try? (data as NSData).compressed(using: .zlib) as Data, c.count < data.count {
            payload = c
            compressed = true
        }
        let b = max(1, blockSize)
        let k = (payload.count + b - 1) / b
        blocks = (0 ..< k).map { i in
            var block = payload.subdata(in: i * b ..< min((i + 1) * b, payload.count))
            if block.count < b { block.append(Data(count: b - block.count)) }
            return block
        }
        self.sessionID = sessionID
        meta = FileMeta(name: name, size: data.count, z: compressed, sha256: Fountain.sha256Hex(data),
                        k: k, b: b, len: payload.count)
        let json = (try? JSONEncoder().encode(meta)) ?? Data()
        metaFrame = "\(Fountain.prefix)|\(sessionID)|M|\(json.base64EncodedString())"
        cdf = Fountain.robustSolitonCDF(k: k)
        rng = SplitMix64(seed: seed)
    }

    public func next() -> String {
        defer { emitted += 1 }
        if blocks.isEmpty || emitted % Self.metaInterval == 0 { return metaFrame }
        return symbol(indices: randomIndices())
    }

    public func symbol(indices: [Int]) -> String {
        var out = blocks[indices[0]]
        for i in indices.dropFirst() { out.xor(with: blocks[i]) }
        let list = indices.map(String.init).joined(separator: ",")
        return "\(Fountain.prefix)|\(sessionID)|D|\(list)|\(out.base64EncodedString())"
    }

    private func randomIndices() -> [Int] {
        let u = Double.random(in: 0 ..< 1, using: &rng)
        let degree = (cdf.firstIndex { u < $0 } ?? cdf.count - 1) + 1
        var picked = Set<Int>()
        while picked.count < degree { picked.insert(Int.random(in: 0 ..< blocks.count, using: &rng)) }
        return picked.sorted()
    }
}

/// Reference receiver (LT peeling decoder) — mirrors what the iOS app must do.
public final class FountainDecoder {
    public enum Result: Equatable { case incomplete, done(name: String, data: Data), failed(String) }

    public private(set) var sessionID: String?
    public private(set) var meta: FileMeta?
    public private(set) var known: [Int: Data] = [:]
    public private(set) var received = 0
    private var pending: [(Set<Int>, Data)] = []
    private var seen = Set<Int>()

    public init() {}

    @discardableResult
    public func ingest(_ text: String) -> Result {
        let parts = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, parts[0] == Fountain.prefix else { return .incomplete }
        if parts[1] != sessionID {
            sessionID = parts[1]
            meta = nil; known = [:]; pending = []; seen = []; received = 0
        }
        guard seen.insert(text.hashValue).inserted else { return .incomplete }

        switch parts[2] {
        case "M" where parts.count == 4:
            guard let json = Data(base64Encoded: parts[3]) else { return .incomplete }
            meta = try? JSONDecoder().decode(FileMeta.self, from: json)
        case "D" where parts.count == 5:
            let indices = Set(parts[3].split(separator: ",").compactMap { Int($0) })
            guard !indices.isEmpty, let body = Data(base64Encoded: parts[4]) else { return .incomplete }
            received += 1
            add(indices, body)
        default:
            return .incomplete
        }
        return finish()
    }

    private func add(_ indices: Set<Int>, _ body: Data) {
        var queue = [(indices, body)]
        while let (set, data) = queue.popLast() {
            var set = set, data = data
            for i in set { if let block = known[i] { data.xor(with: block); set.remove(i) } }
            if set.count > 1 { pending.append((set, data)); continue }
            guard let solved = set.first else { continue }
            known[solved] = data
            var rest: [(Set<Int>, Data)] = []
            for entry in pending { if entry.0.contains(solved) { queue.append(entry) } else { rest.append(entry) } }
            pending = rest
        }
    }

    private func finish() -> Result {
        guard let meta, (0 ..< meta.k).allSatisfy({ known[$0] != nil }) else { return .incomplete }
        var joined = Data(capacity: meta.k * meta.b)
        for i in 0 ..< meta.k { joined.append(known[i]!) }
        joined = Data(joined.prefix(meta.len))
        if meta.z {
            guard let d = try? (joined as NSData).decompressed(using: .zlib) as Data else { return .failed("decompress failed") }
            joined = d
        }
        guard Fountain.sha256Hex(joined) == meta.sha256 else { return .failed("sha256 mismatch") }
        return .done(name: meta.name, data: joined)
    }
}
