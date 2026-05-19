import SwiftUI

/// 章节目录视图
struct TOCView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(0..<viewModel.chapters.count, id: \.self) { index in
                    let chapter = viewModel.chapters[index]
                    HStack {
                        Text(chapter.title)
                            .foregroundColor(viewModel.currentChapterIndex == index ? .blue : .primary)
                        Spacer()
                        if viewModel.currentChapterIndex == index {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.jumpToChapter(index)
                        dismiss()
                    }
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
