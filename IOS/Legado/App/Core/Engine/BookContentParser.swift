import Foundation
import SwiftSoup

/// Book content parser — mirrors Android BookContent.analyzeContent()
///
/// Flow:
///   1. Apply content rule → extract HTML fragment
///   2. Convert HTML to readable plain text (preserving line breaks)
///   3. Apply source-level replaceRegex (ruleContentReplace field)
///   4. Apply user ReplaceRules
///   5. Apply basic formatting (trim, indent)
class BookContentParser {
    static let shared = BookContentParser()

    private let ruleExecutor = RuleExecutor.shared
    private let contentProcessor = ContentProcessor.shared

    /// Parse and clean chapter content.
    func parseContent(
        _ rawHtml: String,
        rule: String,
        context: inout AnalyzeContext,
        replaceRules: [ReplaceRule] = []
    ) -> String {
        context.result = rawHtml

        // 1. Extract content via rule
        guard let extracted = ruleExecutor.execute(rule, in: &context), !extracted.isEmpty else {
            // Fallback: try body text if rule is empty or fails
            if rule.isEmpty {
                return processText(rawHtml, source: context.source, replaceRules: replaceRules)
            }
            return "正文解析失败"
        }

        return processText(extracted, source: context.source, replaceRules: replaceRules)
    }

    // MARK: - Internal pipeline

    private func processText(_ html: String, source: BookSource, replaceRules: [ReplaceRule]) -> String {
        // 2. HTML → plain text
        var text = htmlToPlainText(html)

        // 3. Source-level replaceRegex (ruleContentReplace field on book source)
        if let srcReplace = source.ruleContentReplace, !srcReplace.isEmpty {
            text = applySourceReplace(text, rule: srcReplace)
        }

        // 4. User replace rules
        text = contentProcessor.process(text, with: replaceRules)

        return text
    }

    /// Apply source-level content replace rule (Android: contentRule.replaceRegex).
    /// Format mirrors Android ReplaceRule format: patterns separated by newline,
    /// each entry is "pattern##replacement" (regex if starts with /).
    private func applySourceReplace(_ text: String, rule: String) -> String {
        var result = text
        let entries = rule.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for entry in entries where !entry.isEmpty {
            let parts = entry.components(separatedBy: "##")
            let pattern     = parts[0]
            let replacement = parts.count > 1 ? parts[1] : ""
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            } else {
                result = result.replacingOccurrences(of: pattern, with: replacement)
            }
        }
        return result
    }

    /// HTML → plain text.
    /// Mirrors Android HtmlFormatter.formatKeepImg() behaviour:
    ///   • <p>, <div>, <br> → newline
    ///   • Trim each line, remove empty lines
    ///   • Indent each paragraph with two ideographic spaces (Android default)
    func htmlToPlainText(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        // If it looks like plain text (no tags), skip HTML parsing
        if !html.contains("<") {
            return formatLines(html.components(separatedBy: .newlines))
        }

        do {
            let doc = try SwiftSoup.parse(html)
            // Remove script/style nodes
            try doc.select("script, style, head").remove()

            // Convert block elements to newline markers before text extraction
            let blockTags = ["p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6",
                             "blockquote", "tr", "dt", "dd", "article", "section"]
            for tag in blockTags {
                for el in try doc.select(tag).array() {
                    try el.before("\n")
                    try el.after("\n")
                }
            }

            let rawText = try doc.body()?.text() ?? ""
            // body().text() already collapses whitespace; split on the \n markers we injected
            let lines = rawText.components(separatedBy: "\n")
            return formatLines(lines)
        } catch {
            // Fallback regex-based stripping
            var text = html
            text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: "</p>|</div>|</li>", with: "\n",
                                              options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return formatLines(text.components(separatedBy: .newlines))
        }
    }

    private func formatLines(_ lines: [String]) -> String {
        let trimmed = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Android default indent: two ideographic spaces (　　)
        return trimmed.map { "　　" + $0 }.joined(separator: "\n\n")
    }
}
