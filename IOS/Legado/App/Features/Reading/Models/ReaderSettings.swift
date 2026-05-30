import SwiftUI

struct ReaderTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let backgroundColor: Color
    let textColor: Color
    let uiAccentColor: Color

    static let parchment = ReaderTheme(
        id: "parchment", name: "羊皮纸",
        backgroundColor: Color(red: 0.93, green: 0.87, blue: 0.76),
        textColor: Color(red: 0.20, green: 0.16, blue: 0.10),
        uiAccentColor: .brown
    )
    static let dark = ReaderTheme(
        id: "dark", name: "深色",
        backgroundColor: Color(red: 0.12, green: 0.12, blue: 0.12),
        textColor: Color(red: 0.70, green: 0.70, blue: 0.70),
        uiAccentColor: .blue
    )
    static let eyeCare = ReaderTheme(
        id: "eyeCare", name: "护眼",
        backgroundColor: Color(red: 0.78, green: 0.89, blue: 0.78),
        textColor: Color(red: 0.10, green: 0.25, blue: 0.10),
        uiAccentColor: .green
    )
    static let fresh = ReaderTheme(
        id: "fresh", name: "清新",
        backgroundColor: Color(red: 0.85, green: 0.93, blue: 0.96),
        textColor: Color(red: 0.12, green: 0.22, blue: 0.32),
        uiAccentColor: .cyan
    )
    static let builtinThemes: [ReaderTheme] = [parchment, dark, eyeCare, fresh]

    /// 自定义主题（颜色运行时从 ReaderSettings 读取）
    static func customTheme() -> ReaderTheme {
        let s = ReaderSettings.shared
        return ReaderTheme(
            id: "custom",
            name: "自定义",
            backgroundColor: s.customBgColor,
            textColor: s.customTextColor,
            uiAccentColor: .orange
        )
    }

    /// 含自定义主题的完整列表（调用时获取最新颜色）
    static func allThemes() -> [ReaderTheme] {
        builtinThemes + [customTheme()]
    }
}

/// 翻页模式
enum PageMode: String, CaseIterable {
    case page   = "翻页"
    case scroll = "滚动"
}

/// 阅读器持久化设置（对标 Android ReadStyleDialog + MoreConfigDialog）
class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    // MARK: - 排版
    @AppStorage("reader.fontSize")        private var _fontSize:        Double = 18
    @AppStorage("reader.lineSpacing")     private var _lineSpacing:     Double = 8
    @AppStorage("reader.letterSpacing")   private var _letterSpacing:   Double = 0   // 字间距
    @AppStorage("reader.paragraphSpacing") private var _paragraphSpacing: Double = 12 // 段间距
    @AppStorage("reader.sideMargin")      private var _sideMargin:      Double = 20
    @AppStorage("reader.topMargin")       private var _topMargin:       Double = 40
    @AppStorage("reader.bottomMargin")    private var _bottomMargin:    Double = 40

    var fontSize:          CGFloat { get { CGFloat(_fontSize) }          set { _fontSize          = Double(newValue) } }
    var lineSpacing:       CGFloat { get { CGFloat(_lineSpacing) }       set { _lineSpacing       = Double(newValue) } }
    var letterSpacing:     CGFloat { get { CGFloat(_letterSpacing) }     set { _letterSpacing     = Double(newValue) } }
    var paragraphSpacing:  CGFloat { get { CGFloat(_paragraphSpacing) }  set { _paragraphSpacing  = Double(newValue) } }
    var sideMargin:        CGFloat { get { CGFloat(_sideMargin) }        set { _sideMargin        = Double(newValue) } }
    var topMargin:         CGFloat { get { CGFloat(_topMargin) }         set { _topMargin         = Double(newValue) } }
    var bottomMargin:      CGFloat { get { CGFloat(_bottomMargin) }      set { _bottomMargin      = Double(newValue) } }

    // MARK: - 主题
    @AppStorage("reader.themeId") var themeId: String = "parchment"

    var currentTheme: ReaderTheme {
        let base = ReaderTheme.allThemes().first { $0.id == themeId } ?? .parchment
        guard let override = textColorOverride else { return base }
        // 文字颜色全局覆盖：保留背景色，只替换文字色
        return ReaderTheme(id: base.id, name: base.name,
                           backgroundColor: base.backgroundColor,
                           textColor: override,
                           uiAccentColor: base.uiAccentColor)
    }

    // MARK: - 翻页模式
    @AppStorage("reader.pageMode") private var _pageMode: String = PageMode.page.rawValue
    var pageMode: PageMode {
        get { PageMode(rawValue: _pageMode) ?? .page }
        set { _pageMode = newValue.rawValue }
    }

    // MARK: - 高级
    @AppStorage("reader.keepScreenOn")       var keepScreenOn:          Bool   = true
    @AppStorage("reader.showHeaderTime")     var showHeaderTime:        Bool   = true
    @AppStorage("reader.showHeaderProgress") var showHeaderProgress:    Bool   = true
    @AppStorage("reader.showHeaderBattery")  var showHeaderBattery:     Bool   = true
    @AppStorage("reader.useTraditionalChinese") var useTraditionalChinese: Bool = false
    // B2修复：记住夜间切换前的主题，切回白天时还原
    @AppStorage("reader.preNightThemeId")    var preNightThemeId:       String = "parchment"

    // MARK: - 缓存
    @AppStorage("reader.prefetchCount") var prefetchCount: Int = 10  // 后台预缓存章节数
    @AppStorage("reader.ttsRate")  private var _ttsRate:  Double = 1.0
    @AppStorage("reader.ttsPitch") private var _ttsPitch: Double = 1.0

    var ttsRate:  Float { get { Float(_ttsRate) }  set { _ttsRate  = Double(newValue) } }
    var ttsPitch: Float { get { Float(_ttsPitch) } set { _ttsPitch = Double(newValue) } }

    // MARK: - 自定义主题颜色（hex string 持久化）
    @AppStorage("reader.customBgColorHex")   var customBgColorHex:   String = "#F5E6C8"
    @AppStorage("reader.customTextColorHex") var customTextColorHex: String = "#2C1810"
    @AppStorage("reader.ttsVoiceIdentifier") var ttsVoiceIdentifier: String = ""

    /// 文字颜色覆盖（空字符串 = 使用主题默认色）
    @AppStorage("reader.textColorOverrideHex") var textColorOverrideHex: String = ""

    /// 音量键翻页开关
    @AppStorage("reader.volumePageTurn") var volumePageTurn: Bool = false

    /// 自定义背景色（从 hex 读写）
    var customBgColor: Color {
        get { Color(hex: customBgColorHex) ?? Color(red: 0.96, green: 0.90, blue: 0.78) }
        set { customBgColorHex = newValue.toHex() ?? customBgColorHex }
    }

    /// 自定义文字色（仅 custom 主题使用）
    var customTextColor: Color {
        get { Color(hex: customTextColorHex) ?? Color(red: 0.17, green: 0.09, blue: 0.06) }
        set { customTextColorHex = newValue.toHex() ?? customTextColorHex }
    }

    /// 文字颜色全局覆盖（非空时覆盖所有主题的文字色）
    var textColorOverride: Color? {
        get { Color(hex: textColorOverrideHex) }
        set {
            if let c = newValue { textColorOverrideHex = c.toHex() ?? "" }
            else { textColorOverrideHex = "" }
        }
    }
}

// MARK: - Color hex 互转工具

extension Color {
    /// 从 "#RRGGBB" 字符串构造 Color
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }

    /// 转换为 "#RRGGBB" 字符串（使用 getRed 避免灰阶色空间 components 越界，IM-07）
    func toHex() -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
