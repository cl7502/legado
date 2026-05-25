import SwiftUI
import UIKit

/// 仿真翻页容器 (基于 UIKit UIPageViewController)
/// 数据源：viewModel.currentPages（章节内物理页切片）
struct SimulationPagingView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: ReaderViewModel

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator

        // 初始页面：如果 currentPages 已填充则使用，否则显示占位
        let initialVC = context.coordinator.makePageVC(at: viewModel.currentPageIndex)
        pageVC.setViewControllers([initialVC], direction: .forward, animated: false)

        return pageVC
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        let currentVC = uiViewController.viewControllers?.first as? PhysicalPageViewController
        let desiredIndex = viewModel.currentPageIndex

        // 计算目标页的期望内容，用于检测分页完成后内容变化
        let expectedContent: String
        if viewModel.currentPages.isEmpty {
            expectedContent = viewModel.chapterContents[viewModel.currentChapterIndex] ?? "正在加载..."
        } else {
            let clamped = max(0, min(desiredIndex, viewModel.currentPages.count - 1))
            expectedContent = viewModel.currentPages[clamped]
        }

        // 如果页码相同且内容也相同，无需重新渲染
        if currentVC?.pageIndex == desiredIndex && currentVC?.content == expectedContent {
            return
        }

        let direction: UIPageViewController.NavigationDirection =
            (currentVC?.pageIndex ?? 0) < desiredIndex ? .forward : .reverse
        let nextVC = context.coordinator.makePageVC(at: desiredIndex)
        // 仅在页码真正改变时启用动画，内容刷新时不动画
        let animated = currentVC?.pageIndex != desiredIndex
        uiViewController.setViewControllers([nextVC], direction: direction, animated: animated)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: SimulationPagingView

        init(_ parent: SimulationPagingView) {
            self.parent = parent
        }

        /// 为指定页码构建 VC（安全边界处理）
        func makePageVC(at index: Int) -> PhysicalPageViewController {
            let vm = parent.viewModel
            let vc = PhysicalPageViewController()
            vc.pageIndex = index

            if vm.currentPages.isEmpty {
                // 内容尚未分页，显示占位
                let title = vm.chapters.indices.contains(vm.currentChapterIndex)
                    ? vm.chapters[vm.currentChapterIndex].title : ""
                let body = vm.chapterContents[vm.currentChapterIndex] ?? "正在加载..."
                vc.content = body
                vc.chapterTitle = title
                vc.pageLabel = ""
            } else {
                let clampedIndex = max(0, min(index, vm.currentPages.count - 1))
                vc.content = vm.currentPages[clampedIndex]
                vc.chapterTitle = clampedIndex == 0
                    ? (vm.chapters.indices.contains(vm.currentChapterIndex)
                        ? vm.chapters[vm.currentChapterIndex].title : "")
                    : ""
                vc.pageLabel = "\(clampedIndex + 1) / \(vm.currentPages.count)"
            }
            return vc
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PhysicalPageViewController,
                  current.pageIndex > 0 else { return nil }
            return makePageVC(at: current.pageIndex - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PhysicalPageViewController else { return nil }
            let maxIndex = max(0, parent.viewModel.currentPages.count - 1)
            guard current.pageIndex < maxIndex else { return nil }
            return makePageVC(at: current.pageIndex + 1)
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? PhysicalPageViewController
            else { return }

            DispatchQueue.main.async {
                self.parent.viewModel.currentPageIndex = currentVC.pageIndex
            }
        }
    }
}

// MARK: - PhysicalPageViewController

/// 单个物理页面的 UIKit 容器（替代原来整章 ChapterPageViewController）
class PhysicalPageViewController: UIViewController {
    var pageIndex: Int = 0
    var content: String = ""
    var chapterTitle: String = ""
    var pageLabel: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let hostingVC = UIHostingController(
            rootView: ReaderPageContent(
                content: content,
                chapterTitle: chapterTitle,
                pageLabel: pageLabel
            )
        )
        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.view.frame = view.bounds
        hostingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingVC.view.backgroundColor = .clear
        hostingVC.didMove(toParent: self)
    }
}
