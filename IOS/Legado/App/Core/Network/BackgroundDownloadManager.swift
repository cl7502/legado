import Foundation

/// 后台下载管理器
/// 目标：确保大文件（如 EPUB 或批量章节）在后台持续下载
class BackgroundDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = BackgroundDownloadManager()
    
    private var backgroundSession: URLSession!
    private var completionHandler: (() -> Void)?
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "io.legado.app.background")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false // 立即开始，不等待系统调度（为了体验）
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func startDownload(url: URL) {
        let task = backgroundSession.downloadTask(with: url)
        task.resume()
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 下载完成，处理文件移动
        print("✅ [Background] Download finished: \(location.path)")
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.completionHandler?()
            self.completionHandler = nil
        }
    }
}
