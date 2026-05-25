import SwiftUI

/// 阅读器主题定义
struct ReaderTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let backgroundColor: Color
    let textColor: Color
    let uiAccentColor: Color
    
    static let parchment = ReaderTheme(
        id: "parchment",
        name: "羊皮纸",
        backgroundColor: Color(red: 0.93, green: 0.87, blue: 0.76),
        textColor: Color(red: 0.20, green: 0.16, blue: 0.10),
        uiAccentColor: .brown
    )
    
    static let dark = ReaderTheme(
        id: "dark",
        name: "深色",
        backgroundColor: Color(red: 0.12, green: 0.12, blue: 0.12),
        textColor: Color(red: 0.70, green: 0.70, blue: 0.70),
        uiAccentColor: .blue
    )
    
    static let eyeCare = ReaderTheme(
        id: "eyeCare",
        name: "护眼",
        backgroundColor: Color(red: 0.78, green: 0.89, blue: 0.78),
        textColor: Color(red: 0.10, green: 0.25, blue: 0.10),
        uiAccentColor: .green
    )
    
    static let fresh = ReaderTheme(
        id: "fresh",
        name: "清新",
        backgroundColor: Color(red: 0.85, green: 0.93, blue: 0.96),
        textColor: Color(red: 0.12, green: 0.22, blue: 0.32),
        uiAccentColor: .cyan
    )
    
    static let allThemes = [parchment, dark, eyeCare, fresh]
}

/// 阅读器持久化设置
class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    // @AppStorage 不支持 CGFloat，改用 Double 存储，读取时转换
    @AppStorage("reader.fontSize")    private var _fontSize: Double = 18
    @AppStorage("reader.lineSpacing") private var _lineSpacing: Double = 8
    @AppStorage("reader.sideMargin")  private var _sideMargin: Double = 20
    @AppStorage("reader.themeId")     var themeId: String = "parchment"

    var fontSize:    CGFloat { get { CGFloat(_fontSize) }    set { _fontSize    = Double(newValue) } }
    var lineSpacing: CGFloat { get { CGFloat(_lineSpacing) } set { _lineSpacing = Double(newValue) } }
    var sideMargin:  CGFloat { get { CGFloat(_sideMargin) }  set { _sideMargin  = Double(newValue) } }

    var currentTheme: ReaderTheme {
        ReaderTheme.allThemes.first { $0.id == themeId } ?? .parchment
    }
}
