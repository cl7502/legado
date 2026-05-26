import SwiftUI
import Combine

/// 书源列表业务逻辑
@MainActor
class BookSourceViewModel: ObservableObject {
    @Published var sources: [BookSource] = []
    @Published var isLoading = false
    @Published var searchText = ""
    
    private let db = DatabaseManager.shared
    
    /// 加载所有书源
    func loadSources() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.sources = try await db.getAllBookSources()
        } catch {
            print("❌ [DB Error]: Failed to load sources: \(error)")
        }
    }
    
    /// 切换启用状态
    func toggleEnabled(_ source: BookSource) async {
        var updated = source
        updated.enabled.toggle()
        try? await db.saveBookSources([updated])
        await loadSources()
    }
    
    /// 从远程 URL 下载并导入书源 (P2-D)
    func importFromURL(_ urlString: String) async -> Int {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              urlString.lowercased().hasPrefix("http") else {
            print("❌ [Import Error]: Invalid URL — \(urlString)")
            return 0
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let jsonString = String(data: data, encoding: .utf8) else { return 0 }
            let newSources = BookSourceImporter().parse(jsonString)
            guard !newSources.isEmpty else { return 0 }
            try await db.saveBookSources(newSources)
            await loadSources()
            return newSources.count
        } catch {
            print("❌ [Import Error]: \(error)")
            return 0
        }
    }

    /// 批量导入书源 (支持 JSON 字符串)
    func importFromJSON(_ jsonString: String) async -> Int {
        let importer = BookSourceImporter()
        let newSources = importer.parse(jsonString)
        guard !newSources.isEmpty else { return 0 }
        
        do {
            try await db.saveBookSources(newSources)
            await loadSources()
            return newSources.count
        } catch {
            print("❌ [Import Error]: \(error)")
            return 0
        }
    }
    
    /// 删除书源
    func deleteSource(_ source: BookSource) async {
        try? await db.deleteBookSource(source)
        await loadSources()
    }

    /// 保存（新建或更新）书源
    func saveSource(_ source: BookSource) async {
        do {
            try await db.saveBookSources([source])
            await loadSources()
        } catch {
            print("❌ [BookSourceVM] saveSource: \(error)")
        }
    }
}

/// 书源导入解析器 — 支持 Android 嵌套 JSON 格式
class BookSourceImporter {
    func parse(_ jsonString: String) -> [BookSource] {
        guard let data = jsonString.data(using: .utf8) else {
            print("❌ [Import] UTF-8 encode failed")
            return []
        }

        // 解析顶层 JSON 结构
        let rawObjects: [[String: Any]]
        do {
            if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                rawObjects = arr
            } else if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rawObjects = [obj]
            } else {
                print("❌ [Import] Unexpected JSON root type (expected Array or Object)")
                return []
            }
        } catch {
            print("❌ [Import] JSON parse error: \(error)")
            return []
        }

        // 将 Android 嵌套格式展平
        let flattened = rawObjects.map { flattenAndroidFormat($0) }
        guard let flatData = try? JSONSerialization.data(withJSONObject: flattened) else {
            print("❌ [Import] Re-encode flattened objects failed")
            return []
        }

        let decoder = JSONDecoder()

        // 先尝试整批解码（快速路径）
        if let sources = try? decoder.decode([BookSource].self, from: flatData), !sources.isEmpty {
            print("✅ [Import] Batch decode OK: \(sources.count) sources")
            return sources.filter { !$0.bookSourceUrl.isEmpty }
        }

        // 整批失败 → 逐条解码，跳过有问题的条目
        print("⚠️ [Import] Batch decode failed, trying item-by-item...")
        var results: [BookSource] = []
        for (i, flat) in flattened.enumerated() {
            guard let itemData = try? JSONSerialization.data(withJSONObject: flat) else { continue }
            do {
                let source = try decoder.decode(BookSource.self, from: itemData)
                if !source.bookSourceUrl.isEmpty {
                    results.append(source)
                }
            } catch {
                let name = flat["bookSourceName"] as? String ?? "?"
                print("⚠️ [Import] Item \(i) '\(name)' failed: \(error)")
            }
        }
        print("✅ [Import] Item-by-item result: \(results.count)/\(flattened.count) sources")
        return results
    }

    // 将 Android BookSource JSON（嵌套规则对象）转换为 iOS 扁平字段
    private func flattenAndroidFormat(_ obj: [String: Any]) -> [String: Any] {
        var flat = obj

        // ruleSearch → ruleSearch* 扁平字段
        if let rs = obj["ruleSearch"] as? [String: Any] {
            flat["ruleSearchList"]        = rs["bookList"]
            flat["ruleSearchName"]        = rs["name"]
            flat["ruleSearchAuthor"]      = rs["author"]
            flat["ruleSearchKind"]        = rs["kind"]
            flat["ruleSearchLastChapter"] = rs["lastChapter"]
            flat["ruleSearchCoverUrl"]    = rs["coverUrl"]
            flat["ruleSearchNoteUrl"]     = rs["bookUrl"]
            flat["ruleSearchIntro"]       = rs["intro"]
            flat["ruleSearchUpdateTime"]  = rs["updateTime"]
            flat["ruleSearchWordCount"]   = rs["wordCount"]
            flat.removeValue(forKey: "ruleSearch")
        }

        // ruleBookInfo → ruleBook* 扁平字段
        if let rbi = obj["ruleBookInfo"] as? [String: Any] {
            flat["ruleBookInfoInit"]    = rbi["init"]
            flat["ruleBookName"]        = rbi["name"]
            flat["ruleBookAuthor"]      = rbi["author"]
            flat["ruleBookIntro"]       = rbi["intro"]
            flat["ruleBookKind"]        = rbi["kind"]
            flat["ruleBookLastChapter"] = rbi["lastChapter"]
            flat["ruleBookCoverUrl"]    = rbi["coverUrl"]
            flat["ruleTocUrl"]          = rbi["tocUrl"]
            flat.removeValue(forKey: "ruleBookInfo")
        }

        // ruleToc → ruleToc*/ruleChapter* 扁平字段
        if let toc = obj["ruleToc"] as? [String: Any] {
            flat["ruleTocList"]           = toc["chapterList"]
            flat["ruleChapterName"]       = toc["chapterName"]
            flat["ruleChapterUrl"]        = toc["chapterUrl"]
            flat["ruleChapterVip"]        = toc["isVolume"]    // isVolume = vip chapter marker
            flat["ruleTocNextUrl"]        = toc["nextTocUrl"]
            flat["ruleChapterUpdateTime"] = toc["updateTime"]
            flat["ruleTocPreUpdateJs"]    = toc["preUpdateJs"]
            flat["ruleTocFormatJs"]       = toc["formatJs"]
            flat.removeValue(forKey: "ruleToc")
        }

        // ruleContent: 可能是嵌套对象或直接字符串
        // IMPORTANT: remove the nested object key and set flattened string fields
        if let contentObj = obj["ruleContent"] as? [String: Any] {
            flat.removeValue(forKey: "ruleContent")       // remove nested object
            flat["ruleContent"]        = contentObj["content"]        // string field
            flat["ruleContentNextUrl"] = contentObj["nextContentUrl"]
            flat["ruleContentReplace"] = contentObj["replaceRegex"]
        }
        // 若 ruleContent 已是字符串则保持不变

        // ruleExplore → ruleExplore* 扁平字段
        if let ex = obj["ruleExplore"] as? [String: Any] {
            flat["ruleExploreList"]     = ex["bookList"]
            flat["ruleExploreName"]     = ex["name"]
            flat["ruleExploreAuthor"]   = ex["author"]
            flat["ruleExploreKind"]     = ex["kind"]
            flat["ruleExploreCoverUrl"] = ex["coverUrl"]
            flat["ruleExploreNoteUrl"]  = ex["bookUrl"]
            flat.removeValue(forKey: "ruleExplore")
        }

        return flat
    }
}
