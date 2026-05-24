import SwiftUI

/// 阅读器排版与主题设置面板
struct ReaderSettingsSheet: View {
    @ObservedObject var settings = ReaderSettings.shared
    @ObservedObject private var tts = TTSManager.shared

    var body: some View {
        VStack(spacing: 25) {
            Text("排版设置")
                .font(.headline)
                .padding(.top)

            // 1. 字号调节
            HStack {
                Text("字号")
                Spacer()
                Stepper("", value: $settings.fontSize, in: 12...40)
                Text("\(Int(settings.fontSize))")
                    .frame(width: 30)
            }
            .padding(.horizontal)

            // 2. 行高调节
            HStack {
                Text("行高")
                Spacer()
                Stepper("", value: $settings.lineSpacing, in: 2...20)
                Text("\(Int(settings.lineSpacing))")
                    .frame(width: 30)
            }
            .padding(.horizontal)

            // 3. 朗读语速 (TTS)
            HStack {
                Text("朗读语速")
                Spacer()
                Slider(value: Binding(
                    get: { Double(TTSManager.shared.rate) },
                    set: { TTSManager.shared.rate = Float($0) }
                ), in: 0.1...1.0)
                .frame(width: 150)
                Text(String(format: "%.1fx", TTSManager.shared.rate * 2)) // 转换为常规倍速显示
                    .frame(width: 40)
            }
            .padding(.horizontal)

            // 4. 朗读语音选择 (P2-B)
            if !tts.availableVoices.isEmpty {
                HStack {
                    Text("朗读语音")
                    Spacer()
                    Picker("语音", selection: Binding(
                        get: { tts.selectedVoiceIdentifier },
                        set: { newId in
                            tts.selectedVoiceIdentifier = newId
                            tts.savedVoiceId = newId
                        }
                    )) {
                        Text("默认 (zh-CN)").tag("")
                        ForEach(tts.availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
            }

            // 5. 主题选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(ReaderTheme.allThemes) { theme in
                        VStack {
                            Circle()
                                .fill(theme.backgroundColor)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Circle().stroke(Color.primary, lineWidth: settings.themeId == theme.id ? 2 : 0)
                                )
                            Text(theme.name)
                                .font(.caption2)
                        }
                        .onTapGesture {
                            settings.themeId = theme.id
                        }
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .presentationDetents([.height(360)])
    }
}
