import Foundation

// MARK: - AddonArchive

/// Reads a zip's central directory, so an addon archive can be checked before
/// anything of it is written: every entry must stay inside the folder it
/// unpacks into, and none may be a link.
enum AddonArchive {
    struct Entry: Equatable {
        let name: String
        let isSymbolicLink: Bool
    }

    enum ReadError: Error {
        case notAZip
        case unsupported
    }

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let centralDirectoryEntrySignature: UInt32 = 0x0201_4B50
    /// The end record is 22 bytes, followed by a comment of at most 65,535.
    private static let endRecordSearchLength = 22 + 65535
    private static let unixHost: UInt16 = 3
    private static let fileTypeMask: UInt32 = 0o170000
    private static let symbolicLinkType: UInt32 = 0o120000

    static func entries(of archive: URL) throws -> [Entry] {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
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
            guard position + 46 <= data.count,
                  Self.uint32(data, at: position) == Self.centralDirectoryEntrySignature
            else { throw ReadError.notAZip }
            let madeBy = Self.uint16(data, at: position + 4)
            let nameLength = Int(Self.uint16(data, at: position + 28))
            let extraLength = Int(Self.uint16(data, at: position + 30))
            let commentLength = Int(Self.uint16(data, at: position + 32))
            let externalAttributes = Self.uint32(data, at: position + 38)
            let nameStart = position + 46
            guard nameStart + nameLength <= data.count,
                  let name = String(bytes: data[nameStart ..< nameStart + nameLength], encoding: .utf8)
            else { throw ReadError.notAZip }
            let mode = externalAttributes >> 16
            let isLink = madeBy >> 8 == Self.unixHost && mode & Self.fileTypeMask == Self.symbolicLinkType
            entries.append(Entry(name: name, isSymbolicLink: isLink))
            position = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Whether unpacking these entries writes only plain files and folders
    /// inside the destination: no links, absolute paths, or `..` steps.
    static func isSafe(_ entries: [Entry]) -> Bool {
        entries.allSatisfy { entry in
            guard !entry.isSymbolicLink, !entry.name.isEmpty,
                  !entry.name.hasPrefix("/"), !entry.name.hasPrefix("\\")
            else { return false }
            let components = entry.name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            return !components.contains("..")
        }
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
