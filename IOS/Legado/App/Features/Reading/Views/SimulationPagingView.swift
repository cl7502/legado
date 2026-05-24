import SwiftUI
import UIKit

/// 仿真翻页容器 (基于 UIKit UIPageViewController)
/// 目标：实现完美的仿真翻页手感 (Curl/Scroll)
struct SimulationPagingView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: ReaderViewModel
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl, // 仿真翻页
            navigationOrientation: .horizontal,
            options: nil
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        
        // 设置初始页面
        let initialVC = context.coordinator.viewController(at: viewModel.currentChapterIndex)
        pageVC.setViewControllers([initialVC], direction: .forward, animated: false)
        
        return pageVC
    }
    
    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        // 当 viewModel 触发跳转时更新页面 (需判断是否已在当前页)
        let currentVC = uiViewController.viewControllers?.first as? ChapterPageViewController
        if currentVC?.index != viewModel.currentChapterIndex {
            let nextVC = context.coordinator.viewController(at: viewModel.currentChapterIndex)
            let direction: UIPageViewController.NavigationDirection = (currentVC?.index ?? 0) < viewModel.currentChapterIndex ? .forward : .reverse
            uiViewController.setViewControllers([nextVC], direction: direction, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: SimulationPagingView
        
        init(_ parent: SimulationPagingView) {
            self.parent = parent
        }
        
        func viewController(at index: Int) -> UIViewController {
            let vc = ChapterPageViewController()
            vc.index = index
            vc.content = parent.viewModel.chapterContents[index] ?? "正在加载..."
            vc.titleStr = parent.viewModel.chapters[index].title
            return vc
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            let current = (viewController as! ChapterPageViewController).index
            guard current > 0 else { return nil }
            return self.viewController(at: current - 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            let current = (viewController as! ChapterPageViewController).index
            guard current < parent.viewModel.chapters.count - 1 else { return nil }
            return self.viewController(at: current + 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let currentVC = pageViewController.viewControllers?.first as? ChapterPageViewController {
                // 更新 ViewModel 进度
                DispatchQueue.main.async {
                    self.parent.viewModel.currentChapterIndex = currentVC.index
                }
            }
        }
    }
}

/// 单个章节页面的 UIKit 控制器 (用于嵌入 PageViewController)
class ChapterPageViewController: UIViewController {
    var index: Int = 0
    var content: String = ""
    var titleStr: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 使用 UIHostingController 桥接回 SwiftUI 进行页面内容渲染
        let hostingController = UIHostingController(rootView: ReaderPageContent(content: content, chapterTitle: titleStr))
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.didMove(toParent: self)
        
        // 继承背景色
        hostingController.view.backgroundColor = .clear
    }
}
