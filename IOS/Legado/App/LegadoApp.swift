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
            }
            #if DEBUG
            .task {
                await SpeakerAuditionHelper.generateAll()
            }
            #endif
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
