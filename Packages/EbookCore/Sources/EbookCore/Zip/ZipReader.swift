import Compression
import Foundation
import Synchronization

/// Minimal ZIP reader: end record, central directory, stored and deflated entries.
///
/// Sizes and CRCs are taken from the central directory, so entries written with a data
/// descriptor (general-purpose flag bit 3) read correctly. ZIP64, encryption and
/// multi-disk archives are refused. Every failure is `ImportError.unreadable`.
public struct ZipReader: Sendable {
    /// Archives with more entries than this are refused (zip-bomb guard).
    static let maxEntryCount = 10_000
    /// Entries declaring a larger uncompressed size are refused (zip-bomb guard).
    static let maxUncompressedSize = 200 * 1024 * 1024

    /// Total uncompressed bytes a reader hands out over its lifetime (zip-bomb guard).
    static let defaultTotalBudget = 1024 * 1024 * 1024

    /// Shared running total of declared uncompressed sizes of the entries read so far.
    private final class Budget: Sendable {
        let limit: Int
        private let state = Mutex((used: 0, exhausted: false))

        init(limit: Int) { self.limit = limit }

        var isExhausted: Bool { state.withLock { $0.exhausted } }

        func spend(_ amount: Int) -> Bool {
            state.withLock { state in
                guard state.used + amount <= limit else {
                    state.exhausted = true
                    return false
                }
                state.used += amount
                return true
            }
        }
    }

    private struct Entry: Sendable {
        var method: UInt16
        var flags: UInt16
        var crc: UInt32
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private let bytes: Data
    private let entries: [String: Entry]
    private let budget: Budget
    /// File paths in central-directory order (directories are omitted).
    public let paths: [String]

    /// `true` once a read was refused because the archive would expand past the total budget.
    public var isBudgetExhausted: Bool { budget.isExhausted }

    public init(data: Data) throws {
        try self.init(data: data, totalBudget: Self.defaultTotalBudget)
    }

    init(data: Data, totalBudget: Int) throws {
        let bytes = Data(data) // re-based so indices start at 0
        let endOffset = try Self.findEndRecord(in: bytes)
        let entryCount = try Self.le16(bytes, endOffset + 10)
        let directorySize = try Self.le32(bytes, endOffset + 12)
        let directoryOffset = try Self.le32(bytes, endOffset + 16)
        guard try Self.le16(bytes, endOffset + 4) == 0, try Self.le16(bytes, endOffset + 6) == 0 else {
            throw Self.failure("Multi-disk ZIP archives are not supported")
        }
        guard entryCount != 0xFFFF, directorySize != 0xFFFF_FFFF, directoryOffset != 0xFFFF_FFFF else {
            throw Self.failure("ZIP64 archives are not supported")
        }
        guard entryCount <= Self.maxEntryCount else { throw Self.failure("Too many entries in archive") }
        guard directoryOffset + directorySize <= endOffset else { throw Self.failure("Corrupt central directory") }

        var entries: [String: Entry] = [:]
        var paths: [String] = []
        var cursor = directoryOffset
        for _ in 0..<entryCount {
            guard try Self.le32(bytes, cursor) == 0x0201_4B50 else { throw Self.failure("Corrupt central directory") }
            let flags = UInt16(try Self.le16(bytes, cursor + 8))
            let method = UInt16(try Self.le16(bytes, cursor + 10))
            let crc = UInt32(try Self.le32(bytes, cursor + 16))
            let compressedSize = try Self.le32(bytes, cursor + 20)
            let uncompressedSize = try Self.le32(bytes, cursor + 24)
            let nameLength = try Self.le16(bytes, cursor + 28)
            let extraLength = try Self.le16(bytes, cursor + 30)
            let commentLength = try Self.le16(bytes, cursor + 32)
            let offset = try Self.le32(bytes, cursor + 42)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= bytes.count else { throw Self.failure("Corrupt central directory") }
            let name = Self.decodeName(bytes[nameStart..<nameStart + nameLength])
            cursor = nameStart + nameLength + extraLength + commentLength
            guard cursor <= endOffset else { throw Self.failure("Corrupt central directory") }

            if name.hasSuffix("/") { continue }
            guard entries[name] == nil else { continue } // first occurrence wins
            entries[name] = Entry(
                method: method, flags: flags, crc: crc,
                compressedSize: compressedSize, uncompressedSize: uncompressedSize,
                localHeaderOffset: offset
            )
            paths.append(name)
        }
        self.bytes = bytes
        self.entries = entries
        self.budget = Budget(limit: totalBudget)
        self.paths = paths
    }

    /// The uncompressed, CRC-verified content of the entry at exactly `path`.
    public func data(for path: String) throws -> Data {
        guard let entry = entries[path] else { throw Self.failure("No such entry: \(path)") }
        guard entry.flags & 1 == 0 else { throw Self.failure("Encrypted entry: \(path)") }
        guard entry.uncompressedSize <= Self.maxUncompressedSize else { throw Self.failure("Entry too large: \(path)") }

        guard budget.spend(entry.uncompressedSize) else { throw Self.failure("Archive expands to too much data") }

        let header = entry.localHeaderOffset
        guard try Self.le32(bytes, header) == 0x0403_4B50 else { throw Self.failure("Corrupt local header: \(path)") }
        let start = header + 30 + (try Self.le16(bytes, header + 26)) + (try Self.le16(bytes, header + 28))
        let end = start + entry.compressedSize
        guard end <= bytes.count else { throw Self.failure("Truncated entry: \(path)") }
        let payload = bytes[start..<end]

        let result: Data
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else { throw Self.failure("Corrupt entry: \(path)") }
            result = Data(payload)
        case 8:
            result = try Self.inflate(payload, expectedSize: entry.uncompressedSize, path: path)
        default:
            throw Self.failure("Unsupported compression method \(entry.method): \(path)")
        }
        guard CRC32.checksum(result) == entry.crc else { throw Self.failure("Checksum mismatch: \(path)") }
        return result
    }

    // MARK: - Helpers

    private static func failure(_ message: String) -> ImportError {
        .unreadable(message)
    }

    /// Raw DEFLATE decode into a buffer of exactly the declared size (plus one byte to detect overflow),
    /// so a lying header can never expand beyond the size limit.
    private static func inflate(_ payload: Data, expectedSize: Int, path: String) throws -> Data {
        if expectedSize == 0 { return Data() }
        guard !payload.isEmpty else { throw failure("Corrupt entry: \(path)") }
        let capacity = expectedSize + 1
        var written = 0
        let output = [UInt8](unsafeUninitializedCapacity: capacity) { buffer, count in
            guard let target = buffer.baseAddress else { count = 0; return }
            written = payload.withUnsafeBytes { source -> Int in
                guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(target, capacity, base, payload.count, nil, COMPRESSION_ZLIB)
            }
            count = written
        }
        guard written == expectedSize else { throw failure("Corrupt entry: \(path)") }
        return Data(output)
    }

    private static func findEndRecord(in bytes: Data) throws -> Int {
        let minimumSize = 22
        guard bytes.count >= minimumSize else { throw failure("Not a ZIP archive") }
        let lowest = max(0, bytes.count - minimumSize - 0xFFFF)
        var offset = bytes.count - minimumSize
        while offset >= lowest {
            if bytes[offset] == 0x50, bytes[offset + 1] == 0x4B, bytes[offset + 2] == 0x05, bytes[offset + 3] == 0x06 {
                return offset
            }
            offset -= 1
        }
        throw failure("Not a ZIP archive")
    }

    private static func decodeName(_ raw: Data) -> String {
        if let utf8 = String(data: raw, encoding: .utf8) { return utf8 }
        return String(raw.map { Character(Unicode.Scalar($0)) })
    }

    private static func le16(_ bytes: Data, _ offset: Int) throws -> Int {
        guard offset >= 0, offset + 2 <= bytes.count else { throw failure("Truncated archive") }
        return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }

    private static func le32(_ bytes: Data, _ offset: Int) throws -> Int {
        try le16(bytes, offset) | le16(bytes, offset + 2) << 16
    }
}
