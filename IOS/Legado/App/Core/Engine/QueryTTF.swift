import Foundation

/// TTF character-map parser for font-encrypted sources (ISSUE-016).
/// Mirrors Android QueryTTF.kt — builds unicode↔glyph-ID bidirectional maps.
/// Supports cmap Format 4 (BMP, most sources) and Format 12 (full Unicode).
final class QueryTTF {

    /// unicode code point → glyph ID
    let unicodeToGlyph: [UInt32: UInt16]
    /// glyph ID → unicode code point (reverse of above, built on init)
    let glyphToUnicode: [UInt16: UInt32]

    init(data: Data) {
        let fwd = Self.parseTTF(data: data)
        unicodeToGlyph = fwd
        var rev: [UInt16: UInt32] = Dictionary(minimumCapacity: fwd.count)
        for (u, g) in fwd where g != 0 { rev[g] = u }
        glyphToUnicode = rev
    }

    func glyphId(for char: Character) -> UInt16 {
        guard let scalar = char.unicodeScalars.first else { return 0 }
        return unicodeToGlyph[scalar.value] ?? 0
    }

    func char(forGlyphId glyph: UInt16) -> Character? {
        guard let cp = glyphToUnicode[glyph], let scalar = Unicode.Scalar(cp) else { return nil }
        return Character(scalar)
    }

    // MARK: - TTF binary parsing

    private static func parseTTF(data: Data) -> [UInt32: UInt16] {
        guard data.count > 12 else { return [:] }

        // Offset table: sfVersion(4) numTables(2) searchRange(2) entrySelector(2) rangeShift(2)
        let numTables = data.u16(4)

        // Table directory: each record is 16 bytes (tag[4], checkSum[4], offset[4], length[4])
        for i in 0..<Int(numTables) {
            let base = 12 + i * 16
            guard base + 16 <= data.count else { break }
            let tag = String(bytes: data[base..<base+4], encoding: .ascii) ?? ""
            if tag == "cmap" {
                let offset = Int(data.u32(base + 8))
                return parseCMapTable(data: data, offset: offset)
            }
        }
        return [:]
    }

    private static func parseCMapTable(data: Data, offset: Int) -> [UInt32: UInt16] {
        // cmap header: version(2), numSubtables(2)
        guard offset + 4 <= data.count else { return [:] }
        let numSubtables = Int(data.u16(offset + 2))

        // Pick best Unicode subtable (platform 0 = Unicode, platform 3 = Windows Unicode)
        var bestOff: Int? = nil
        var bestPri = -1
        for i in 0..<numSubtables {
            let base = offset + 4 + i * 8
            guard base + 8 <= data.count else { break }
            let pid = data.u16(base)
            let eid = data.u16(base + 2)
            let sub = Int(data.u32(base + 4))
            let pri: Int
            switch (pid, eid) {
            case (0, _):   pri = 3
            case (3, 10):  pri = 4
            case (3, 1):   pri = 2
            default:       pri = -1
            }
            if pri > bestPri { bestPri = pri; bestOff = offset + sub }
        }
        guard let abs = bestOff, abs + 2 <= data.count else { return [:] }

        switch data.u16(abs) {
        case 4:  return parseFmt4(data: data, offset: abs)
        case 12: return parseFmt12(data: data, offset: abs)
        default: return [:]
        }
    }

    // Format 4: segmented BMP mapping
    private static func parseFmt4(data: Data, offset: Int) -> [UInt32: UInt16] {
        guard offset + 14 <= data.count else { return [:] }
        let segCount = Int(data.u16(offset + 6)) / 2
        guard segCount > 0 else { return [:] }

        let endBase   = offset + 14
        let startBase = endBase + segCount * 2 + 2   // +2 for reservedPad
        let deltaBase = startBase + segCount * 2
        let rangeBase = deltaBase + segCount * 2

        guard rangeBase + segCount * 2 <= data.count else { return [:] }

        var map = [UInt32: UInt16](minimumCapacity: segCount * 32)

        for i in 0..<segCount {
            let endCode   = data.u16(endBase   + i * 2)
            let startCode = data.u16(startBase + i * 2)
            let delta     = Int16(bitPattern: data.u16(deltaBase + i * 2))
            let rangeOff  = data.u16(rangeBase + i * 2)

            if startCode == 0xFFFF { break }

            for c in startCode...endCode {
                let glyph: UInt16
                if rangeOff == 0 {
                    glyph = UInt16(bitPattern: Int16(c) &+ delta)
                } else {
                    // Byte offset from position of this idRangeOffset entry
                    let pos = rangeBase + i * 2
                    let glyphOffset = pos + Int(rangeOff) + (Int(c) - Int(startCode)) * 2
                    guard glyphOffset + 2 <= data.count else { continue }
                    let raw = data.u16(glyphOffset)
                    glyph = raw == 0 ? 0 : UInt16(bitPattern: Int16(raw) &+ delta)
                }
                if glyph != 0 { map[UInt32(c)] = glyph }
            }
        }
        return map
    }

    // Format 12: sequential map groups for full Unicode
    private static func parseFmt12(data: Data, offset: Int) -> [UInt32: UInt16] {
        guard offset + 16 <= data.count else { return [:] }
        let numGroups = Int(data.u32(offset + 12))
        let groupBase = offset + 16
        guard groupBase + numGroups * 12 <= data.count else { return [:] }

        var map = [UInt32: UInt16](minimumCapacity: numGroups * 16)

        for i in 0..<numGroups {
            let base       = groupBase + i * 12
            let startCode  = data.u32(base)
            let endCode    = data.u32(base + 4)
            let startGlyph = data.u32(base + 8)
            for (j, code) in (startCode...endCode).enumerated() {
                let glyph = UInt16(truncatingIfNeeded: startGlyph + UInt32(j))
                if glyph != 0 { map[code] = glyph }
            }
        }
        return map
    }
}

// MARK: - Data read helpers (big-endian, as TTF requires)
private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }
    func u32(_ offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) << 24 | UInt32(self[offset+1]) << 16
             | UInt32(self[offset+2]) <<  8 | UInt32(self[offset+3])
    }
}
