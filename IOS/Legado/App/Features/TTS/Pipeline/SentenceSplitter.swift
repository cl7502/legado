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
        var segStart: String.Index = piece.text.startIndex
        var nsOffsetDelta: Int = 0   // NSString (UTF-16) offset from piece.text.startIndex

        while segStart < piece.text.endIndex {
            let remaining = piece.text[segStart...]
            let remainingNSLen = (remaining as NSString).length
            if remainingNSLen <= maxLength {
                results.append(RawPiece(text: String(remaining),
                                        offset: piece.offset + nsOffsetDelta))
                break
            }
            // Walk forward using Swift String.Index (grapheme clusters), tracking NS length
            var cutIdx = segStart
            var nsLen = 0
            var softCutIdx: String.Index? = nil
            var softNsLen = 0

            while cutIdx < piece.text.endIndex {
                let ch = piece.text[cutIdx]
                let chNSLen = (String(ch) as NSString).length
                if nsLen + chNSLen > maxLength { break }
                cutIdx = piece.text.index(after: cutIdx)
                nsLen += chNSLen
                // Record first soft boundary after position 50 (NS chars)
                if softCutIdx == nil && nsLen >= 50 &&
                   ch.unicodeScalars.contains(where: softBoundaries.contains) {
                    softCutIdx = cutIdx
                    softNsLen  = nsLen
                }
            }

            // Use soft boundary if found, else hard cut at maxLength
            let (finalCutIdx, finalNsLen) = softCutIdx != nil
                ? (softCutIdx!, softNsLen)
                : (cutIdx, nsLen)

            let sub = String(piece.text[segStart..<finalCutIdx])
            results.append(RawPiece(text: sub, offset: piece.offset + nsOffsetDelta))
            nsOffsetDelta += finalNsLen
            segStart = finalCutIdx
        }
        return results
    }
}
