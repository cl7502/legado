import SwiftUI
import Combine

/// 搜索业务逻辑
@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var searchProgress: Float = 0
    
    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared
    
    /// 执行并发搜索
    func search(_ query: String) async {
        guard !query.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        searchProgress = 0
        
        do {
            // 1. 获取所有启用的书源
            let sources = try await db.getEnabledBookSources()
            guard !sources.isEmpty else {
                isSearching = false
                return
            }
            
            let totalSources = Float(sources.count)
            var completedCount: Float = 0
            
            // 2. 使用 TaskGroup 进行并发搜索
            await withTaskGroup(of: [SearchResult].self) { group in
                for source in sources {
                    group.addTask {
                        return await self.searchInSource(query, source: source)
                    }
                }
                
                // 3. 流式获取结果并更新 UI
                for await results in group {
                    self.searchResults.append(contentsOf: results)
                    completedCount += 1
                    self.searchProgress = completedCount / totalSources
                }
            }
        } catch {
            print("❌ [Search Error]: \(error)")
        }
        
        isSearching = false
    }
    
    /// 在单个书源中搜索 (核心逻辑)
    private func searchInSource(_ query: String, source: BookSource) async -> [SearchResult] {
        guard let searchUrlTemplate = source.searchUrl else { return [] }
        
        // 简单替换关键词 (对标 Android 版基础搜索)
        let finalUrl = searchUrlTemplate.replacingOccurrences(of: "{{key}}", with: query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)
        
        do {
            // 创建上下文
            var context = AnalyzeContext(source: source, baseUrl: finalUrl)
            
            // 发起请求
            let html = try await network.request(finalUrl, source: source, context: &context)
            context.result = html
            
            // 执行搜索列表规则 (阶段 4 完善的规则引擎)
            // TODO: 这里需要 RuleExecutor 支持返回列表，目前先模拟单条返回
            if let rule = source.ruleSearchUrl,
               let _ = ruleExecutor.execute(rule, in: &context) {
                // 暂时返回一个模拟结果证明流程打通
                return [SearchResult(name: "示例书籍", author: "示例作者", bookUrl: finalUrl, origin: source.bookSourceUrl, originName: source.bookSourceName)]
            }
        } catch {
            print("⚠️ [Search Source Error]: \(source.bookSourceName) - \(error.localizedDescription)")
        }
        
        return []
    }
}
