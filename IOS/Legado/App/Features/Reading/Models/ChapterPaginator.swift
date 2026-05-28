import UIKit
import CoreText

/// 将章节文字按屏幕可视区域分割为多个物理页
struct ChapterPaginator {
    let pageSize: CGSize
    let font: UIFont
    let lineSpacing: CGFloat
    let letterSpacing: CGFloat
    let paragraphSpacing: CGFloat

    init(pageSize: CGSize, font: UIFont, lineSpacing: CGFloat,
         letterSpacing: CGFloat = 0, paragraphSpacing: CGFloat = 0) {
        self.pageSize = pageSize
        self.font = font
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
        self.paragraphSpacing = paragraphSpacing
    }

    func paginate(text: String, chapterTitle: String) -> [String] {
        guard pageSize.width > 0, pageSize.height > 0, !text.isEmpty else {
            return [text]
        }

        let titleFont = UIFont.boldSystemFont(ofSize: font.pointSize + 6)
        let titleLineHeight = titleFont.lineHeight + 20.0
        let firstPageHeight = max(pageSize.height - titleLineHeight, 50)

        var pages: [String] = []
        var remaining = text as NSString
        var isFirstPage = true

        while remaining.length > 0 {
            let availableHeight = isFirstPage ? firstPageHeight : pageSize.height
            let attrStr = makeAttrString(remaining as String)
            let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
            let path = CGPath(rect: CGRect(origin: .zero,
                                           size: CGSize(width: pageSize.width, height: availableHeight)),
                              transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length <= 0 {
                pages.append(remaining as String)
                break
            }
            let slice = remaining.substring(with: NSRange(location: visibleRange.location,
                                                           length: visibleRange.length))
            pages.append(slice)
            let nextStart = visibleRange.location + visibleRange.length
            if nextStart >= remaining.length { break }
            remaining = remaining.substring(from: nextStart) as NSString
            isFirstPage = false
        }
        return pages.isEmpty ? [text] : pages
    }

    private func makeAttrString(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        // 用 minimumLineHeight/maximumLineHeight 固定行高，
        // 与 SwiftUI AttributedString 渲染保持一致
        let fixedLineH = font.lineHeight + lineSpacing
        para.minimumLineHeight = fixedLineH
        para.maximumLineHeight = fixedLineH
        para.paragraphSpacing  = paragraphSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: para,
            .kern: letterSpacing,
        ])
    }
}
