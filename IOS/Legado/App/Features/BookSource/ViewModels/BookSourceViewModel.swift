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
}

/// 书源导入解析器
class BookSourceImporter {
    func parse(_ jsonString: String) -> [BookSource] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        
        // 尝试解析为数组
        if let sources = try? decoder.decode([BookSource].self, from: data) {
            return sources
        }
        
        // 尝试解析为单体
        if let source = try? decoder.decode(BookSource.self, from: data) {
            return [source]
        }
        
        return []
    }
}
