import CryptoKit
import Foundation

struct Transfer {
    struct Metadata: Decodable {
        let name: String
        let size: Int
        let z: Bool
        let sha256: String
        let k: Int
        let b: Int
        let len: Int

        var isValid: Bool {
            let hash = sha256.utf8
            guard size >= 0, len >= 0, b > 0,
                  k >= len / b + (len % b == 0 ? 0 : 1),
                  z ? len > 0 : len == size,
                  !name.isEmpty, name != ".", name != "..",
                  !name.contains("/"), !name.utf8.contains(0),
                  hash.count == 64 else { return false }
            return hash.allSatisfy {
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }
        }
    }

    struct Progress {
        let name: String?
        let known: Int
        let expected: Int
        let symbols: Int
    }

    enum Failure: LocalizedError {
        case decompression
        case checksum

        var errorDescription: String? {
            switch self {
            case .decompression:
                return "The file could not be decompressed. Scanning has restarted."
            case .checksum:
                return "The file failed verification. Scanning has restarted."
            }
        }
    }

    private struct Symbol {
        var indices: Set<Int>
        var data: Data
    }

    private(set) var sessionID: String?
    private var metadata: Metadata?
    private var seen: Set<Int> = []
    private var symbolCount = 0
    private var buffered: [Symbol] = []
    private var known: [Int: Data] = [:]
    private var pending: [Int: Symbol] = [:]
    private var pendingByBlock: [Int: Set<Int>] = [:]
    private var nextPendingID = 0

    var progress: Progress {
        Progress(name: metadata?.name, known: known.count,
                 expected: metadata?.k ?? 0, symbols: symbolCount)
    }

    @discardableResult
    mutating func receive(_ string: String) -> Bool {
        let parts = string.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count >= 4, parts[0] == "QRT2", !parts[1].isEmpty else { return false }

        let sid = String(parts[1])
        let hash = string.hashValue
        if sessionID == sid, seen.contains(hash) { return false }

        switch parts[2] {
        case "M":
            guard parts.count == 4,
                  let payload = Data(base64Encoded: String(parts[3])),
                  let decoded = try? JSONDecoder().decode(Metadata.self, from: payload),
                  decoded.isValid else { return false }

            beginSession(sid)
            guard metadata == nil else { return false }
            seen.insert(hash)
            metadata = decoded
            let earlySymbols = buffered
            buffered.removeAll()
            symbolCount = 0
            for symbol in earlySymbols where Self.isValid(symbol, for: decoded) {
                symbolCount += 1
                peel(symbol)
            }

        case "D":
            guard parts.count == 5,
                  let data = Data(base64Encoded: String(parts[4])),
                  !data.isEmpty else { return false }
            var indices = Set<Int>()
            for field in parts[3].split(separator: ",", omittingEmptySubsequences: false) {
                guard let index = Int(field), index >= 0,
                      indices.insert(index).inserted else { return false }
            }
            guard !indices.isEmpty else { return false }
            let symbol = Symbol(indices: indices, data: data)
            if sessionID == sid, let metadata, !Self.isValid(symbol, for: metadata) {
                return false
            }

            beginSession(sid)
            seen.insert(hash)
            symbolCount += 1
            if metadata != nil {
                peel(symbol)
            } else {
                buffered.append(symbol)
            }

        default:
            return false
        }
        return true
    }

    private mutating func beginSession(_ sid: String) {
        guard sessionID != sid else { return }
        self = Transfer()
        sessionID = sid
    }

    private static func isValid(_ symbol: Symbol, for metadata: Metadata) -> Bool {
        symbol.data.count == metadata.b && symbol.indices.allSatisfy { $0 < metadata.k }
    }

    private mutating func peel(_ symbol: Symbol) {
        var work = [symbol]
        while var current = work.popLast() {
            for index in current.indices {
                if let block = known[index] {
                    Self.xor(block, into: &current.data)
                    current.indices.remove(index)
                }
            }

            guard let index = current.indices.first else { continue }
            if current.indices.count == 1 {
                known[index] = current.data
                for id in pendingByBlock.removeValue(forKey: index) ?? [] {
                    guard let entry = pending.removeValue(forKey: id) else { continue }
                    for dependency in entry.indices where dependency != index {
                        pendingByBlock[dependency]?.remove(id)
                        if pendingByBlock[dependency]?.isEmpty == true {
                            pendingByBlock.removeValue(forKey: dependency)
                        }
                    }
                    work.append(entry)
                }
            } else {
                let id = nextPendingID
                nextPendingID += 1
                pending[id] = current
                for dependency in current.indices {
                    pendingByBlock[dependency, default: []].insert(id)
                }
            }
        }
    }

    private static func xor(_ source: Data, into destination: inout Data) {
        destination.withUnsafeMutableBytes { (destinationBytes: UnsafeMutableRawBufferPointer) in
            source.withUnsafeBytes { (sourceBytes: UnsafeRawBufferPointer) in
                for offset in sourceBytes.indices {
                    destinationBytes[offset] ^= sourceBytes[offset]
                }
            }
        }
    }

    func completedFile() throws -> (name: String, data: Data)? {
        guard let metadata, known.count == metadata.k else { return nil }
        var data = Data()
        data.reserveCapacity(metadata.len)
        for index in 0..<metadata.k {
            guard let block = known[index] else { return nil }
            data.append(contentsOf: block.prefix(metadata.len - data.count))
        }
        if metadata.z {
            do {
                data = try (data as NSData).decompressed(using: .zlib) as Data
            } catch {
                throw Failure.decompression
            }
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
        guard data.count == metadata.size, digest == metadata.sha256.lowercased() else {
            throw Failure.checksum
        }
        return (metadata.name, data)
    }
}
