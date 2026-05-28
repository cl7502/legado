import SafariServices
import SwiftUI

/// SFSafariViewController 的 SwiftUI 包装，用于书源"浏览"功能
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
