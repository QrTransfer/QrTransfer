import CryptoKit
import Foundation

struct Transfer {
    struct Metadata: Decodable {
        let name: String
        let size: Int
        let z: Bool
        let sha256: String

        var isValid: Bool {
            let hash = sha256.utf8
            return size >= 0 && !name.isEmpty && name != "." && name != ".."
                && !name.contains("/") && !name.utf8.contains(0)
                && hash.count == 64
                && hash.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }

    struct Progress {
        let name: String?
        let received: Int
        let expected: Int
        let missing: [Int]
    }

    enum Failure: LocalizedError {
        case decompression
        case checksum

        var errorDescription: String? {
            switch self {
            case .decompression:
                return "The file could not be decompressed. Scanning has restarted."
            case .checksum:
                return "The file failed SHA-256 verification. Scanning has restarted."
            }
        }
    }

    private(set) var sessionID: String?
    private var total = 1
    private var previous: String?
    private var metadata: Metadata?
    private var chunks: [Int: Data] = [:]

    var progress: Progress {
        let expected = total - 1
        let missing = expected - chunks.count < 20
            ? (1..<total).filter { chunks[$0] == nil }
            : []
        return Progress(name: metadata?.name, received: chunks.count, expected: expected, missing: missing)
    }

    @discardableResult
    mutating func receive(_ string: String) -> Bool {
        guard string != previous else { return false }
        previous = string
        guard string.hasPrefix("QRT1|") else { return false }
        let parts = string.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 5, !parts[1].isEmpty,
              let index = Int(parts[2]), let frameTotal = Int(parts[3]),
              frameTotal > 0, (0..<frameTotal).contains(index) else { return false }

        let sessionChanged = sessionID.map { $0 != parts[1] } ?? true
        if sessionChanged {
            self = Transfer()
            previous = string
            sessionID = String(parts[1])
            total = frameTotal
        }

        guard total == frameTotal else { return false }
        if index == 0 {
            guard metadata == nil,
                  let payload = Data(base64Encoded: String(parts[4])),
                  let decoded = try? JSONDecoder().decode(Metadata.self, from: payload),
                  decoded.isValid else { return sessionChanged }
            metadata = decoded
        } else {
            guard chunks[index] == nil,
                  let chunk = Data(base64Encoded: String(parts[4])) else { return sessionChanged }
            chunks[index] = chunk
        }
        return true
    }

    func completedFile() throws -> (name: String, data: Data)? {
        guard let metadata, chunks.count == total - 1 else { return nil }
        var data = Data()
        for index in 1..<total {
            if let chunk = chunks[index] {
                data.append(chunk)
            }
        }
        if metadata.z {
            do {
                data = try (data as NSData).decompressed(using: .zlib) as Data
            } catch {
                throw Failure.decompression
            }
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
        guard digest == metadata.sha256 else { throw Failure.checksum }
        return (metadata.name, data)
    }
}
