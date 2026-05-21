import SwiftUI

/// 设置界面
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingClearAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("数据管理")) {
                    Button(action: { viewModel.clearCache() }) {
                        HStack {
                            Text("清理缓存")
                            Spacer()
                            Text(viewModel.cacheSize).foregroundColor(.secondary)
                        }
                    }
                    
                    Button(role: .destructive, action: { viewModel.clearCookies() }) {
                        Text("清理所有 Cookie (注销登录)")
                    }
                    
                    Button(role: .destructive, action: { viewModel.clearDatabase() }) {
                        Text("重置数据库 (清空所有书源与书籍)")
                    }
                }
                
                Section(header: Text("关于")) {
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text(viewModel.appVersion).foregroundColor(.secondary)
                    }
                    
                    Link("开源项目地址", destination: URL(string: "https://github.com/gedoor/legado")!)
                }
            }
            .navigationTitle("设置")
        }
    }
}
