import SwiftUI

/// 主界面容器
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BookshelfView()
                .tabItem { Label("书架", systemImage: "books.vertical.fill") }
                .tag(0)
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(1)
            ExploreView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(2)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

#Preview { MainTabView() }


