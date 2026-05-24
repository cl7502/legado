import UIKit
import CoreText

/// 将章节文字按屏幕可视区域分割为多个物理页
struct ChapterPaginator {
    /// 可用渲染区域（已减去边距）
    let pageSize: CGSize
    let font: UIFont
    let lineSpacing: CGFloat

    // MARK: - 公开接口

    /// 将章节正文分割为页面切片。
    /// - Parameters:
    ///   - text: 章节正文（不含标题）
    ///   - chapterTitle: 章节标题，第一页顶部预留其高度
    /// - Returns: 每页应显示的纯文字切片数组（第一页可能文字较少，因为标题占位）
    func paginate(text: String, chapterTitle: String) -> [String] {
        guard pageSize.width > 0, pageSize.height > 0, !text.isEmpty else {
            return [text]
        }

        // 标题行高度：(fontSize+6) bold 字体 + 20pt 下边距
        let titleFont = UIFont.boldSystemFont(ofSize: font.pointSize + 6)
        let titleLineHeight = titleFont.lineHeight + 20.0

        // 第一页可用高度（扣除标题）
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
            let frame = CTFramesetterCreateFrame(framesetter,
                                                 CFRangeMake(0, 0),
                                                 path,
                                                 nil)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length <= 0 {
                // 保护：无法切分时把剩余全放入一页
                pages.append(remaining as String)
                break
            }

            let slice = remaining.substring(with: NSRange(location: visibleRange.location,
                                                           length: visibleRange.length))
            pages.append(slice)

            let nextStart = visibleRange.location + visibleRange.length
            if nextStart >= remaining.length {
                break
            }
            remaining = remaining.substring(from: nextStart) as NSString
            isFirstPage = false
        }

        return pages.isEmpty ? [text] : pages
    }

    // MARK: - 私有工具

    private func makeAttrString(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: para
        ])
    }
}
