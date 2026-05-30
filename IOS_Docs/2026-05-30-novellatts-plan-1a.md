# NovellaTTS Phase 1a：核心流水线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Sherpa-ONNX + Kokoro 替换现有 AVSpeechSynthesizer，实现句级流式朗读，保持与 ReaderViewModel / ReaderView 的接口完全兼容，单一预设声音跑通全流程。

**Architecture:** NovellaTTSEngine 实现与 TTSManager 相同的公开接口（TTSProtocol），ReaderViewModel 切换到协议类型后无需修改调用代码。原始文本先 SentenceSplitter 断句（保留原始偏移量），每句分别经 TextNormalizer 归一化后送入 SherpaKokoroEngine，合成在后台 Task.detached 执行（不阻塞 MainActor），PCM 结果切回主线程交给 AudioPipeline → speakingRange 回调驱动现有高亮和翻页逻辑。ReaderViewModel 新增 `ttsState` Published 转发器，ReaderMenuView 从 viewModel 读取状态。

**Tech Stack:** Swift 5.9, iOS 15+, Sherpa-ONNX XCFramework, Kokoro-multi-lang-v1.1-int8（140 MB），AVAudioEngine, Combine, XCTest

> **架构关键约束（Review 修正）**
> 1. `SherpaKokoroEngine.synthesize()` 在 `Task.detached` 里执行，严禁在 MainActor 上运行 ONNX 推理
> 2. `SentenceSplitter` 使用原始文本计算 `charOffset`，`TextNormalizer` 仅在送入 TTS 前对文本应用，不影响偏移坐标
> 3. `ReaderMenuView` 通过 `viewModel.ttsState` 观察 TTS 状态，不直接引用具体引擎实例

---

## 文件变更清单

| 操作 | 文件 | 职责 |
|------|------|------|
| 创建 | `App/Features/TTS/TTSProtocol.swift` | TTSManager 与 NovellaTTSEngine 共用接口 |
| 创建 | `App/Features/TTS/Pipeline/TextNormalizer.swift` | 数字/日期/符号 → 可读汉字 |
| 创建 | `App/Features/TTS/Pipeline/SentenceSplitter.swift` | 章节文本 → [SentenceUnit] |
| 创建 | `App/Features/TTS/Engines/TTSEngine.swift` | 引擎协议（合成 + warmup）|
| 创建 | `App/Features/TTS/Engines/SherpaKokoroEngine.swift` | Sherpa-ONNX Kokoro 封装 |
| 创建 | `App/Features/TTS/Engines/ZipVoiceEngine.swift` | Phase 2 占位桩 |
| 创建 | `App/Features/TTS/AudioPipeline.swift` | AVAudioEngine 流式播放 |
| 创建 | `App/Features/TTS/NovellaTTSEngine.swift` | 主控协调器 |
| 创建 | `App/Resources/preset_voices.json` | 预设声音配置 |
| 修改 | `App/Features/Reading/ViewModels/ReaderViewModel.swift` | ttsManager 改为协议类型 |
| 修改 | `App/Features/Reading/Views/ReaderView.swift` | ReaderMenuView.ttsManager 适配 |
| 修改 | `App/Features/TTS/ViewModels/TTSManager.swift` | 让现有类实现 TTSProtocol |
| 测试 | `LegadoTests/TTS/TextNormalizerTests.swift` | |
| 测试 | `LegadoTests/TTS/SentenceSplitterTests.swift` | |

---

## Task 1：TTSProtocol + 项目结构

**Files:**
- Create: `IOS/Legado/App/Features/TTS/TTSProtocol.swift`
- Create: `IOS/Legado/App/Features/TTS/Engines/TTSEngine.swift`
- Create: `IOS/Legado/App/Features/TTS/Engines/ZipVoiceEngine.swift`
- Create: `IOS/LegadoTests/TTS/` (目录)

- [ ] **Step 1.1：创建目录结构**

```bash
mkdir -p IOS/Legado/App/Features/TTS/Pipeline
mkdir -p IOS/Legado/App/Features/TTS/Engines
mkdir -p IOS/Legado/App/Features/TTS/CharacterDetection
mkdir -p IOS/Legado/App/Features/TTS/VoiceRegistry
mkdir -p IOS/LegadoTests/TTS
```

- [ ] **Step 1.2：创建 TTSProtocol.swift**

`IOS/Legado/App/Features/TTS/TTSProtocol.swift`:

```swift
import Foundation
import AVFoundation

/// TTSManager（系统TTS）和 NovellaTTSEngine（高质量TTS）共用的公开接口。
/// ReaderViewModel 和 ReaderView 只依赖此协议，切换引擎无需改调用代码。
protocol TTSProtocol: AnyObject {
    var isPlaying: Bool { get }
    var speakingRange: NSRange? { get }
    var remainingSeconds: Int? { get }
    var isSpeaking: Bool { get }

    /// selectedVoice 仅 TTSManager（AVSpeechSynthesizer）使用，NovellaTTSEngine 可空实现
    var selectedVoice: AVSpeechSynthesisVoice? { get set }

    func speak(_ text: String, bookName: String, chapterTitle: String,
               onFinish: @escaping () -> Void)
    func pause()
    func resume()
    func stop()
    func startTimer(minutes: Int)
    func cancelTimer()
    func restartForSettingChange()
}
```

- [ ] **Step 1.3：创建引擎协议 TTSEngine.swift**

`IOS/Legado/App/Features/TTS/Engines/TTSEngine.swift`:

```swift
import Foundation

struct AudioChunk {
    let samples: [Float]
    let sampleRate: Int
}

struct VoiceConfig {
    let id: String           // 角色槽位 ID，如 "narrator"
    let speakerId: Int       // Kokoro speaker index
    let displayName: String
}

struct SpeakingStyle {
    var rateMultiplier: Float    = 1.0
    var pitchOffset: Float       = 0.0
    var volumeMultiplier: Float  = 1.0

    static let normal = SpeakingStyle()
}

protocol TTSEngine: AnyObject {
    var isReady: Bool { get }
    func warmup() async
    func synthesize(
        text: String,
        voice: VoiceConfig,
        style: SpeakingStyle
    ) async throws -> AudioChunk
}
```

- [ ] **Step 1.4：创建 ZipVoiceEngine 占位桩**

`IOS/Legado/App/Features/TTS/Engines/ZipVoiceEngine.swift`:

```swift
import Foundation

/// Phase 2 占位桩，待 ZipVoice ONNX 就绪后实现。
final class ZipVoiceEngine: TTSEngine {
    var isReady: Bool { false }
    func warmup() async {}
    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk {
        throw TTSError.engineNotReady
    }
}

enum TTSError: Error {
    case engineNotReady
    case modelNotFound(String)
    case synthesizeFailed(String)
}
```

- [ ] **Step 1.5：让现有 TTSManager 实现 TTSProtocol**

编辑 `IOS/Legado/App/Features/TTS/ViewModels/TTSManager.swift`，在类声明行加 `TTSProtocol`：

```swift
// 修改前
class TTSManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {

// 修改后
class TTSManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject, TTSProtocol {
```

`TTSManager` 已有 `isPlaying`、`speakingRange`、`remainingSeconds`、`isSpeaking`、`selectedVoice`、`speak`、`pause`、`resume`、`stop`、`startTimer`、`cancelTimer`、`restartForSettingChange` 全部方法，编译器会直接通过。

- [ ] **Step 1.6：编译验证**

```bash
cd IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 1.7：Commit**

```bash
git add IOS/Legado/App/Features/TTS/ IOS/LegadoTests/
git commit -m "feat(tts): TTSProtocol + TTSEngine 协议 + 目录结构"
```

---

## Task 2：TextNormalizer（TDD）

**Files:**
- Create: `IOS/Legado/App/Features/TTS/Pipeline/TextNormalizer.swift`
- Create: `IOS/LegadoTests/TTS/TextNormalizerTests.swift`

- [ ] **Step 2.1：创建测试文件（先写测试）**

`IOS/LegadoTests/TTS/TextNormalizerTests.swift`:

```swift
import XCTest
@testable import Legado

final class TextNormalizerTests: XCTestCase {
    var sut: TextNormalizer!

    override func setUp() { sut = TextNormalizer() }

    func test_integer_under_10000() {
        XCTAssertEqual(sut.normalize("今天来了3个人"), "今天来了三个人")
    }

    func test_integer_10000_plus() {
        XCTAssertEqual(sut.normalize("损失12000元"), "损失一万两千元")
    }

    func test_year_4digits() {
        XCTAssertEqual(sut.normalize("2024年"), "二零二四年")
    }

    func test_month_day() {
        XCTAssertEqual(sut.normalize("10月1日"), "十月一日")
    }

    func test_time_hhmm() {
        XCTAssertEqual(sut.normalize("14:30"), "十四点三十分")
    }

    func test_percentage() {
        XCTAssertEqual(sut.normalize("成功率98%"), "成功率百分之九十八")
    }

    func test_decimal_amount() {
        XCTAssertEqual(sut.normalize("花了1,234.56元"), "花了一千二百三十四点五六元")
    }

    func test_ellipsis_normalized() {
        XCTAssertEqual(sut.normalize("他说……然后离开"), "他说…然后离开")
    }

    func test_zero_width_chars_removed() {
        XCTAssertEqual(sut.normalize("他\u{200B}说"), "他说")
    }

    func test_mixed_sentence() {
        let input = "他花了1,234.56元买了3本书，于2024年10月1日到货"
        let output = sut.normalize(input)
        XCTAssertTrue(output.contains("一千二百三十四点五六元"))
        XCTAssertTrue(output.contains("三本书"))
        XCTAssertTrue(output.contains("二零二四年十月一日"))
    }
}
```

- [ ] **Step 2.2：创建 TextNormalizer.swift（最小实现使测试通过）**

`IOS/Legado/App/Features/TTS/Pipeline/TextNormalizer.swift`:

```swift
import Foundation

final class TextNormalizer {

    private static let chineseDigits = ["零","一","二","三","四","五","六","七","八","九"]
    private static let chineseUnits  = ["","十","百","千","万","十","百","千","亿"]

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
        let hidden: [Character] = ["\u{200B}", "\u{FEFF}", "\u{00A0}"]
        return s.filter { !hidden.contains($0) }
    }

    private func normalizeEllipsis(_ s: String) -> String {
        // 多个连续省略号归一为单个…
        s.replacingOccurrences(of: "……", with: "…")
         .replacingOccurrences(of: "...", with: "…")
    }

    private func normalizeYear(_ s: String) -> String {
        // 四位年份：2024年 → 二零二四年
        let pattern = #"(\d{4})年"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            let digits = String(result[range])
            let cn = digits.compactMap { Int(String($0)).map { Self.chineseDigits[$0] } }.joined()
            result.replaceSubrange(result.range(of: digits + "年", range: range.lowerBound...)!,
                                   with: cn + "年")
        }
        return result
    }

    private func normalizeMonthDay(_ s: String) -> String {
        // 10月1日 → 十月一日
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
        // 14:30 → 十四点三十分
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
        // 98% → 百分之九十八
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
        // 1,234.56元 → 一千二百三十四点五六元
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
        // 独立整数（前后非数字/汉字连续）→ 汉字
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
        if n < 10000 { return convertBelow10000(n) }
        let wan = n / 10000
        let rest = n % 10000
        var result = convertBelow10000(wan) + "万"
        if rest > 0 {
            if rest < 1000 { result += "零" }
            result += convertBelow10000(rest)
        }
        return result
    }

    private func convertBelow10000(_ n: Int) -> String {
        guard n > 0 else { return "" }
        var result = ""
        let thousands = n / 1000;  let rem1 = n % 1000
        let hundreds  = rem1 / 100; let rem2 = rem1 % 100
        let tens      = rem2 / 10;  let ones = rem2 % 10

        if thousands > 0 { result += Self.chineseDigits[thousands] + "千" }
        if hundreds  > 0 { result += Self.chineseDigits[hundreds]  + "百" }
        else if thousands > 0 && rem2 > 0 { result += "零" }
        if tens > 0 {
            result += (tens == 1 && thousands == 0 && hundreds == 0) ? "十" :
                       Self.chineseDigits[tens] + "十"
        } else if (thousands > 0 || hundreds > 0) && ones > 0 { result += "零" }
        if ones > 0 { result += Self.chineseDigits[ones] }
        return result
    }
}
```

- [ ] **Step 2.3：在 Xcode 中将 LegadoTests target 加入 Package.swift**

编辑 `IOS/Legado/Package.swift`，确认测试 target 路径为 `Tests`（已有），在 `IOS/` 根目录建测试目录映射。由于项目使用 Xcode 而非纯 SPM，需在 Xcode 里手动：

1. File → New → Target → Unit Testing Bundle，命名 `LegadoTests`
2. 将 `TextNormalizerTests.swift` 加入该 target
3. 在 target 的 Build Settings → `SWIFT_OBJC_BRIDGING_HEADER` 留空，`@testable import Legado` 即可

- [ ] **Step 2.4：运行测试**

在 Xcode 中：Product → Test（⌘U），或：

```bash
xcodebuild test -project IOS/Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -only-testing:LegadoTests/TextNormalizerTests 2>&1 | grep -E "passed|failed|error"
```

期望：全部 10 个测试 passed。

- [ ] **Step 2.5：Commit**

```bash
git add IOS/Legado/App/Features/TTS/Pipeline/TextNormalizer.swift \
        IOS/LegadoTests/TTS/TextNormalizerTests.swift
git commit -m "feat(tts): TextNormalizer 数字/日期/符号归一化（含测试）"
```

---

## Task 3：SentenceSplitter（TDD）

**Files:**
- Create: `IOS/Legado/App/Features/TTS/Pipeline/SentenceSplitter.swift`
- Create: `IOS/LegadoTests/TTS/SentenceSplitterTests.swift`

- [ ] **Step 3.1：写测试**

`IOS/LegadoTests/TTS/SentenceSplitterTests.swift`:

```swift
import XCTest
@testable import Legado

final class SentenceSplitterTests: XCTestCase {
    var sut: SentenceSplitter!
    override func setUp() { sut = SentenceSplitter() }

    func test_hard_boundary_splits() {
        let result = sut.split("他来了。她离开了。", baseOffset: 0)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "他来了。")
        XCTAssertEqual(result[1].text, "她离开了。")
    }

    func test_newline_splits() {
        let result = sut.split("第一句\n第二句", baseOffset: 0)
        XCTAssertEqual(result.count, 2)
    }

    func test_short_sentences_merged() {
        // "好。" 只有2字，应与下一句合并
        let result = sut.split("好。他继续说话。", baseOffset: 0)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "好。他继续说话。")
    }

    func test_long_sentence_split_at_soft_boundary() {
        // 超过 50 字应在逗号处分割
        let long = "林峰看了看她，想起了往事，那是很多年前的事情了，具体是哪一年他已经记不清楚，只知道那时候天气很好。"
        let result = sut.split(long, baseOffset: 0)
        XCTAssertTrue(result.count > 1)
        // 每段不超过 80 字
        result.forEach { XCTAssertLessThanOrEqual($0.text.count, 80) }
    }

    func test_char_offset_is_correct() {
        let text = "第一句。第二句。"
        let result = sut.split(text, baseOffset: 100)
        XCTAssertEqual(result[0].charOffset, 100)
        XCTAssertEqual(result[1].charOffset, 100 + (text as NSString).range(of: "第二句").location)
    }

    func test_empty_string() {
        let result = sut.split("", baseOffset: 0)
        XCTAssertTrue(result.isEmpty)
    }
}
```

- [ ] **Step 3.2：实现 SentenceSplitter**

`IOS/Legado/App/Features/TTS/Pipeline/SentenceSplitter.swift`:

```swift
import Foundation

struct SentenceUnit {
    let index: Int
    let text: String
    let charOffset: Int    // 在章节文本中的绝对偏移（\n\n→\n 归一化后坐标）
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
        var start = text.startIndex
        var offset = 0
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            let isHard = ch.unicodeScalars.contains(where: hardBoundaries.contains)
            let next = text.index(after: i)
            if isHard {
                let piece = String(text[start...i])
                if !piece.trimmingCharacters(in: .whitespaces).isEmpty {
                    pieces.append(RawPiece(text: piece, offset: offset))
                }
                offset += (piece as NSString).length
                start = next
            }
            i = next
        }
        // 末尾无边界符的剩余文本
        if start < text.endIndex {
            let piece = String(text[start...])
            if !piece.trimmingCharacters(in: .whitespaces).isEmpty {
                pieces.append(RawPiece(text: piece, offset: offset))
            }
        }
        return pieces
    }

    private func mergeShort(_ pieces: [RawPiece]) -> [RawPiece] {
        var result: [RawPiece] = []
        var i = 0
        while i < pieces.count {
            var piece = pieces[i]
            // 如果当前句太短，且后面还有句子，合并
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
        let nsText = piece.text as NSString
        guard nsText.length > maxLength else { return [piece] }
        // 找 50 字附近最近的软边界
        var results: [RawPiece] = []
        var startIdx = piece.text.startIndex
        var offsetDelta = 0
        while startIdx < piece.text.endIndex {
            let remaining = piece.text[startIdx...]
            if (remaining as NSString).length <= maxLength {
                results.append(RawPiece(text: String(remaining), offset: piece.offset + offsetDelta))
                break
            }
            // 在 [40, maxLength] 范围内找软边界
            let scanEnd = piece.text.index(startIdx, offsetBy: min(maxLength, (remaining as NSString).length) - 1)
            var cutIdx = piece.text.index(startIdx, offsetBy: 50, limitedBy: scanEnd) ?? scanEnd
            var found = false
            while cutIdx < scanEnd {
                let ch = piece.text[cutIdx]
                if ch.unicodeScalars.contains(where: softBoundaries.contains) {
                    cutIdx = piece.text.index(after: cutIdx)
                    found = true
                    break
                }
                cutIdx = piece.text.index(after: cutIdx)
            }
            if !found { cutIdx = scanEnd }
            let sub = String(piece.text[startIdx..<cutIdx])
            results.append(RawPiece(text: sub, offset: piece.offset + offsetDelta))
            offsetDelta += (sub as NSString).length
            startIdx = cutIdx
        }
        return results
    }
}
```

- [ ] **Step 3.3：运行测试**

```bash
xcodebuild test -project IOS/Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -only-testing:LegadoTests/TTS/SentenceSplitterTests 2>&1 | grep -E "passed|failed"
```

期望：6 个测试全部 passed。

- [ ] **Step 3.4：Commit**

```bash
git add IOS/Legado/App/Features/TTS/Pipeline/SentenceSplitter.swift \
        IOS/LegadoTests/TTS/SentenceSplitterTests.swift
git commit -m "feat(tts): SentenceSplitter 章节断句（含测试）"
```

---

## Task 4：Sherpa-ONNX 集成 + Kokoro 模型下载

**Files:**
- Modify: `IOS/Legado.xcodeproj`（手动在 Xcode 中添加 XCFramework）
- Create: `IOS/Legado/App/Features/TTS/Engines/ModelManager.swift`

- [ ] **Step 4.1：下载 Sherpa-ONNX iOS XCFramework**

```bash
# 从 GitHub Releases 下载最新 iOS XCFramework
# 访问 https://github.com/k2-fsa/sherpa-onnx/releases
# 下载文件名类似：sherpa-onnx-v1.x.x-ios.tar.bz2

# 或使用最近已知可用版本（根据实际情况调整版本号）：
cd /tmp
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.11.3/sherpa-onnx-v1.11.3-ios.tar.bz2
tar xf sherpa-onnx-v1.11.3-ios.tar.bz2
ls sherpa-onnx-v1.11.3-ios/
# 应看到 SherpaOnnx.xcframework 目录
```

- [ ] **Step 4.2：在 Xcode 中添加 XCFramework**

1. 将解压得到的 `SherpaOnnx.xcframework` 复制到 `IOS/Legado/Frameworks/`
2. Xcode → 选中 Legado target → General → Frameworks, Libraries, and Embedded Content
3. 点 "+" → Add Files → 选择 `SherpaOnnx.xcframework`
4. 设置为 **Embed & Sign**
5. Build Settings → Other Linker Flags 确认无需额外设置（XCFramework 自动链接）

- [ ] **Step 4.3：下载 Kokoro 模型文件**

```bash
# 下载 kokoro-multi-lang-v1.1-int8（140MB，中英双语，103 speakers）
cd /tmp
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1.1-int8.tar.bz2
tar xf kokoro-multi-lang-v1.1-int8.tar.bz2
ls kokoro-multi-lang-v1.1-int8/
# 应看到：model.onnx  voices.json  tokens.txt  espeak-ng-data/
```

模型文件放入 App Bundle（开发阶段）：将整个 `kokoro-multi-lang-v1.1-int8/` 目录拖入 Xcode 项目，选择 **Create folder references**，添加到 Legado target。

> **注意**：生产版本应改为首次运行时按需下载到 `Documents/TTS/` 目录，避免 App 体积过大。此处开发阶段直接 Bundle 简化调试。

- [ ] **Step 4.4：创建 ModelManager.swift（模型路径管理）**

`IOS/Legado/App/Features/TTS/Engines/ModelManager.swift`:

```swift
import Foundation

/// 管理 TTS 模型文件路径，支持 Bundle（开发）和 Documents（生产下载）双路径。
struct ModelManager {

    enum Model {
        case kokoroMultiLangInt8
    }

    static func modelDir(for model: Model) -> String? {
        switch model {
        case .kokoroMultiLangInt8:
            // 先检查 Documents（生产下载路径）
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let docsPath = docs.appendingPathComponent("TTS/kokoro-multi-lang-v1.1-int8").path
            if FileManager.default.fileExists(atPath: docsPath) { return docsPath }
            // 回退到 Bundle（开发阶段）
            return Bundle.main.path(forResource: "kokoro-multi-lang-v1.1-int8", ofType: nil)
        }
    }

    static func isAvailable(_ model: Model) -> Bool {
        modelDir(for: model) != nil
    }
}
```

- [ ] **Step 4.5：编译验证（验证 XCFramework 链接正常）**

```bash
cd IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`（有 SherpaOnnx import 仍通过则 XCFramework 链接正常）

- [ ] **Step 4.6：Commit**

```bash
git add IOS/Legado/App/Features/TTS/Engines/ModelManager.swift
git commit -m "feat(tts): Sherpa-ONNX XCFramework 集成 + Kokoro 模型路径管理"
```

---

## Task 5：SherpaKokoroEngine

**Files:**
- Create: `IOS/Legado/App/Features/TTS/Engines/SherpaKokoroEngine.swift`

- [ ] **Step 5.1：实现 SherpaKokoroEngine**

`IOS/Legado/App/Features/TTS/Engines/SherpaKokoroEngine.swift`:

```swift
import Foundation
import SherpaOnnx

/// Sherpa-ONNX + Kokoro TTS 引擎封装。
/// 线程安全：synthesize() 在调用方的 Task（后台线程）上执行，不阻塞主线程。
final class SherpaKokoroEngine: TTSEngine {

    private var tts: SherpaOnnxOfflineTts?
    private(set) var isReady = false

    func warmup() async {
        guard let dir = ModelManager.modelDir(for: .kokoroMultiLangInt8) else {
            print("❌ [SherpaKokoro] 模型目录未找到")
            return
        }
        let config = makeConfig(modelDir: dir)
        tts = SherpaOnnxOfflineTts(config: config)
        isReady = tts != nil
        if isReady {
            // 预热：合成一个极短文本，让引擎完成首次 ONNX 图加载
            _ = tts?.generate(text: "你好", sid: 0, speed: 1.0)
            print("✅ [SherpaKokoro] 引擎预热完成")
        }
    }

    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk {
        guard let tts, isReady else { throw TTSError.engineNotReady }
        let speed = style.rateMultiplier   // Kokoro speed 参数直接对应 rateMultiplier
        guard let audio = tts.generate(text: text, sid: Int32(voice.speakerId), speed: speed) else {
            throw TTSError.synthesizeFailed("Kokoro generate 返回 nil，text=\(text.prefix(20))")
        }
        return AudioChunk(samples: Array(audio.samples), sampleRate: Int(audio.sampleRate))
    }

    // MARK: - Config

    private func makeConfig(modelDir: String) -> SherpaOnnxOfflineTtsConfig {
        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model:  "\(modelDir)/model.onnx",
            voices: "\(modelDir)/voices.json",
            tokens: "\(modelDir)/tokens.txt",
            dataDir: "\(modelDir)/espeak-ng-data",
            lengthScale: 1.0
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig
        )
        return sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            ruleFsts: "",
            maxNumSentences: 1,
            ruleFars: ""
        )
    }
}
```

- [ ] **Step 5.2：手动集成测试（Simulator）**

在 `LegadoApp.swift` 的 `@main struct` 的 `.task` 里临时加一段测试代码（完成后删除）：

```swift
Task {
    let engine = SherpaKokoroEngine()
    await engine.warmup()
    guard engine.isReady else { print("❌ engine not ready"); return }
    let voice = VoiceConfig(id: "test", speakerId: 0, displayName: "测试")
    if let chunk = try? await engine.synthesize(
        text: "你好，这是测试。", voice: voice, style: .normal) {
        print("✅ 合成成功，samples=\(chunk.samples.count) rate=\(chunk.sampleRate)")
    }
}
```

运行 App，查看 Console：期望看到 `✅ 合成成功，samples=XXXXX rate=24000`。

- [ ] **Step 5.3：删除测试代码**

删除 Step 5.2 添加的临时代码。

- [ ] **Step 5.4：Commit**

```bash
git add IOS/Legado/App/Features/TTS/Engines/SherpaKokoroEngine.swift
git commit -m "feat(tts): SherpaKokoroEngine Kokoro 合成引擎"
```

---

## Task 6：AudioPipeline

**Files:**
- Create: `IOS/Legado/App/Features/TTS/AudioPipeline.swift`

- [ ] **Step 6.1：实现 AudioPipeline**

`IOS/Legado/App/Features/TTS/AudioPipeline.swift`:

```swift
import AVFoundation

/// AVAudioEngine 流式播放器。
/// setup() 在初始化和每次 stop() 后调用（stop 会 reset engine，须重建连接）。
final class AudioPipeline {

    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    private let pitchEffect = AVAudioUnitTimePitch()
    private var isSetup = false

    var onSentenceComplete: ((SentenceUnit) -> Void)?

    // MARK: - Setup（stop 后须重新调用）

    func setup() throws {
        if isSetup { return }
        engine.attach(playerNode)
        engine.attach(pitchEffect)
        engine.connect(playerNode, to: pitchEffect,           format: nil)
        engine.connect(pitchEffect, to: engine.mainMixerNode, format: nil)
        try engine.start()
        isSetup = true
    }

    // MARK: - Playback

    func enqueue(chunk: AudioChunk, sentence: SentenceUnit, style: SpeakingStyle) {
        guard let buffer = makeBuffer(from: chunk) else { return }
        applyStyle(style)
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.onSentenceComplete?(sentence) }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    func pause() {
        playerNode.pause()
        // engine 保持 running，pause 后 resume 无需重新 setup
    }

    func resume() throws {
        if !engine.isRunning {
            // engine 被外部打断（如来电），需要重新 start
            try engine.start()
        }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        engine.reset()   // 清空所有已调度的 buffer
        isSetup = false  // 标记需要重新 setup
    }

    // MARK: - Private helpers

    private func makeBuffer(from chunk: AudioChunk) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(chunk.samples.count)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(chunk.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        chunk.samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData?[0].initialize(from: ptr.baseAddress!,
                                                   count: chunk.samples.count)
        }
        return buffer
    }

    private func applyStyle(_ style: SpeakingStyle) {
        pitchEffect.pitch  = style.pitchOffset * 100   // cent 单位
        pitchEffect.rate   = style.rateMultiplier
        engine.mainMixerNode.outputVolume = style.volumeMultiplier
    }
}
```

- [ ] **Step 6.2：Commit**

```bash
git add IOS/Legado/App/Features/TTS/AudioPipeline.swift
git commit -m "feat(tts): AudioPipeline AVAudioEngine 流式播放器"
```

---

## Task 7：NovellaTTSEngine（Phase 1a 版本，单一声音）

**Files:**
- Create: `IOS/Legado/App/Features/TTS/NovellaTTSEngine.swift`
- Create: `IOS/Legado/App/Resources/preset_voices.json`

- [ ] **Step 7.1：创建 preset_voices.json**

`IOS/Legado/App/Resources/preset_voices.json`:

```json
[
  {
    "id": "narrator",
    "displayName": "旁白",
    "kokoroSpeakerId": 0,
    "gender": "neutral",
    "ageGroup": "adult",
    "note": "Speaker ID 待集成后试听确认，此处为占位值 0"
  },
  {
    "id": "protagonist",
    "displayName": "男主",
    "kokoroSpeakerId": 0,
    "gender": "male",
    "ageGroup": "young",
    "note": "Speaker ID 待试听确认"
  },
  {
    "id": "heroine",
    "displayName": "女主",
    "kokoroSpeakerId": 0,
    "gender": "female",
    "ageGroup": "young",
    "note": "Speaker ID 待试听确认"
  },
  {
    "id": "elder_male",
    "displayName": "老者",
    "kokoroSpeakerId": 0,
    "gender": "male",
    "ageGroup": "elder",
    "note": "Speaker ID 待试听确认"
  },
  {
    "id": "young_female",
    "displayName": "少女",
    "kokoroSpeakerId": 0,
    "gender": "female",
    "ageGroup": "young",
    "note": "Speaker ID 待试听确认"
  },
  {
    "id": "villain",
    "displayName": "反派",
    "kokoroSpeakerId": 0,
    "gender": "male",
    "ageGroup": "adult",
    "note": "Speaker ID 待试听确认"
  },
  {
    "id": "child",
    "displayName": "孩童",
    "kokoroSpeakerId": 0,
    "gender": "neutral",
    "ageGroup": "child",
    "note": "Speaker ID 待试听确认"
  },
  {
    "id": "neutral",
    "displayName": "通用",
    "kokoroSpeakerId": 0,
    "gender": "neutral",
    "ageGroup": "adult",
    "note": "Speaker ID 待试听确认，兜底声音"
  }
]
```

- [ ] **Step 7.2：实现 NovellaTTSEngine**

`IOS/Legado/App/Features/TTS/NovellaTTSEngine.swift`:

```swift
import Foundation
import AVFoundation
import Combine
import MediaPlayer

/// 高质量 TTS 主控协调器（Phase 1a：单一声音，无角色区分）。
/// ⚠️ 不能标注 @MainActor：ONNX 推理必须在后台线程，@MainActor 会导致 UI 卡顿。
/// @Published 属性的更新统一通过 DispatchQueue.main.async 派发到主线程。
final class NovellaTTSEngine: ObservableObject, TTSProtocol {

    static let shared = NovellaTTSEngine()

    // MARK: - TTSProtocol 公开状态（主线程更新）

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var speakingRange: NSRange? = nil
    @Published private(set) var remainingSeconds: Int? = nil
    var selectedVoice: AVSpeechSynthesisVoice? = nil  // Phase 1a 不使用，兼容协议

    // MARK: - 私有状态

    private let engine    = SherpaKokoroEngine()
    private let pipeline  = AudioPipeline()
    private let normalizer = TextNormalizer()
    private let splitter   = SentenceSplitter()

    private var sentenceQueue: [SentenceUnit] = []
    private var currentIndex = 0
    private var onChapterFinish: (() -> Void)?
    private var originalText = ""          // \n\n→\n 归一化后的原始文本，用于 speakingRange 坐标
    private var currentBookName = ""
    private var currentChapterTitle = ""
    private var generationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    // 串行队列保护非主线程访问的共享状态
    private let stateQueue = DispatchQueue(label: "com.legado.novellatts.state")

    private let narratorVoice = VoiceConfig(id: "narrator", speakerId: 0, displayName: "旁白")

    private init() {
        pipeline.onSentenceComplete = { [weak self] sentence in
            self?.onSentencePlayed(sentence)
        }
        Task { await setupOnLaunch() }
    }

    private func setupOnLaunch() async {
        do {
            try pipeline.setup()
        } catch {
            print("❌ [NovellaTTS] AudioPipeline 初始化失败: \(error)")
        }
        setupAudioSession()
        setupRemoteCommandCenter()
        await engine.warmup()
    }

    // MARK: - TTSProtocol 实现

    func speak(_ text: String, bookName: String, chapterTitle: String,
               onFinish: @escaping () -> Void) {
        stopInternal()

        originalText         = text
        currentBookName      = bookName
        currentChapterTitle  = chapterTitle
        onChapterFinish      = onFinish

        // ⚡ Fix 2：SentenceSplitter 使用原始文本计算 charOffset（不经 TextNormalizer）
        // TextNormalizer 只在每句送入 TTS 前应用，不改变偏移坐标
        sentenceQueue = splitter.split(text, baseOffset: 0)
        currentIndex  = 0

        DispatchQueue.main.async {
            self.isPlaying  = true
            self.isSpeaking = true
        }
        updateNowPlayingInfo()
        startGenerationPipeline()
    }

    func pause() {
        pipeline.pause()
        generationTask?.cancel()
        DispatchQueue.main.async {
            self.isPlaying  = false
            self.isSpeaking = false
        }
    }

    func resume() {
        do {
            try pipeline.resume()
        } catch {
            print("❌ [NovellaTTS] AudioPipeline resume 失败: \(error)")
            return
        }
        DispatchQueue.main.async {
            self.isPlaying  = true
            self.isSpeaking = true
        }
        startGenerationPipeline()
    }

    func stop() {
        cancelTimer()
        stopInternal()
    }

    private func stopInternal() {
        generationTask?.cancel()
        generationTask = nil
        pipeline.stop()
        sentenceQueue   = []
        currentIndex    = 0
        onChapterFinish = nil
        DispatchQueue.main.async {
            self.isPlaying       = false
            self.isSpeaking      = false
            self.speakingRange   = nil
            self.remainingSeconds = nil
        }
    }

    func restartForSettingChange() {
        guard isPlaying || isSpeaking, !originalText.isEmpty else { return }
        let text  = originalText
        let book  = currentBookName
        let title = currentChapterTitle
        let cb    = onChapterFinish ?? {}
        speak(text, bookName: book, chapterTitle: title, onFinish: cb)
    }

    func startTimer(minutes: Int) {
        timerTask?.cancel()
        let seconds = minutes * 60
        DispatchQueue.main.async { self.remainingSeconds = seconds }
        timerTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
                DispatchQueue.main.async { self?.remainingSeconds = remaining }
            }
            self?.stop()
        }
    }

    func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
        DispatchQueue.main.async { self.remainingSeconds = nil }
    }

    // MARK: - 流水线

    private func startGenerationPipeline() {
        generationTask?.cancel()

        // ⚡ Fix 1：Task.detached 确保 ONNX 推理在后台线程，不阻塞 MainActor
        generationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // 预生成当前句 + 下一句（并发 2 句缓冲）
            let startIdx  = self.currentIndex
            let queueSnap = self.sentenceQueue  // 值拷贝，线程安全
            let endIdx    = min(startIdx + 2, queueSnap.count)

            for idx in startIdx..<endIdx {
                guard !Task.isCancelled else { return }
                let sentence = queueSnap[idx]

                // ⚡ Fix 2：TextNormalizer 仅在此处对送入 TTS 的文本应用
                // sentence.charOffset 基于原始文本，保持与 pageStartOffset 坐标一致
                let normalizedForTTS = self.normalizer.normalize(sentence.text)

                do {
                    let chunk = try await self.engine.synthesize(
                        text: normalizedForTTS,
                        voice: self.narratorVoice,
                        style: .normal
                    )
                    // 切回主线程入队播放
                    await MainActor.run {
                        self.pipeline.enqueue(chunk: chunk, sentence: sentence, style: .normal)
                    }
                } catch {
                    print("❌ [NovellaTTS] 合成失败 idx=\(idx): \(error)")
                }
            }
        }
    }

    private func onSentencePlayed(_ sentence: SentenceUnit) {
        DispatchQueue.main.async {
            self.speakingRange = NSRange(location: sentence.charOffset, length: sentence.charLength)
        }
        currentIndex += 1

        if currentIndex >= sentenceQueue.count {
            DispatchQueue.main.async {
                self.isPlaying    = false
                self.isSpeaking   = false
                self.speakingRange = nil
            }
            onChapterFinish?()
        } else {
            startGenerationPipeline()
        }
    }

    // MARK: - Audio Session + Now Playing

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget  { [unowned self] _ in resume(); return .success }
        cc.pauseCommand.addTarget { [unowned self] _ in pause();  return .success }
        cc.togglePlayPauseCommand.addTarget { [unowned self] _ in
            isPlaying ? pause() : resume(); return .success
        }
    }

    private func updateNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:             currentChapterTitle,
            MPMediaItemPropertyArtist:            currentBookName,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }
}
```

- [ ] **Step 7.3：Commit**

```bash
git add IOS/Legado/App/Features/TTS/NovellaTTSEngine.swift \
        IOS/Legado/App/Resources/preset_voices.json
git commit -m "feat(tts): NovellaTTSEngine Phase 1a 主控协调器（单声音流式朗读）"
```

---

## Task 8：ReaderViewModel + ReaderView 接入

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/ViewModels/ReaderViewModel.swift`
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`
- Modify: `IOS/Legado/App/Features/Reading/Models/ReaderSettings.swift`

- [ ] **Step 8.1：在 ReaderViewModel 添加 `ttsState` 转发属性**

打开 `ReaderViewModel.swift`，在 `@Published var isTTSEnabled` 附近添加（⚡ Fix 3：统一转发 TTS 状态，ReaderMenuView 不再直接引用具体引擎）：

```swift
// 在现有 @Published 属性区添加
@Published var ttsIsPlaying: Bool      = false
@Published var ttsRemainingSeconds: Int? = nil
```

修改 `ttsManager` 声明：

```swift
// 修改前
let ttsManager = TTSManager.shared

// 修改后
var ttsManager: any TTSProtocol = TTSManager.shared
```

在 `init` 末尾调用新增的绑定方法：

```swift
init(book: Book) {
    self.book = book
    self.currentChapterIndex = book.durChapterIndex
    if ReaderSettings.shared.useNovellaTTS && ModelManager.isAvailable(.kokoroMultiLangInt8) {
        ttsManager = NovellaTTSEngine.shared
    }
    subscribeToTTSSpeakingRange()
    bindTTSStateForwarding()   // 新增
}
```

新增 `bindTTSStateForwarding()` 方法：

```swift
/// 将活跃 TTS 引擎的 isPlaying/remainingSeconds 转发到 ReaderViewModel 的
/// @Published 属性，让 ReaderMenuView 通过 @ObservedObject viewModel 接收更新。
private func bindTTSStateForwarding() {
    if let novella = ttsManager as? NovellaTTSEngine {
        novella.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$ttsIsPlaying)
        novella.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .assign(to: &$ttsRemainingSeconds)
    } else if let system = ttsManager as? TTSManager {
        system.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$ttsIsPlaying)
        system.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .assign(to: &$ttsRemainingSeconds)
    }
}
```

修改 `subscribeToTTSSpeakingRange`，兼容两种引擎：

```swift
private func subscribeToTTSSpeakingRange() {
    if let novella = ttsManager as? NovellaTTSEngine {
        novella.$speakingRange
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in self?.updatePageForTTSRange(range) }
            .store(in: &cancellables)
    } else if let system = ttsManager as? TTSManager {
        system.$speakingRange
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in self?.updatePageForTTSRange(range) }
            .store(in: &cancellables)
    }
}
```

- [ ] **Step 8.2：更新 ReaderMenuView 使用 `viewModel.ttsIsPlaying`**

打开 `ReaderView.swift`，找到 `ReaderMenuView` 结构体：

```swift
// 修改前
@ObservedObject private var ttsManager = TTSManager.shared
```

删除该行（`ReaderMenuView` 不再直接引用引擎）。

在 `ttsPanelView` 里，将所有 `ttsManager.isPlaying` 替换为 `viewModel.ttsIsPlaying`，将 `ttsManager.remainingSeconds` 替换为 `viewModel.ttsRemainingSeconds`：

```swift
// 暂停/继续按钮（修改后）
Button {
    if viewModel.ttsIsPlaying {
        viewModel.ttsManager.pause()
    } else {
        viewModel.ttsManager.resume()
    }
} label: {
    HStack {
        Image(systemName: viewModel.ttsIsPlaying ? "pause.circle.fill" : "play.circle.fill")
        Text(viewModel.ttsIsPlaying ? "暂停" : "继续")
    }
    ...
}

// 定时倒计时显示（修改后）
if let remaining = viewModel.ttsRemainingSeconds {
    Text(formatRemaining(remaining))
        .font(.caption2).foregroundColor(.secondary)
        .monospacedDigit()
}
```

其余直接调用 `ttsManager` 方法（如 `pause()`, `resume()`, `startTimer()` 等）改为通过 `viewModel.ttsManager` 调用：

```swift
// 示例：退出朗读按钮
Button(role: .destructive) {
    viewModel.stopTTS()
    ttsTimerSelection = nil
} label: { ... }

// timerButton 中
ttsManager.startTimer(minutes: min)  →  viewModel.ttsManager.startTimer(minutes: min)
ttsManager.cancelTimer()             →  viewModel.ttsManager.cancelTimer()
```

- [ ] **Step 8.3：ReaderSettings 添加 TTS 引擎切换开关**

在 `ReaderSettings.swift` 的"高级"区域添加：

```swift
@AppStorage("reader.useNovellaTTS") var useNovellaTTS: Bool = false
```

在 `ReadingPreferencesView` 的"高级"Section 追加（紧跟在 `Toggle("音量键翻页", ...)` 之后）：

```swift
if ModelManager.isAvailable(.kokoroMultiLangInt8) {
    Toggle("高质量TTS（Kokoro）", isOn: $settings.useNovellaTTS)
}
```

- [ ] **Step 8.4：编译验证**

```bash
cd IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 8.5：Commit**

```bash
git add IOS/Legado/App/Features/Reading/ViewModels/ReaderViewModel.swift \
        IOS/Legado/App/Features/Reading/Views/ReaderView.swift \
        IOS/Legado/App/Features/Reading/Models/ReaderSettings.swift
git commit -m "feat(tts): ReaderViewModel ttsState 转发 + ReaderMenuView 解耦具体引擎"
```

---

## Task 9：Speaker ID 试听 + preset_voices.json 填写

**Files:**
- Create: `IOS/Legado/App/Features/TTS/Tools/SpeakerAuditionHelper.swift`（开发工具，不打包）
- Modify: `IOS/Legado/App/Resources/preset_voices.json`

- [ ] **Step 9.1：创建试听辅助工具**

`IOS/Legado/App/Features/TTS/Tools/SpeakerAuditionHelper.swift`（Xcode 中标记为不参与 Release target）：

```swift
#if DEBUG
import Foundation

/// 在开发阶段用于批量生成所有 Kokoro Speaker 的试听样本。
/// 使用方式：在 AppDelegate/App 的 DEBUG 路径下调用 generateAll()，
/// 输出音频文件到 Documents/audition/ 供人工试听。
final class SpeakerAuditionHelper {

    static func generateAll() async {
        guard let dir = ModelManager.modelDir(for: .kokoroMultiLangInt8) else { return }
        let engine = SherpaKokoroEngine()
        await engine.warmup()
        guard engine.isReady else { print("引擎未就绪"); return }

        let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audition")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let sampleText = "林峰抬起头，看向远方的天际，心中涌起一阵难以言说的情绪。"
        let voiceConfig = VoiceConfig(id: "test", speakerId: 0, displayName: "test")

        for speakerId in 0..<103 {
            let voice = VoiceConfig(id: "\(speakerId)", speakerId: speakerId, displayName: "\(speakerId)")
            if let chunk = try? await engine.synthesize(text: sampleText, voice: voice, style: .normal) {
                let wavURL = outputDir.appendingPathComponent("speaker_\(String(format: "%03d", speakerId)).wav")
                writeWAV(samples: chunk.samples, sampleRate: chunk.sampleRate, to: wavURL)
                print("✅ Speaker \(speakerId) → \(wavURL.lastPathComponent)")
            }
        }
        print("🎵 试听文件已生成到 Documents/audition/，共 103 个")
    }

    private static func writeWAV(samples: [Float], sampleRate: Int, to url: URL) {
        // 44 字节 WAV 头 + PCM int16 数据
        let numSamples = samples.count
        let dataSize = numSamples * 2
        var header = Data()
        func append(_ v: UInt32) { var x = v.littleEndian; header.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) }) }
        func append16(_ v: UInt16) { var x = v.littleEndian; header.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) }) }
        header.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + dataSize))
        header.append(contentsOf: "WAVEfmt ".utf8)
        append(16); append16(1); append16(1)
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append16(2); append16(16)
        header.append(contentsOf: "data".utf8)
        append(UInt32(dataSize))
        var pcm = Data(capacity: dataSize)
        for s in samples {
            var v = Int16(max(-32768, min(32767, Int(s * 32767))))
            pcm.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
        }
        try? (header + pcm).write(to: url)
    }
}
#endif
```

- [ ] **Step 9.2：触发试听生成**

在 `LegadoApp.swift` 中临时添加（`#if DEBUG`）：

```swift
#if DEBUG
.task {
    await SpeakerAuditionHelper.generateAll()
}
#endif
```

运行 App，等待 Console 输出 `共 103 个`，然后用 Xcode 的 Device File Manager 或 `simctl` 取出音频：

```bash
# 从模拟器取出试听文件
xcrun simctl get_app_container 962E405B-C2DC-463C-889D-FC51D1438E83 com.legado.app data
# 输出路径类似 ~/Library/Developer/.../data
# 进入该路径下的 Documents/audition/ 目录用 QuickTime 逐一试听
```

- [ ] **Step 9.3：人工试听，填写 preset_voices.json**

试听 103 个 speaker 后，将每个角色槽位对应的 Speaker ID 填入 `preset_voices.json`：

```json
{ "id": "narrator",    "kokoroSpeakerId": 12  }  ← 替换为实际试听后确认的编号
{ "id": "protagonist", "kokoroSpeakerId": 7   }
...
```

- [ ] **Step 9.4：删除试听触发代码**

删除 Step 9.2 在 `LegadoApp.swift` 添加的临时代码。

- [ ] **Step 9.5：Commit**

```bash
git add IOS/Legado/App/Features/TTS/Tools/SpeakerAuditionHelper.swift \
        IOS/Legado/App/Resources/preset_voices.json
git commit -m "feat(tts): Speaker 试听工具 + preset_voices.json 填写确认 Speaker ID"
```

---

## Task 10：端到端验收测试

- [ ] **Step 10.1：打开一本书，进入朗读**

1. 启动 App，打开任意一本已加载的书
2. 进入阅读界面，点击屏幕中间打开菜单
3. 在设置里**开启"高质量TTS（Kokoro）"**
4. 重新进入阅读，点击"朗读"按钮

预期：
- 约 500ms 内开始听到声音（Kokoro 首句合成 + 播放）
- Console 无 `❌` 错误
- 朗读时文本出现橙色高亮（speakingRange 回调正常）
- 翻页跟随朗读进度自动推进

- [ ] **Step 10.2：验证暂停/继续**

朗读中，打开菜单 → 点击"暂停"→ 声音停止，按钮变为"继续"  
点击"继续"→ 从中断处继续朗读

- [ ] **Step 10.3：验证章节结束自动连读**

等待当前章节朗读完毕，确认 App 自动切换到下一章并继续朗读。

- [ ] **Step 10.4：验证 TextNormalizer 效果**

找到含数字/日期的章节（如"第2024年"、"花了300元"），确认朗读时发音为汉字而非数字英文拼读。

- [ ] **Step 10.5：最终 Commit**

```bash
git add .
git commit -m "feat(tts): Phase 1a 验收通过 — Kokoro 流式朗读全流程可用"
```

---

## 验收标准

| 项目 | 标准 |
|------|------|
| 首字延迟 | ≤ 800ms（模拟器），≤ 500ms（真机） |
| TextNormalizer | 全部 10 个单元测试通过 |
| SentenceSplitter | 全部 6 个单元测试通过 |
| 朗读高亮 | speakingRange 与文字同步，橙色高亮可见 |
| 自动翻页 | 朗读推进到下一页时页面自动翻转 |
| 暂停/继续 | 状态正确，按钮文字同步 |
| 章节连读 | 章节结束后自动播放下一章 |
| 系统TTS回退 | 关闭"高质量TTS"后，AVSpeechSynthesizer 正常工作 |
