import Foundation

/// Errors thrown while building a ZIP archive.
public enum ZipError: Error, Sendable, Equatable {
    case compressionFailed(path: String)
    /// Archive would need ZIP64 (more than 65535 entries, or sizes/offsets above 4 GiB).
    case tooLarge
}

/// Minimal deterministic ZIP writer: local headers, central directory, end record.
/// No data descriptors, UTF-8 names (bit 11), fixed DOS timestamp 1980-01-01 00:00.
public enum ZipWriter {
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x0021 // 1980-01-01
    private static let utf8Flag: UInt16 = 1 << 11

    private struct Record {
        var name: Data
        var method: UInt16
        var crc: UInt32
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var offset: UInt32
    }

    public static func archive(_ entries: [ZipEntry]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else { throw ZipError.tooLarge }
        var output = Data()
        var records: [Record] = []

        for entry in entries {
            let (payload, method) = try encode(entry)
            guard payload.count <= Int(UInt32.max),
                  entry.data.count <= Int(UInt32.max),
                  output.count <= Int(UInt32.max) else { throw ZipError.tooLarge }
            let name = Data(entry.path.utf8)
            guard name.count <= Int(UInt16.max) else { throw ZipError.tooLarge }
            let record = Record(
                name: name,
                method: method.rawValue,
                crc: CRC32.checksum(entry.data),
                compressedSize: UInt32(payload.count),
                uncompressedSize: UInt32(entry.data.count),
                offset: UInt32(output.count)
            )
            output.append(le32: 0x0403_4B50)
            output.append(le16: method == .stored ? 10 : 20) // version needed
            output.append(le16: utf8Flag)
            output.append(le16: method.rawValue)
            output.append(le16: dosTime)
            output.append(le16: dosDate)
            output.append(le32: record.crc)
            output.append(le32: record.compressedSize)
            output.append(le32: record.uncompressedSize)
            output.append(le16: UInt16(name.count))
            output.append(le16: 0) // extra length
            output.append(name)
            output.append(payload)
            records.append(record)
        }

        let directoryStart = output.count
        guard directoryStart <= Int(UInt32.max) else { throw ZipError.tooLarge }
        for record in records {
            output.append(le32: 0x0201_4B50)
            output.append(le16: 20) // version made by
            output.append(le16: record.method == ZipEntry.Method.stored.rawValue ? 10 : 20)
            output.append(le16: utf8Flag)
            output.append(le16: record.method)
            output.append(le16: dosTime)
            output.append(le16: dosDate)
            output.append(le32: record.crc)
            output.append(le32: record.compressedSize)
            output.append(le32: record.uncompressedSize)
            output.append(le16: UInt16(record.name.count))
            output.append(le16: 0) // extra length
            output.append(le16: 0) // comment length
            output.append(le16: 0) // disk number start
            output.append(le16: 0) // internal attributes
            output.append(le32: 0) // external attributes
            output.append(le32: record.offset)
            output.append(record.name)
        }
        let directorySize = output.count - directoryStart
        guard output.count <= Int(UInt32.max) else { throw ZipError.tooLarge }

        output.append(le32: 0x0605_4B50)
        output.append(le16: 0) // this disk
        output.append(le16: 0) // directory disk
        output.append(le16: UInt16(records.count))
        output.append(le16: UInt16(records.count))
        output.append(le32: UInt32(directorySize))
        output.append(le32: UInt32(directoryStart))
        output.append(le16: 0) // comment length
        return output
    }

    /// Returns the bytes to store and the method actually used.
    /// Empty data is always stored (raw DEFLATE of nothing is not worth a special case).
    private static func encode(_ entry: ZipEntry) throws -> (Data, ZipEntry.Method) {
        guard entry.method == .deflated, !entry.data.isEmpty else { return (entry.data, .stored) }
        do {
            let compressed = try (entry.data as NSData).compressed(using: .zlib)
            return (compressed as Data, .deflated)
        } catch {
            throw ZipError.compressionFailed(path: entry.path)
        }
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func append(le32 value: UInt32) {
        append(le16: UInt16(truncatingIfNeeded: value))
        append(le16: UInt16(truncatingIfNeeded: value >> 16))
    }
}
