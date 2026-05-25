import SwiftUI

/// 主界面容器
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // 1. 书架
            BookshelfView()
                .tabItem {
                    Label("书架", systemImage: "books.vertical.fill")
                }
                .tag(0)

            // 2. 搜索
            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(1)

            // 3. 发现
            ExploreView()
                .tabItem {
                    Label("发现", systemImage: "safari")
                }
                .tag(2)

            // 4. 设置
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        // ISSUE-026: 确保背景延伸到全面屏 SafeArea 区域，消除黑边
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

#Preview {
    MainTabView()
}
