import SwiftUI

/// 主界面容器
/// 目标：提供 底部导航 切换 书架、发现、书源、设置
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
            
            // 2. 发现 (搜索)
            Text("搜索功能开发中")
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(1)
            
            // 3. 书源
            Text("书源管理开发中")
                .tabItem {
                    Label("书源", systemImage: "network")
                }
                .tag(2)
            
            // 4. 设置
            Text("设置开发中")
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
    }
}

#Preview {
    MainTabView()
}
