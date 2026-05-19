import SwiftUI

struct ContentView: View {
    @State private var testOutput = "点击按钮开始测试..."
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Legado iOS 验证程序")
                .font(.largeTitle)
                .fontWeight(.bold)

            Button(action: runTests) {
                Text(isRunning ? "测试中..." : "开始测试")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isRunning)

            ScrollView {
                Text(testOutput)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 400)
    }

    func runTests() {
        isRunning = true
        testOutput = "正在运行测试..."

        DispatchQueue.global(qos: .userInitiated).async {
            let output = ValidationRunner.shared.runAllTests()

            DispatchQueue.main.async {
                self.testOutput = output
                self.isRunning = false

                // 同时输出到控制台
                print(output)
            }
        }
    }
}

#Preview {
    ContentView()
}