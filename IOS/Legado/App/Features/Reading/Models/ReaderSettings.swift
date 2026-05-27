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
    static let allThemes = [parchment, dark, eyeCare, fresh]
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
        ReaderTheme.allThemes.first { $0.id == themeId } ?? .parchment
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
}
