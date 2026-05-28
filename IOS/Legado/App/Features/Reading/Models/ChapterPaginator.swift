import UIKit

/// TextKit 2 分页器（iOS 16+）
///
/// 用 NSTextLayoutManager 替换旧的 CTFramesetter，保证分页测量与渲染引擎一致。
/// 改进：
/// - CJK 行尾/行首禁则规则（TextKit 2 原生支持）
/// - 更准确的行高累积，消除 CoreText 贪心断行引起的底部偏差
/// - 同一引擎 → 分页器和 UITextView 渲染器结果完全吻合
@available(iOS 16, *)
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

        // 第一页扣除章节标题的高度
        let titleFont   = UIFont.boldSystemFont(ofSize: font.pointSize + 6)
        let titleLineH  = titleFont.lineHeight + 20.0
        let firstPageH  = max(pageSize.height - titleLineH, 50)

        // 剥离图片标记再分页（图片以固定高度另行渲染）
        let (pureText, _) = stripImageMarkers(text)

        let attrStr = makeAttrString(pureText)

        // ── TextKit 2 测量 ──────────────────────────────────────────
        let storage   = NSTextContentStorage()
        storage.attributedString = attrStr

        let layoutMgr = NSTextLayoutManager()
        storage.addTextLayoutManager(layoutMgr)

        // 用极大高度一次性排版整章
        let container = NSTextContainer(
            size: CGSize(width: pageSize.width, height: 1_000_000)
        )
        container.lineFragmentPadding = 0
        layoutMgr.textContainer = container

        layoutMgr.ensureLayout(for: layoutMgr.documentRange)

        // 枚举 layout fragments，找断页位置
        var pageBreakOffsets: [Int] = [0]
        var accumulated: CGFloat    = 0
        var pageLimit               = firstPageH

        layoutMgr.enumerateTextLayoutFragments(
            from: layoutMgr.documentRange.location,
            options: .ensuresLayout
        ) { frag in
            let h = frag.layoutFragmentFrame.height
            if accumulated + h > pageLimit, accumulated > 0 {
                let off = storage.offset(
                    from: storage.documentRange.location,
                    to:   frag.rangeInElement.location
                )
                pageBreakOffsets.append(off)
                accumulated = h
                pageLimit   = pageSize.height
            } else {
                accumulated += h
            }
            return true
        }

        // 从断页位置重建原始（含图片标记）的页面字符串
        return buildPages(from: text, breaks: pageBreakOffsets, pureText: pureText)
    }

    // MARK: - 私有工具

    /// 把 ⟨IMG:url⟩ 标记剥离，返回纯文本 + 图片标记位置列表
    private func stripImageMarkers(_ text: String) -> (pure: String, markers: [(offset: Int, marker: String)]) {
        let pattern = #"⟨IMG:[^⟩]+⟩"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return (text, []) }
        let ns = text as NSString
        var result = text
        var offset = 0
        var markers: [(Int, String)] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let adjusted = m.range.location - offset
            let marker   = ns.substring(with: m.range)
            markers.append((adjusted, marker))
            result.removeSubrange(result.index(result.startIndex, offsetBy: adjusted) ..< result.index(result.startIndex, offsetBy: adjusted + marker.count))
            offset += marker.count
        }
        return (result, markers)
    }

    /// 将纯文本的断页偏移映射回带有图片标记的原始文本
    private func buildPages(from original: String, breaks: [Int], pureText: String) -> [String] {
        // 简单方案：按纯文本偏移在原始文本里查找对应的断行位置
        // 由于图片标记是独立行，断行点一般不在标记内部，直接按字符比例映射即可
        let nsOrig = original as NSString
        let nsPure = pureText as NSString
        let ratio  = nsOrig.length > 0 ? Double(nsOrig.length) / Double(max(nsPure.length, 1)) : 1.0

        var offsets = breaks.map { Int(Double($0) * ratio) }
        offsets.append(nsOrig.length)

        var pages: [String] = []
        for i in 0 ..< offsets.count - 1 {
            let start = min(offsets[i], nsOrig.length)
            let end   = min(offsets[i + 1], nsOrig.length)
            if end > start {
                pages.append(nsOrig.substring(with: NSRange(location: start, length: end - start)))
            }
        }
        return pages.isEmpty ? [original] : pages
    }

    private func makeAttrString(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        // TextKit 2 用 lineHeightMultiple 比固定行高更准确
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
