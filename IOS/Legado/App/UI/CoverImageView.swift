import SwiftUI

/// 封面图片加载组件 — 带 Referer 头，解决部分 CDN 鉴权问题。
///
/// 用法：
///   CoverImageView(url: book.coverUrl, referer: book.origin)
///     .frame(width: 48, height: 64)
///     .cornerRadius(4)
struct CoverImageView: View {
    let url: String?
    let referer: String?

    @StateObject private var loader = CoverImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            await loader.load(url: url, referer: referer)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .overlay(
                Image(systemName: "book.closed")
                    .foregroundColor(.secondary)
            )
    }
}

// MARK: - Loader

@MainActor
private class CoverImageLoader: ObservableObject {
    @Published var image: UIImage? = nil

    private static var cache = NSCache<NSString, UIImage>()

    func load(url urlStr: String?, referer: String?) async {
        guard let urlStr, !urlStr.isEmpty else { image = nil; return }
        // Strip spurious trailing slash from image URLs (e.g. ".jpg/") to avoid 404s.
        // This artifact appears when a regex replacement matches a path segment
        // like "/101045" from "/101045/" without consuming the trailing slash.
        var cleanUrl = urlStr
        if cleanUrl.hasPrefix("http"), cleanUrl.hasSuffix("/"),
           let ext = URL(string: cleanUrl)?.pathExtension, !ext.isEmpty {
            cleanUrl = String(cleanUrl.dropLast())
        }
        guard let url = URL(string: cleanUrl) else { image = nil; return }

        let key = cleanUrl as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached; return
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        if let ref = referer, !ref.isEmpty {
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }
        // 模拟浏览器 UA，部分 CDN 会检查
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let img = UIImage(data: data) else { return }
            Self.cache.setObject(img, forKey: key)
            image = img
        } catch {
            image = nil
        }
    }
}
