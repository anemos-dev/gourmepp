import Compression
import Foundation

nonisolated struct ZIPContainer {
    struct Entry {
        let path: String
        let data: Data
        let shouldCompress: Bool

        init(path: String, data: Data, shouldCompress: Bool = true) {
            self.path = path
            self.data = data
            self.shouldCompress = shouldCompress
        }
    }

    private struct StoredEntry {
        let path: String
        let nameData: Data
        let data: Data
        let compressedData: Data
        let compressionMethod: UInt16
        let checksum: UInt32
        let localHeaderOffset: UInt32
    }

    private struct DirectoryEntry {
        let path: String
        let flags: UInt16
        let compressionMethod: UInt16
        let checksum: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static let maximumEntryCount = 10_000
    private static let maximumUncompressedSize = 1_000_000_000

    static func archive(entries: [Entry]) throws -> Data {
        guard entries.count <= maximumEntryCount else { throw EPUBError.fileTooLarge }

        var output = Data()
        var storedEntries: [StoredEntry] = []
        var seenPaths = Set<String>()
        var totalSize = 0

        for entry in entries {
            let path = try validated(path: entry.path)
            guard seenPaths.insert(path).inserted,
                  let nameData = path.data(using: .utf8),
                  nameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  output.count <= Int(UInt32.max) else {
                throw EPUBError.invalidFile
            }
            totalSize += entry.data.count
            guard totalSize <= maximumUncompressedSize else { throw EPUBError.fileTooLarge }

            let compressed = entry.shouldCompress ? deflated(entry.data) : nil
            let payload = compressed.flatMap { $0.count < entry.data.count ? $0 : nil } ?? entry.data
            let method: UInt16 = payload.count == entry.data.count ? 0 : 8
            let checksum = crc32(entry.data)
            let localOffset = UInt32(output.count)

            output.appendLittleEndian(UInt32(0x04034b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(1 << 11))
            output.appendLittleEndian(method)
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(checksum)
            output.appendLittleEndian(UInt32(payload.count))
            output.appendLittleEndian(UInt32(entry.data.count))
            output.appendLittleEndian(UInt16(nameData.count))
            output.appendLittleEndian(UInt16(0))
            output.append(nameData)
            output.append(payload)

            storedEntries.append(StoredEntry(
                path: path,
                nameData: nameData,
                data: entry.data,
                compressedData: payload,
                compressionMethod: method,
                checksum: checksum,
                localHeaderOffset: localOffset
            ))
        }

        guard output.count <= Int(UInt32.max) else { throw EPUBError.fileTooLarge }
        let centralDirectoryOffset = UInt32(output.count)
        for entry in storedEntries {
            output.appendLittleEndian(UInt32(0x02014b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(1 << 11))
            output.appendLittleEndian(entry.compressionMethod)
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(entry.checksum)
            output.appendLittleEndian(UInt32(entry.compressedData.count))
            output.appendLittleEndian(UInt32(entry.data.count))
            output.appendLittleEndian(UInt16(entry.nameData.count))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt32(0))
            output.appendLittleEndian(entry.localHeaderOffset)
            output.append(entry.nameData)
        }

        guard output.count <= Int(UInt32.max), storedEntries.count <= Int(UInt16.max) else {
            throw EPUBError.fileTooLarge
        }
        let centralDirectorySize = UInt32(output.count) - centralDirectoryOffset
        output.appendLittleEndian(UInt32(0x06054b50))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(storedEntries.count))
        output.appendLittleEndian(UInt16(storedEntries.count))
        output.appendLittleEndian(centralDirectorySize)
        output.appendLittleEndian(centralDirectoryOffset)
        output.appendLittleEndian(UInt16(0))
        return output
    }

    static func contents(of archive: Data) throws -> [String: Data] {
        guard archive.count >= 22, let endOffset = endOfCentralDirectory(in: archive) else {
            throw EPUBError.invalidFile
        }
        let diskNumber: UInt16 = try archive.integer(at: endOffset + 4)
        let directoryDisk: UInt16 = try archive.integer(at: endOffset + 6)
        let entryCount: UInt16 = try archive.integer(at: endOffset + 10)
        let directorySize: UInt32 = try archive.integer(at: endOffset + 12)
        let directoryOffset: UInt32 = try archive.integer(at: endOffset + 16)
        guard diskNumber == 0, directoryDisk == 0,
              Int(entryCount) <= maximumEntryCount,
              Int(directoryOffset) <= archive.count,
              Int(directorySize) <= archive.count - Int(directoryOffset) else {
            throw EPUBError.invalidFile
        }

        var directoryEntries: [DirectoryEntry] = []
        var cursor = Int(directoryOffset)
        var totalSize = 0
        for _ in 0..<Int(entryCount) {
            let signature: UInt32 = try archive.integer(at: cursor)
            guard signature == 0x02014b50 else { throw EPUBError.invalidFile }
            let flags: UInt16 = try archive.integer(at: cursor + 8)
            let method: UInt16 = try archive.integer(at: cursor + 10)
            let checksum: UInt32 = try archive.integer(at: cursor + 16)
            let compressedSize: UInt32 = try archive.integer(at: cursor + 20)
            let uncompressedSize: UInt32 = try archive.integer(at: cursor + 24)
            let nameLength: UInt16 = try archive.integer(at: cursor + 28)
            let extraLength: UInt16 = try archive.integer(at: cursor + 30)
            let commentLength: UInt16 = try archive.integer(at: cursor + 32)
            let localOffset: UInt32 = try archive.integer(at: cursor + 42)
            let headerLength = 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
            guard cursor <= archive.count - headerLength,
                  flags & 1 == 0,
                  method == 0 || method == 8 else {
                throw method == 0 || method == 8 ? EPUBError.invalidFile : EPUBError.unsupportedCompression
            }

            let nameRange = (cursor + 46)..<(cursor + 46 + Int(nameLength))
            guard let rawPath = String(data: archive.subdata(in: nameRange), encoding: .utf8) else {
                throw EPUBError.invalidFile
            }
            let path = try validated(path: rawPath)
            totalSize += Int(uncompressedSize)
            guard totalSize <= maximumUncompressedSize else { throw EPUBError.fileTooLarge }
            directoryEntries.append(DirectoryEntry(
                path: path,
                flags: flags,
                compressionMethod: method,
                checksum: checksum,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localOffset)
            ))
            cursor += headerLength
        }

        var result: [String: Data] = [:]
        for entry in directoryEntries where !entry.path.hasSuffix("/") {
            let localSignature: UInt32 = try archive.integer(at: entry.localHeaderOffset)
            guard localSignature == 0x04034b50 else { throw EPUBError.invalidFile }
            let nameLength: UInt16 = try archive.integer(at: entry.localHeaderOffset + 26)
            let extraLength: UInt16 = try archive.integer(at: entry.localHeaderOffset + 28)
            let payloadOffset = entry.localHeaderOffset + 30 + Int(nameLength) + Int(extraLength)
            guard payloadOffset <= archive.count - entry.compressedSize else { throw EPUBError.invalidFile }
            let compressedData = archive.subdata(in: payloadOffset..<(payloadOffset + entry.compressedSize))
            let data: Data
            switch entry.compressionMethod {
            case 0:
                guard compressedData.count == entry.uncompressedSize else { throw EPUBError.invalidFile }
                data = compressedData
            case 8:
                data = try inflated(compressedData, expectedSize: entry.uncompressedSize)
            default:
                throw EPUBError.unsupportedCompression
            }
            guard crc32(data) == entry.checksum else { throw EPUBError.invalidFile }
            result[entry.path] = data
        }
        return result
    }

    private static func endOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
            if (try? data.integer(at: offset) as UInt32) == 0x06054b50 { return offset }
        }
        return nil
    }

    private static func validated(path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0"),
              !normalized.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw EPUBError.invalidFile
        }
        return normalized
    }

    private static func deflated(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        var capacity = max(64, data.count + data.count / 8 + 64)
        for _ in 0..<3 {
            var destination = Data(count: capacity)
            let encodedSize = destination.withUnsafeMutableBytes { destinationBuffer in
                data.withUnsafeBytes { sourceBuffer in
                    compression_encode_buffer(
                        destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        capacity,
                        sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if encodedSize > 0 {
                destination.count = encodedSize
                return destination
            }
            capacity *= 2
        }
        return nil
    }

    private static func inflated(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw EPUBError.invalidFile }
        if expectedSize == 0 { return Data() }
        var destination = Data(count: expectedSize)
        let decodedSize = destination.withUnsafeMutableBytes { destinationBuffer in
            data.withUnsafeBytes { sourceBuffer in
                compression_decode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedSize == expectedSize else { throw EPUBError.invalidFile }
        return destination
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xffff_ffff
        for byte in data {
            var value = (checksum ^ UInt32(byte)) & 0xff
            for _ in 0..<8 {
                value = value & 1 == 1 ? (value >> 1) ^ 0xedb8_8320 : value >> 1
            }
            checksum = (checksum >> 8) ^ value
        }
        return checksum ^ 0xffff_ffff
    }
}

nonisolated private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    func integer<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset <= count - MemoryLayout<T>.size else { throw EPUBError.invalidFile }
        var value: T = 0
        for index in 0..<MemoryLayout<T>.size {
            value |= T(self[offset + index]) << T(index * 8)
        }
        return value
    }
}
