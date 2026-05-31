import Foundation

final class TextNormalizer {

    private static let chineseDigits = ["零","一","二","三","四","五","六","七","八","九"]

    func normalize(_ text: String) -> String {
        var s = text
        s = removeHiddenChars(s)
        s = normalizeDecimalAmount(s)   // 1,234.56元 → 优先处理，避免被整数规则打断
        s = normalizeYear(s)
        s = normalizeMonthDay(s)
        s = normalizeTime(s)
        s = normalizePercentage(s)
        s = normalizeInteger(s)
        s = normalizeEllipsis(s)
        return s
    }

    // MARK: - Private rules

    private func removeHiddenChars(_ s: String) -> String {
        // \u{3000} = 全角空格（中文段落缩进），ZipVoice lexicon 无法识别，替换为普通空格
        let hidden: [Character] = ["\u{200B}", "\u{FEFF}", "\u{00A0}"]
        return s.filter { !hidden.contains($0) }
                .replacingOccurrences(of: "\u{3000}", with: " ")
    }

    private func normalizeEllipsis(_ s: String) -> String {
        s.replacingOccurrences(of: "……", with: "…")
         .replacingOccurrences(of: "...", with: "…")
    }

    private func normalizeYear(_ s: String) -> String {
        let pattern = #"(\d{4})年"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        // Work backwards so replacements don't shift earlier indices
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            // match.range covers e.g. "2024年" (5 chars); range(at:1) covers "2024" (4 chars)
            guard let digitRange = Range(match.range(at: 1), in: result),
                  let fullRange  = Range(match.range,         in: result) else { continue }
            let digits = String(result[digitRange])
            let cn = digits.compactMap { Int(String($0)).map { Self.chineseDigits[$0] } }.joined()
            result.replaceSubrange(fullRange, with: cn + "年")
        }
        return result
    }

    private func normalizeMonthDay(_ s: String) -> String {
        let pattern = #"(\d{1,2})月(\d{1,2})日"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let m = Range(match.range(at: 1), in: result),
                  let d = Range(match.range(at: 2), in: result) else { continue }
            let mCN = intToChinese(Int(result[m])!)
            let dCN = intToChinese(Int(result[d])!)
            result.replaceSubrange(fullRange, with: "\(mCN)月\(dCN)日")
        }
        return result
    }

    private func normalizeTime(_ s: String) -> String {
        let pattern = #"(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let h = Range(match.range(at: 1), in: result),
                  let m = Range(match.range(at: 2), in: result) else { continue }
            let hCN = intToChinese(Int(result[h])!)
            let mCN = intToChinese(Int(result[m])!)
            result.replaceSubrange(fullRange, with: "\(hCN)点\(mCN)分")
        }
        return result
    }

    private func normalizePercentage(_ s: String) -> String {
        let pattern = #"(\d+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result),
                  let num = Int(result[numRange]) else { continue }
            result.replaceSubrange(fullRange, with: "百分之\(intToChinese(num))")
        }
        return result
    }

    private func normalizeDecimalAmount(_ s: String) -> String {
        let pattern = #"([\d,]+\.\d+)元"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result) else { continue }
            let numStr = result[numRange].replacingOccurrences(of: ",", with: "")
            let parts = numStr.split(separator: ".")
            guard parts.count == 2, let intPart = Int(parts[0]) else { continue }
            let intCN = intToChinese(intPart)
            let decCN = String(parts[1]).compactMap { Int(String($0)).map { Self.chineseDigits[$0] } }.joined()
            result.replaceSubrange(fullRange, with: "\(intCN)点\(decCN)元")
        }
        return result
    }

    private func normalizeInteger(_ s: String) -> String {
        let pattern = #"(?<![.\d])(\d{1,8})(?![.\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 1), in: result),
                  let num = Int(result[fullRange]) else { continue }
            result.replaceSubrange(fullRange, with: intToChinese(num))
        }
        return result
    }

    // MARK: - 整数转汉字（≤ 99_999_999）

    func intToChinese(_ n: Int) -> String {
        if n == 0 { return "零" }
        if n < 10 { return Self.chineseDigits[n] }
        var result: String
        if n < 10000 {
            result = convertBelow10000(n)
        } else {
            let wan = n / 10000
            let rest = n % 10000
            result = convertBelow10000(wan) + "万"
            if rest > 0 {
                if rest < 1000 { result += "零" }
                result += convertBelow10000(rest)
            }
        }
        // 口语习惯：量词前的"二"读作"两"（二千→两千，二百→两百，二万→两万）
        result = result
            .replacingOccurrences(of: "二千", with: "两千")
            .replacingOccurrences(of: "二百", with: "两百")
            .replacingOccurrences(of: "二万", with: "两万")
        return result
    }

    private func convertBelow10000(_ n: Int) -> String {
        guard n > 0 else { return "" }
        var result = ""
        let thousands = n / 1000;  let rem1 = n % 1000
        let hundreds  = rem1 / 100; let rem2 = rem1 % 100
        let tens      = rem2 / 10;  let ones = rem2 % 10
        var needZero  = false   // 待插入的补零标志，延迟写入避免尾零

        if thousands > 0 {
            result += Self.chineseDigits[thousands] + "千"
            if rem1 == 0 { return result }                  // 整千，直接返回
            if hundreds == 0 { needZero = true }            // 千后无百，需补零
        }
        if hundreds > 0 {
            if needZero { result += "零"; needZero = false }
            result += Self.chineseDigits[hundreds] + "百"
            if rem2 == 0 { return result }                  // 整百，直接返回
            if tens == 0 { needZero = true }                // 百后无十，需补零
        }
        if tens > 0 {
            if needZero { result += "零"; needZero = false }
            result += (tens == 1 && thousands == 0 && hundreds == 0)
                ? "十"
                : Self.chineseDigits[tens] + "十"
        }
        if ones > 0 {
            if needZero { result += "零" }
            result += Self.chineseDigits[ones]
        }
        return result
    }
}
