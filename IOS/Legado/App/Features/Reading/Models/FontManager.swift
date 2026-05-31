import Foundation
import CoreText
import UIKit

/// 管理用户从外部导入的自定义字体（TTF/OTF）
///
/// 字体文件持久化存储在 Documents/fonts/；
/// 每次初始化时重新向 CoreText 注册，保证跨启动可用。
final class FontManager: ObservableObject {
    static let shared = FontManager()

    struct FontEntry: Identifiable, Equatable {
        let id = UUID()
        let psName: String      // PostScript 名称（用于 UIFont(name:size:)）
        let displayName: String // 显示名称（如 "霞鹜文楷"）
        let fileName: String    // 文件名（如 "LXGW-Regular.ttf"）
    }

    @Published private(set) var importedFonts: [FontEntry] = []

    private var fontsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("fonts", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        reload()
    }

    /// 扫描 fonts/ 目录并向 CoreText 注册所有字体
    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: fontsDir, includingPropertiesForKeys: nil)) ?? []
        importedFonts = urls
            .filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            .compactMap { register(at: $0) }
    }

    /// 将 sourceURL 对应字体文件复制到 fonts/ 目录并注册；返回注册信息
    @discardableResult
    func importFont(from sourceURL: URL) -> FontEntry? {
        let dest = fontsDir.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            print("❌ [FontManager] 复制字体失败: \(error)")
            return nil
        }
        guard let entry = register(at: dest) else { return nil }
        if !importedFonts.contains(where: { $0.psName == entry.psName }) {
            DispatchQueue.main.async { self.importedFonts.append(entry) }
        }
        return entry
    }

    /// 删除已导入字体
    func removeFont(_ entry: FontEntry) {
        let url = fontsDir.appendingPathComponent(entry.fileName)
        try? FileManager.default.removeItem(at: url)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        DispatchQueue.main.async {
            self.importedFonts.removeAll { $0.psName == entry.psName }
        }
    }

    func font(named psName: String, size: CGFloat) -> UIFont {
        UIFont(name: psName, size: size) ?? UIFont.systemFont(ofSize: size)
    }

    // MARK: - Private

    private func register(at url: URL) -> FontEntry? {
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let desc = descs.first else { return nil }
        guard let psName = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String,
              !psName.isEmpty else { return nil }
        let displayName = (CTFontDescriptorCopyAttribute(desc, kCTFontDisplayNameAttribute) as? String) ?? psName
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return FontEntry(psName: psName, displayName: displayName, fileName: url.lastPathComponent)
    }
}
