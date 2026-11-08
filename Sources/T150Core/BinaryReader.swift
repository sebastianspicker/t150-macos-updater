import Foundation

/// Bounds-checked, alignment-independent reads of untrusted files.
struct BinaryReader {
    let bytes: [UInt8]
    init(_ data: Data) { bytes = Array(data) }
    func range(_ offset: Int, _ length: Int) throws -> ArraySlice<UInt8> {
        guard offset >= 0, length >= 0, offset <= bytes.count, length <= bytes.count - offset else {
            throw UpdaterError.invalid("The installer contains a truncated or invalid binary structure.")
        }
        return bytes[offset..<(offset + length)]
    }
    func u16(_ offset: Int) throws -> UInt16 {
        let b = Array(try range(offset, 2))
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }
    func u32(_ offset: Int) throws -> UInt32 {
        let b = Array(try range(offset, 4))
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }
    struct PESection { let rva, size, offset: Int }

    func peSections() throws -> [PESection] {
        guard Array(try range(0, 2)) == [0x4d, 0x5a] else { throw UpdaterError.invalid("Not a Windows installer.") }
        let pe = Int(try u32(0x3c))
        guard Array(try range(pe, 4)) == [0x50, 0x45, 0, 0] else { throw UpdaterError.invalid("Invalid PE signature.") }
        let count = Int(try u16(pe + 6))
        let optional = Int(try u16(pe + 20))
        guard (1...96).contains(count), optional >= 96 else { throw UpdaterError.invalid("Unsupported PE layout.") }
        let start = pe + 24 + optional
        _ = try range(start, count * 40)
        return try (0..<count).map { i in
            let section = start + i * 40
            let size = Int(try u32(section + 16))
            let offset = Int(try u32(section + 20))
            _ = try range(offset, size)
            return PESection(rva: Int(try u32(section + 12)), size: size, offset: offset)
        }
    }
}

/// Parses only the reviewed InstallShield overlay; it never executes PE code.
enum InstallerContainer {
    static func cabinets(from data: Data) throws -> [String: Data] {
        let reader = BinaryReader(data)
        let sections = try reader.peSections()
        guard let overlay = sections.map({ $0.offset + $0.size }).max() else { throw UpdaterError.invalid("Missing installer overlay.") }
        guard try reader.u32(overlay) == 22 else { throw UpdaterError.invalid("Unreviewed installer container format.") }
        var cursor = overlay + 4
        func string() throws -> String {
            var words = [UInt16]()
            while words.count < 4096 {
                let word = try reader.u16(cursor)
                cursor += 2
                if word == 0 { return String(decoding: words, as: UTF16.self) }
                words.append(word)
            }
            throw UpdaterError.invalid("Installer metadata is too long.")
        }
        var seen = Set<String>()
        var result = [String: Data]()
        let wanted: Set<String> = ["data1.cab", "data1.hdr", "data2.cab"]
        for _ in 0..<22 {
            let name = try string()
            _ = try string() // vendor's original path is metadata, never a destination
            _ = try string()
            let sizeText = try string()
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
                  seen.insert(name.lowercased()).inserted,
                  !sizeText.isEmpty, sizeText.utf8.allSatisfy({ (48...57).contains($0) }),
                  let size = Int(sizeText), size <= 128 * 1024 * 1024 else {
                throw UpdaterError.invalid("Unsafe or unsupported installer member.")
            }
            let bytes = try reader.range(cursor, size)
            if wanted.contains(name) { result[name] = Data(bytes) }
            cursor += size
        }
        guard result["data1.cab"] != nil, result["data1.hdr"] != nil else {
            throw UpdaterError.invalid("The installer has no supported firmware cabinet.")
        }
        return result
    }
}
