import Foundation

/// Port of the reviewed LPC11 transformation. The lookup data is read from the
/// user's exact official driver; no vendor code or firmware is distributed.
enum FirmwareDecoder {
    // One reviewed transform with hash-pinned output; splitting it would only move lines.
    // swiftlint:disable:next function_body_length
    static func decode(wrapped: Data, driver: Data, profile: FirmwareProfile) throws -> Data {
        guard wrapped.count == 57_472, driver.count == 383_008,
              sha256(wrapped) == profile.wrappedSHA256, sha256(driver) == profile.driverSHA256 else {
            throw UpdaterError.invalid("Extracted firmware or decoder driver does not match the reviewed package.")
        }
        let fw = BinaryReader(wrapped)
        guard Array(try fw.range(0, 4)) == Array("FZFG".utf8),
              try fw.u32(4) == 128, try fw.u32(8) == 0,
              try fw.u32(0x4c) == 4, try fw.u32(0x64) == 6,
              try fw.u32(0x68) == UInt32(profile.version),
              Array(try fw.range(0x60, 4)) == Array("LPCB".utf8) else {
            throw UpdaterError.invalid("This firmware does not identify the supported T150 controller.")
        }
        let checksum = try stride(from: 0, to: wrapped.count, by: 4).reduce(UInt32(0)) { try $0 &+ fw.u32($1) }
        guard checksum == 0 else { throw UpdaterError.invalid("Firmware checksum failed.") }
        let pe = BinaryReader(driver)
        let tableRVA = 0x590d0
        guard let section = try pe.peSections().first(where: {
            $0.rva <= tableRVA && tableRVA + 2048 <= $0.rva + $0.size
        }) else { throw UpdaterError.invalid("Reviewed decoder table is missing.") }
        let tableOffset = section.offset + tableRVA - section.rva
        let table = try (0..<512).map { Int64(Int32(bitPattern: try pe.u32(tableOffset + 4 * $0))) }
        func signed32(_ value: Int64) -> Int64 { Int64(Int32(bitPattern: UInt32(truncatingIfNeeded: value))) }
        func wave(_ phase: Bool, _ signed: Bool, _ scale: Int64, _ counter: UInt32, _ divisor: Int64) -> Int64 {
            let shifted = Int64(Int32(bitPattern: counter &<< 11))
            let angle = Int((shifted / divisor + (phase ? 0 : 512)) & 2047)
            var value: Int64
            switch angle {
            case 0..<512: value = 65_536 + table[angle]
            case 512..<1024: value = 65_536 + table[1023 - angle]
            case 1024..<1536: value = 65_536 - table[angle - 1024]
            default: value = 65_536 - table[2047 - angle]
            }
            if signed { value -= 65_536 }
            return signed32(value * scale) / 65_536
        }
        var output = fw.bytes
        func setWord(_ offset: Int, _ value: UInt32) {
            for i in 0..<4 { output[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        var seed = fw.bytes[0x70..<0x74].reduce(UInt32(0)) { $0 + UInt32($1) }
        for offset in stride(from: 128, to: output.count, by: 4) {
            let rotate = UInt32(truncatingIfNeeded: wave(false, false, 87, seed, 0x54d)) & 31
            seed &+= 1
            let word = try fw.u32(offset)
            setWord(offset, word &<< rotate | word &>> ((32 - rotate) & 31))
        }
        var state: UInt32 = 0x1351
        var counter: UInt32 = 0
        func nextByte() -> UInt8 {
            state = state &* 0x1173
            if state & 0x80200100 != 0 { counter &+= 0x13d }
            let value = wave(true, true, 255, counter, 3000)
                + wave(false, true, 48, counter &+ 1, 137) + Int64(state)
            counter &+= 2
            return UInt8(truncatingIfNeeded: value)
        }
        _ = nextByte()
        let skip = fw.bytes[0x6c..<0x70].reduce(0) { $0 + Int($1) } & 255
        for _ in 0..<skip { _ = nextByte() }
        for offset in 128..<output.count { output[offset] = output[offset] &- nextByte() }
        output[1] = 0x57 // FZFG -> FWFG
        setWord(0x7c, 0)
        let decoded = BinaryReader(Data(output))
        let sum = try stride(from: 0, to: output.count, by: 4).reduce(UInt32(0)) { try $0 &+ decoded.u32($1) }
        setWord(0x7c, 0 &- sum)
        let result = Data(output)
        guard sha256(result) == profile.decodedSHA256 else {
            throw UpdaterError.invalid("Decoded firmware did not match the independently reviewed image. No update is allowed.")
        }
        return result
    }
}
