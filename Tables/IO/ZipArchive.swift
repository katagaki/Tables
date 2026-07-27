import Compression
import Foundation

enum ZipError: LocalizedError {
    case notAnArchive
    case unsupportedCompression(UInt16)
    case corruptEntry(String)
    case decompressionFailed(String)
    case compressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "This file isn’t a valid Office Open XML package."
        case .unsupportedCompression(let method):
            return "The package uses an unsupported compression method (\(method))."
        case .corruptEntry(let name):
            return "The package entry “\(name)” is damaged."
        case .decompressionFailed(let name):
            return "Couldn’t decompress “\(name)”."
        case .compressionFailed(let name):
            return "Couldn’t compress “\(name)”."
        }
    }
}

/// A minimal ZIP reader and writer covering the subset OOXML packages use:
/// stored and deflated entries, no encryption, no spanning.
enum ZipArchive {

    // MARK: - Reading

    /// Reads every entry into a path-keyed table.
    static func entries(in data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard let directoryStart = locateCentralDirectory(bytes) else { throw ZipError.notAnArchive }

        var result: [String: Data] = [:]
        var offset = directoryStart
        while offset + 46 <= bytes.count, readUInt32(bytes, offset) == 0x0201_4B50 {
            let method = readUInt16(bytes, offset + 10)
            let compressedSize = Int(readUInt32(bytes, offset + 20))
            let uncompressedSize = Int(readUInt32(bytes, offset + 24))
            let nameLength = Int(readUInt16(bytes, offset + 28))
            let extraLength = Int(readUInt16(bytes, offset + 30))
            let commentLength = Int(readUInt16(bytes, offset + 32))
            let localOffset = Int(readUInt32(bytes, offset + 42))

            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.notAnArchive }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)

            if !name.hasSuffix("/") {
                let payload = try extract(
                    bytes, localHeaderOffset: localOffset, method: method,
                    compressedSize: compressedSize, uncompressedSize: uncompressedSize, name: name
                )
                result[name] = payload
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        guard !result.isEmpty else { throw ZipError.notAnArchive }
        return result
    }

    private static func extract(
        _ bytes: [UInt8], localHeaderOffset: Int, method: UInt16,
        compressedSize: Int, uncompressedSize: Int, name: String
    ) throws -> Data {
        guard localHeaderOffset + 30 <= bytes.count,
              readUInt32(bytes, localHeaderOffset) == 0x0403_4B50 else {
            throw ZipError.corruptEntry(name)
        }
        let nameLength = Int(readUInt16(bytes, localHeaderOffset + 26))
        let extraLength = Int(readUInt16(bytes, localHeaderOffset + 28))
        let start = localHeaderOffset + 30 + nameLength + extraLength
        guard start + compressedSize <= bytes.count else { throw ZipError.corruptEntry(name) }
        let payload = Data(bytes[start..<(start + compressedSize)])

        switch method {
        case 0:
            return payload
        case 8:
            guard let inflated = inflate(payload, expectedSize: uncompressedSize) else {
                throw ZipError.decompressionFailed(name)
            }
            return inflated
        default:
            throw ZipError.unsupportedCompression(method)
        }
    }

    /// Scans backwards for the end-of-central-directory record.
    private static func locateCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowerBound = max(0, bytes.count - 22 - 65_535)
        var offset = bytes.count - 22
        while offset >= lowerBound {
            if readUInt32(bytes, offset) == 0x0605_4B50 {
                return Int(readUInt32(bytes, offset + 16))
            }
            offset -= 1
        }
        return nil
    }

    // MARK: - Writing

    /// Builds an archive. Entries are written in the order given, which matters
    /// for OOXML readers that expect `[Content_Types].xml` first.
    static func archive(entries: [(path: String, data: Data)]) throws -> Data {
        var output = Data()
        var directory = Data()
        var count: UInt16 = 0

        for entry in entries {
            let nameBytes = Array(entry.path.utf8)
            let crc = crc32(entry.data)
            let localOffset = UInt32(output.count)

            var payload = entry.data
            var method: UInt16 = 0
            if entry.data.count > 64, let deflated = deflate(entry.data), deflated.count < entry.data.count {
                payload = deflated
                method = 8
            }

            var header = Data()
            header.appendUInt32(0x0403_4B50)
            header.appendUInt16(20)             // version needed
            header.appendUInt16(0)              // flags
            header.appendUInt16(method)
            header.appendUInt16(0)              // modification time
            header.appendUInt16(0x21)           // modification date (1980-01-01)
            header.appendUInt32(crc)
            header.appendUInt32(UInt32(payload.count))
            header.appendUInt32(UInt32(entry.data.count))
            header.appendUInt16(UInt16(nameBytes.count))
            header.appendUInt16(0)              // extra field length
            header.append(contentsOf: nameBytes)
            output.append(header)
            output.append(payload)

            var record = Data()
            record.appendUInt32(0x0201_4B50)
            record.appendUInt16(20)             // version made by
            record.appendUInt16(20)             // version needed
            record.appendUInt16(0)              // flags
            record.appendUInt16(method)
            record.appendUInt16(0)
            record.appendUInt16(0x21)
            record.appendUInt32(crc)
            record.appendUInt32(UInt32(payload.count))
            record.appendUInt32(UInt32(entry.data.count))
            record.appendUInt16(UInt16(nameBytes.count))
            record.appendUInt16(0)              // extra
            record.appendUInt16(0)              // comment
            record.appendUInt16(0)              // disk number
            record.appendUInt16(0)              // internal attributes
            record.appendUInt32(0)              // external attributes
            record.appendUInt32(localOffset)
            record.append(contentsOf: nameBytes)
            directory.append(record)
            count += 1
        }

        let directoryOffset = UInt32(output.count)
        output.append(directory)
        output.appendUInt32(0x0605_4B50)
        output.appendUInt16(0)                  // this disk
        output.appendUInt16(0)                  // disk with central directory
        output.appendUInt16(count)
        output.appendUInt16(count)
        output.appendUInt32(UInt32(directory.count))
        output.appendUInt32(directoryOffset)
        output.appendUInt16(0)                  // comment length
        return output
    }

    // MARK: - DEFLATE

    /// ZIP stores raw DEFLATE streams, which is exactly `COMPRESSION_ZLIB` here.
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return Data() }

        // The central directory usually tells us the exact output size.
        if expectedSize > 0, let exact = decode(data, into: expectedSize), exact.count == expectedSize {
            return exact
        }
        // Otherwise grow the buffer until the output fits with room to spare,
        // which is how we know it wasn't truncated.
        var capacity = max(data.count * 8, 64 * 1024)
        for _ in 0..<8 {
            if let decoded = decode(data, into: capacity), decoded.count < capacity {
                return decoded
            }
            capacity *= 4
        }
        return nil
    }

    private static func decode(_ data: Data, into capacity: Int) -> Data? {
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(destination, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }

    private static func deflate(_ data: Data) -> Data? {
        let capacity = data.count + 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(destination, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }

    // MARK: - CRC-32

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            return value
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Byte access

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
