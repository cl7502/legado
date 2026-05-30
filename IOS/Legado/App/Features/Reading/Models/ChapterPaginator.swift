import UIKit
import CoreText

/// 章节分页器 — 使用 CoreText CTFramesetter（稳定，跨线程安全）。
///
/// 渲染层已切换到 TextKit 2 (UITextView)，但分页测量继续用 CoreText，原因：
/// NSTextLayoutManager.ensureLayout(for:) 在主线程同步调用时会与内部 UIKit
/// 调度产生死锁，watchdog 8秒后 SIGKILL。CoreText 纯 C API，无此问题。
struct ChapterPaginator {
    let pageSize: CGSize
    let font: UIFont
    let lineSpacing: CGFloat
    let letterSpacing: CGFloat
    let paragraphSpacing: CGFloat

    init(pageSize: CGSize, font: UIFont, lineSpacing: CGFloat,
         letterSpacing: CGFloat = 0, paragraphSpacing: CGFloat = 0) {
        self.pageSize         = pageSize
        self.font             = font
        self.lineSpacing      = lineSpacing
        self.letterSpacing    = letterSpacing
        self.paragraphSpacing = paragraphSpacing
    }

    func paginate(text: String, chapterTitle: String) -> [String] {
        guard pageSize.width > 0, pageSize.height > 0, !text.isEmpty else { return [text] }

        let titleFont    = UIFont.boldSystemFont(ofSize: font.pointSize + 6)
        let titleLineH   = titleFont.lineHeight + 20.0
        let firstPageH   = max(pageSize.height - titleLineH, 50)

        var pages: [String] = []
        var remaining = text as NSString
        var isFirstPage = true

        while remaining.length > 0 {
            let availableH = isFirstPage ? firstPageH : pageSize.height
            let attrStr    = makeAttrString(remaining as String)
            let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
            let path = CGPath(
                rect: CGRect(origin: .zero,
                             size: CGSize(width: pageSize.width, height: availableH)),
                transform: nil
            )
            let frame        = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length <= 0 {
                pages.append(remaining as String)
                break
            }
            let slice = remaining.substring(
                with: NSRange(location: visibleRange.location, length: visibleRange.length)
            )
            pages.append(slice)
            let nextStart = visibleRange.location + visibleRange.length
            if nextStart >= remaining.length { break }

            // 跳过段落边界处的换行符：若下一页以 \n 开头，TextKit2 会将其渲染为
            // 一整行空白（lineHeight + paragraphSpacing ≈ 38pt），造成顶部空白过大
            var adjustedStart = nextStart
            while adjustedStart < remaining.length
                    && remaining.character(at: adjustedStart) == 0x000A {
                adjustedStart += 1
            }
            if adjustedStart >= remaining.length { break }
            remaining   = remaining.substring(from: adjustedStart) as NSString
            isFirstPage = false
        }
        return pages.isEmpty ? [text] : pages
    }

    private func makeAttrString(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        let fixedH = font.lineHeight + lineSpacing
        para.minimumLineHeight  = fixedH
        para.maximumLineHeight  = fixedH
        para.paragraphSpacing   = paragraphSpacing
        return NSAttributedString(string: text, attributes: [
            .font:           font,
            .paragraphStyle: para,
            .kern:           letterSpacing,
        ])
    }
}
