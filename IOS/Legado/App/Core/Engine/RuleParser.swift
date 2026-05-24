import Foundation

enum RuleType {
    case defaultRule  // CSS 选择器（可含 @attr 后缀）
    case xpath
    case json
    case regex
    case js
}

struct RuleSegment {
    let type: RuleType
    let content: String
}

/// 规则链解析器
/// 修复：状态机分割避免 JS 块/属性名被错切，合并 selector@attr 为单一段
class RuleParser {
    static let shared = RuleParser()

    func parseChain(_ rule: String) -> [RuleSegment] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 整体是 JS 的快速路径
        if trimmed.hasPrefix("javascript:") ||
           (trimmed.hasPrefix("<js>") && trimmed.hasSuffix("</js>")) {
            return [parseSingle(trimmed)]
        }

        // 1. 状态机按 @ 分割，跳过 <js>...</js> 内部
        let parts = splitOnAt(trimmed)

        // 2. 把紧跟在 CSS 段后的属性名合并回去：["a", "href"] → ["a@href"]
        var segments: [RuleSegment] = []
        var i = 0
        while i < parts.count {
            let part = parts[i]
            if part.isEmpty { i += 1; continue }

            if i + 1 < parts.count {
                let next = parts[i + 1]
                // 下一段是纯属性名 → 合并为 "selector@attr"
                if !next.isEmpty && isAttributeName(next) {
                    segments.append(parseSingle(part + "@" + next))
                    i += 2
                    continue
                }
            }
            segments.append(parseSingle(part))
            i += 1
        }
        return segments
    }

    // MARK: - Private

    /// 状态机分割：@ 在 <js>...</js> 内不切割
    private func splitOnAt(_ rule: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var jsDepth = 0
        var idx = rule.startIndex

        while idx < rule.endIndex {
            let rest = rule[idx...]
            if !rest.hasPrefix("<js>") && !rest.hasPrefix("</js>") {
                let ch = rule[idx]
                if ch == "@" && jsDepth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
                idx = rule.index(after: idx)
                continue
            }
            if rest.hasPrefix("<js>") {
                jsDepth += 1
                current += "<js>"
                idx = rule.index(idx, offsetBy: 4)
            } else { // </js>
                jsDepth = max(0, jsDepth - 1)
                current += "</js>"
                idx = rule.index(idx, offsetBy: 5)
            }
        }
        parts.append(current)
        return parts
    }

    /// 是否是 HTML 属性名（不含 CSS 特殊字符）
    private func isAttributeName(_ s: String) -> Bool {
        let knownAttrs: Set<String> = [
            "text", "html", "outerHtml", "href", "src", "alt", "title",
            "class", "id", "name", "value", "type", "style", "content",
            "rel", "action", "placeholder", "srcset", "data"
        ]
        if knownAttrs.contains(s) { return true }
        if s.hasPrefix("data-") && s.count > 5 { return true }
        // 纯字母数字（无 CSS 特殊符号）也当属性名
        let cssSpecial = CharacterSet(charactersIn: ".#[]>+~:() ,\\\"'")
        return !s.isEmpty && s.unicodeScalars.allSatisfy { !cssSpecial.contains($0) }
               && s.unicodeScalars.first.map { CharacterSet.letters.contains($0) } == true
    }

    private func parseSingle(_ rule: String) -> RuleSegment {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("javascript:") ||
           (trimmed.hasPrefix("<js>") && trimmed.hasSuffix("</js>")) {
            let content: String
            if trimmed.hasPrefix("javascript:") {
                content = String(trimmed.dropFirst(11))
            } else {
                content = String(trimmed.dropFirst(4).dropLast(5))
            }
            return RuleSegment(type: .js, content: content)
        }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("@xpath:") {
            return RuleSegment(type: .xpath, content: String(trimmed.dropFirst(7)))
        }
        if lower.hasPrefix("xpath:") {
            return RuleSegment(type: .xpath, content: String(trimmed.dropFirst(6)))
        }
        if lower.hasPrefix("@json:") {
            return RuleSegment(type: .json, content: String(trimmed.dropFirst(6)))
        }
        if lower.hasPrefix("json:") {
            return RuleSegment(type: .json, content: String(trimmed.dropFirst(5)))
        }
        if trimmed.hasPrefix(":") {
            return RuleSegment(type: .regex, content: String(trimmed.dropFirst(1)))
        }

        return RuleSegment(type: .defaultRule, content: trimmed)
    }
}
