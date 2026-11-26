import Compression
import Foundation

// MARK: - AddonArchive

/// Unpacks an addon's zip itself, so that what is checked is what gets
/// written: entries come from the central directory, each must match its
/// local header, stay inside the destination, and be a plain file or
/// folder, and only those entries are written.
enum AddonArchive {
    struct Entry: Equatable {
        let name: String
        let isSymbolicLink: Bool
        var method: UInt16 = 0
        var flags: UInt16 = 0
        var compressedSize = 0
        var uncompressedSize = 0
        var localHeaderOffset = 0
    }

    enum ReadError: Error {
        case notAZip
        case unsupported
        case unsafe
    }

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let centralDirectoryEntrySignature: UInt32 = 0x0201_4B50
    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    /// The end record is 22 bytes, followed by a comment of at most 65,535.
    private static let endRecordSearchLength = 22 + 65535
    private static let fileTypeMask: UInt32 = 0o170000
    private static let symbolicLinkType: UInt32 = 0o120000
    private static let stored: UInt16 = 0
    private static let deflated: UInt16 = 8
    /// Addons unpack to a few tens of megabytes; this stops a zip bomb.
    static let maximumUnpackedSize = 256 * 1024 * 1024

    static func entries(of archive: URL) throws -> [Entry] {
        try self.entries(in: Data(contentsOf: archive, options: .mappedIfSafe))
    }

    static func entries(in data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ReadError.notAZip }
        var endRecord: Int?
        var offset = data.count - 22
        let searchStart = max(0, data.count - Self.endRecordSearchLength)
        while offset >= searchStart {
            if Self.uint32(data, at: offset) == Self.endOfCentralDirectorySignature {
                endRecord = offset
                break
            }
            offset -= 1
        }
        guard let endRecord else { throw ReadError.notAZip }

        let count = Int(Self.uint16(data, at: endRecord + 10))
        let directoryOffset = Int(Self.uint32(data, at: endRecord + 16))
        // ZIP64 archives mark these fields as overflowing; addons are small.
        guard count != 0xFFFF, directoryOffset != 0xFFFF_FFFF else { throw ReadError.unsupported }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var position = directoryOffset
        for _ in 0 ..< count {
            guard position + 46 <= endRecord,
                  Self.uint32(data, at: position) == Self.centralDirectoryEntrySignature
            else { throw ReadError.notAZip }
            let nameLength = Int(Self.uint16(data, at: position + 28))
            let extraLength = Int(Self.uint16(data, at: position + 30))
            let commentLength = Int(Self.uint16(data, at: position + 32))
            let nameStart = position + 46
            guard nameStart + nameLength <= endRecord,
                  let name = String(bytes: data[data.startIndex + nameStart ..< data.startIndex + nameStart + nameLength], encoding: .utf8)
            else { throw ReadError.notAZip }
            let mode = Self.uint32(data, at: position + 38) >> 16
            entries.append(Entry(
                name: name,
                isSymbolicLink: mode & Self.fileTypeMask == Self.symbolicLinkType,
                method: Self.uint16(data, at: position + 10),
                flags: Self.uint16(data, at: position + 8),
                compressedSize: Int(Self.uint32(data, at: position + 20)),
                uncompressedSize: Int(Self.uint32(data, at: position + 24)),
                localHeaderOffset: Int(Self.uint32(data, at: position + 42))
            ))
            position = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Whether every entry is a plain file or folder inside the destination:
    /// no links, absolute paths, or `..` steps, and at least one entry.
    static func isSafe(_ entries: [Entry]) -> Bool {
        !entries.isEmpty && entries.allSatisfy { entry in
            guard !entry.isSymbolicLink, !entry.name.isEmpty,
                  !entry.name.hasPrefix("/"), !entry.name.hasPrefix("\\")
            else { return false }
            let components = entry.name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            return !components.contains("..")
        }
    }

    /// Writes the archive's entries into `destination`, which must exist.
    static func extract(_ archive: URL, to destination: URL) throws {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let entries = try self.entries(in: data)
        guard self.isSafe(entries) else { throw ReadError.unsafe }
        let root = destination.standardizedFileURL.path
        var unpackedSize = 0

        for entry in entries {
            let target = destination.appendingPathComponent(entry.name).standardizedFileURL
            guard target.path.hasPrefix(root + "/") else { throw ReadError.unsafe }
            let content = try self.content(of: entry, in: data)
            unpackedSize += content.count
            guard unpackedSize <= self.maximumUnpackedSize else { throw ReadError.unsupported }
            if entry.name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try content.write(to: target, options: .withoutOverwriting)
            }
        }
    }

    /// The entry's bytes, read where its local header says, after checking
    /// that the header names the same entry.
    private static func content(of entry: Entry, in data: Data) throws -> Data {
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, Self.uint32(data, at: header) == Self.localHeaderSignature else {
            throw ReadError.notAZip
        }
        let nameLength = Int(Self.uint16(data, at: header + 26))
        let extraLength = Int(Self.uint16(data, at: header + 28))
        let nameStart = header + 30
        guard nameStart + nameLength <= data.count,
              String(bytes: data[data.startIndex + nameStart ..< data.startIndex + nameStart + nameLength], encoding: .utf8) == entry.name
        else { throw ReadError.unsafe }
        // Encrypted entries can't be read; anything but stored or deflated
        // isn't something a browser extension build uses.
        guard entry.flags & 1 == 0, entry.method == Self.stored || entry.method == Self.deflated else {
            throw ReadError.unsupported
        }
        let dataStart = nameStart + nameLength + extraLength
        guard dataStart + entry.compressedSize <= data.count else { throw ReadError.notAZip }
        let compressed = data[data.startIndex + dataStart ..< data.startIndex + dataStart + entry.compressedSize]

        if entry.method == Self.stored {
            guard entry.compressedSize == entry.uncompressedSize else { throw ReadError.notAZip }
            return Data(compressed)
        }
        guard entry.uncompressedSize > 0 else { return Data() }
        guard entry.uncompressedSize <= self.maximumUnpackedSize else { throw ReadError.unsupported }
        var output = Data(count: entry.uncompressedSize)
        let written = output.withUnsafeMutableBytes { outputBuffer in
            compressed.withUnsafeBytes { inputBuffer -> Int in
                guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let inputBase = inputBuffer.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE, as zip stores it.
                return compression_decode_buffer(
                    outputBase, entry.uncompressedSize, inputBase, entry.compressedSize, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == entry.uncompressedSize else { throw ReadError.notAZip }
        return output
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        let start = data.startIndex + offset
        return UInt16(data[start]) | UInt16(data[start + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start]) | UInt32(data[start + 1]) << 8
            | UInt32(data[start + 2]) << 16 | UInt32(data[start + 3]) << 24
    }
}
