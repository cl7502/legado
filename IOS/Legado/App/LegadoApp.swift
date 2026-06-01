import SwiftUI


@main
struct LegadoApp: App {
    @State private var dbReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if dbReady {
                    MainTabView()
                } else {
                    AppLaunchView()
                }
            }
            .task {
                await Task.detached(priority: .userInitiated) {
                    _ = DatabaseManager.shared
                }.value
                dbReady = true
                // WebDAV：启动后检查服务端是否有更新
                await MainActor.run { WebDAVSyncManager.shared.checkOnLaunch() }
            }
        }
    }
}

private struct AppLaunchView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Legado")
                .font(.largeTitle.bold())
            ProgressView().scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
