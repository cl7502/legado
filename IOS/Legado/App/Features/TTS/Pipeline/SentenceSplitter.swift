import Foundation

struct SentenceUnit {
    let index: Int
    let text: String
    let charOffset: Int    // 在章节文本中的绝对偏移（与 ReaderPageView.pageStartOffset 坐标系一致）
    let charLength: Int
}

final class SentenceSplitter {
    private let hardBoundaries = CharacterSet(charactersIn: "。！？…\n")
    private let softBoundaries = CharacterSet(charactersIn: "，；：")
    private let maxLength = 80
    private let minLength = 5

    func split(_ text: String, baseOffset: Int) -> [SentenceUnit] {
        guard !text.isEmpty else { return [] }
        let raw = splitAtHardBoundaries(text)
        let merged = mergeShort(raw)
        let chopped = merged.flatMap { chopLong($0) }
        return chopped.enumerated().map { idx, pair in
            SentenceUnit(index: idx,
                         text: pair.text,
                         charOffset: baseOffset + pair.offset,
                         charLength: (pair.text as NSString).length)
        }
    }

    // MARK: - Private

    private struct RawPiece { let text: String; let offset: Int }

    private func splitAtHardBoundaries(_ text: String) -> [RawPiece] {
        var pieces: [RawPiece] = []
        var pieceStart = text.startIndex
        var byteOffset = 0   // NSString UTF-16 offset
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            let isHard = ch.unicodeScalars.contains(where: hardBoundaries.contains)
            let next = text.index(after: i)
            if isHard {
                let piece = String(text[pieceStart...i])
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    pieces.append(RawPiece(text: piece, offset: byteOffset))
                }
                byteOffset += (piece as NSString).length
                pieceStart = next
            }
            i = next
        }
        // 末尾无边界符的剩余文本
        if pieceStart < text.endIndex {
            let piece = String(text[pieceStart...])
            if !piece.trimmingCharacters(in: .whitespaces).isEmpty {
                pieces.append(RawPiece(text: piece, offset: byteOffset))
            }
        }
        return pieces
    }

    private func mergeShort(_ pieces: [RawPiece]) -> [RawPiece] {
        var result: [RawPiece] = []
        var i = 0
        while i < pieces.count {
            var piece = pieces[i]
            while (piece.text as NSString).length < minLength && i + 1 < pieces.count {
                i += 1
                piece = RawPiece(text: piece.text + pieces[i].text, offset: piece.offset)
            }
            result.append(piece)
            i += 1
        }
        return result
    }

    private func chopLong(_ piece: RawPiece) -> [RawPiece] {
        guard (piece.text as NSString).length > maxLength else { return [piece] }
        var results: [RawPiece] = []
        var startIdx = piece.text.startIndex
        var offsetDelta = 0
        while startIdx < piece.text.endIndex {
            let remaining = String(piece.text[startIdx...])
            if (remaining as NSString).length <= maxLength {
                results.append(RawPiece(text: remaining, offset: piece.offset + offsetDelta))
                break
            }
            // 在 50 字附近找最近的软边界
            let maxOff = min(maxLength - 1, (remaining as NSString).length - 1)
            var cutOffset = min(50, maxOff)
            var found = false
            // 向后搜索软边界直到 maxLength
            while cutOffset <= maxOff {
                let idx = remaining.index(remaining.startIndex, offsetBy: cutOffset)
                if remaining[idx].unicodeScalars.contains(where: softBoundaries.contains) {
                    cutOffset += 1  // include the boundary char
                    found = true
                    break
                }
                cutOffset += 1
            }
            if !found { cutOffset = maxOff + 1 }
            let cutIdx = remaining.index(remaining.startIndex, offsetBy: cutOffset)
            let sub = String(remaining[..<cutIdx])
            results.append(RawPiece(text: sub, offset: piece.offset + offsetDelta))
            offsetDelta += (sub as NSString).length
            startIdx = piece.text.index(startIdx, offsetBy: (sub as NSString).length)
        }
        return results
    }
}
