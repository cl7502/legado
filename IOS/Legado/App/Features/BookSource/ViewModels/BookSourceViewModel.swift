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
    /// Returns (count, errorMessage). errorMessage is empty on success.
    func importFromURL(_ urlString: String) async -> (Int, String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, "URL 不能为空") }
        guard trimmed.lowercased().hasPrefix("http") else { return (0, "URL 必须以 http 或 https 开头") }
        guard let url = URL(string: trimmed) else { return (0, "URL 格式无效：\(trimmed)") }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 0 || (200..<300).contains(statusCode) else {
                return (0, "服务器返回错误：HTTP \(statusCode)")
            }
            guard !data.isEmpty else { return (0, "服务器返回空数据") }

            // Use EncodingHelper to handle GBK/GB18030 responses from Chinese servers
            guard let jsonString = EncodingHelper.shared.decode(data) else {
                return (0, "无法解码服务器响应（非 UTF-8/GBK 编码）")
            }

            let (count, error) = importFromJSONString(jsonString)
            if count > 0 {
                try await db.saveBookSources(BookSourceImporter().parse(jsonString))
                await loadSources()
                return (count, "")
            }
            return (0, error.isEmpty ? "JSON 解析成功但未找到有效书源" : error)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("App Transport Security") || msg.contains("cleartext") {
                return (0, "网络被 ATS 拦截（HTTP 链接）：\(msg)")
            }
            return (0, "网络请求失败：\(msg)")
        }
    }

    /// 批量导入书源 (支持 JSON 字符串)
    /// Returns (count, errorMessage). errorMessage is empty on success.
    func importFromJSON(_ jsonString: String) async -> (Int, String) {
        let (count, error) = importFromJSONString(jsonString)
        guard count > 0 else { return (0, error) }
        do {
            try await db.saveBookSources(BookSourceImporter().parse(jsonString))
            await loadSources()
            return (count, "")
        } catch {
            return (0, "数据库保存失败：\(error.localizedDescription)")
        }
    }

    /// Internal: parse and diagnose without saving.
    private func importFromJSONString(_ jsonString: String) -> (Int, String) {
        let importer = BookSourceImporter()
        let (sources, diagnosis) = importer.parseWithDiagnosis(jsonString)
        return (sources.count, diagnosis)
    }
    
    /// 删除书源
    func deleteSource(_ source: BookSource) async {
        try? await db.deleteBookSource(source)
        await loadSources()
    }

    func deleteAllSources() async {
        try? await db.deleteAllBookSources()
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

    /// 将书源移至列表最顶部（customOrder = 当前最小值 - 1）
    func moveToTop(_ source: BookSource) async {
        let minOrder = sources.map { $0.customOrder }.min() ?? 0
        var updated = source
        updated.customOrder = minOrder - 1
        await saveSource(updated)
    }

    /// 切换书源在发现页的显示状态（enabledExplore）
    func toggleEnabledExplore(_ source: BookSource) async {
        var updated = source
        updated.enabledExplore = !source.enabledExplore
        await saveSource(updated)
    }

    /// 拖拽排序：将 from 位置的书源移到 to 位置，批量更新 customOrder
    func moveSource(from: IndexSet, to: Int) async {
        var reordered = sources
        reordered.move(fromOffsets: from, toOffset: to)
        // 重新分配 customOrder（0, 1, 2, ...），保证顺序稳定
        let updated = reordered.enumerated().map { idx, src -> BookSource in
            var s = src
            s.customOrder = idx
            return s
        }
        do {
            try await db.saveBookSources(updated)
            await loadSources()
        } catch {
            print("❌ [BookSourceVM] moveSource: \(error)")
        }
    }
}

/// 书源导入解析器 — 支持 Android 嵌套 JSON 格式
class BookSourceImporter {
    func parse(_ jsonString: String) -> [BookSource] {
        parseWithDiagnosis(jsonString).0
    }

    /// Parse and return (sources, humanReadableError). Error is "" on success.
    func parseWithDiagnosis(_ jsonString: String) -> ([BookSource], String) {
        guard let data = jsonString.data(using: .utf8) else {
            return ([], "JSON 字符串无法转 UTF-8 Data")
        }

        // 解析顶层 JSON 结构
        let rawObjects: [[String: Any]]
        do {
            let top = try JSONSerialization.jsonObject(with: data)
            if let arr = top as? [[String: Any]] {
                rawObjects = arr
            } else if let obj = top as? [String: Any] {
                // Check common Android wrapper keys before treating as a single source
                if let inner = obj["bookSourceList"] as? [[String: Any]] {
                    rawObjects = inner
                } else if let inner = obj["sources"] as? [[String: Any]] {
                    rawObjects = inner
                } else if let inner = obj["data"] as? [[String: Any]] {
                    rawObjects = inner
                } else {
                    rawObjects = [obj]
                }
            } else {
                return ([], "JSON 根类型不正确（期望数组或对象，实际得到 \(type(of: try JSONSerialization.jsonObject(with: data)))）")
            }
        } catch {
            return ([], "JSON 解析失败：\(error.localizedDescription)")
        }

        guard !rawObjects.isEmpty else {
            return ([], "JSON 解析为空数组")
        }

        // 将 Android 嵌套格式展平
        let flattened = rawObjects.map { flattenAndroidFormat($0) }
        guard let flatData = try? JSONSerialization.data(withJSONObject: flattened) else {
            return ([], "展平后的数据无法重新序列化")
        }

        let decoder = JSONDecoder()

        // 先尝试整批解码（快速路径）
        if let sources = try? decoder.decode([BookSource].self, from: flatData), !sources.isEmpty {
            let valid = sources.filter { !$0.bookSourceUrl.isEmpty }
            if !valid.isEmpty {
                print("✅ [Import] Batch OK: \(valid.count)/\(sources.count) sources")
                return (valid, "")
            }
        }

        // 整批失败 → 逐条解码，跳过有问题的条目
        var results: [BookSource] = []
        var itemErrors: [String] = []
        for (i, flat) in flattened.enumerated() {
            guard let itemData = try? JSONSerialization.data(withJSONObject: flat) else { continue }
            do {
                let source = try decoder.decode(BookSource.self, from: itemData)
                if !source.bookSourceUrl.isEmpty {
                    results.append(source)
                } else {
                    let name = flat["bookSourceName"] as? String ?? "?"
                    itemErrors.append("第\(i+1)条'\(name)'：bookSourceUrl 为空")
                }
            } catch {
                let name = flat["bookSourceName"] as? String ?? "?"
                itemErrors.append("第\(i+1)条'\(name)'解码失败：\(error.localizedDescription)")
            }
        }

        if !results.isEmpty {
            print("✅ [Import] Item-by-item: \(results.count)/\(flattened.count)")
            return (results, "")
        }

        let detail = itemErrors.prefix(3).joined(separator: "；")
        return ([], "共 \(flattened.count) 条书源全部解码失败。前几条原因：\(detail)")
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
