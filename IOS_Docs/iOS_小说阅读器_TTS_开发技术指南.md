# iOS 小说阅读器 TTS 开发技术指南
## 基于 Sherpa-ONNX 的离线语音合成方案

> **版本**: v1.0  
> **日期**: 2026-05-30  
> **适用场景**: iOS 小说阅读器 App，要求完全离线、低资源占用、中文优化、角色音色区分

---

## 目录

1. [架构概览](#1-架构概览)
2. [环境准备与构建](#2-环境准备与构建)
3. [模型选型与下载](#3-模型选型与下载)
4. [iOS 集成实战](#4-ios-集成实战)
5. [小说场景专项优化](#5-小说场景专项优化)
6. [性能调优与资源管理](#6-性能调优与资源管理)
7. [常见问题与解决方案](#7-常见问题与解决方案)
8. [参考资源](#8-参考资源)

---

## 1. 架构概览

### 1.1 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        应用层 (App Layer)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │  阅读器 UI   │  │  播放控制器  │  │  角色/语速/音色设置面板  │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                      业务逻辑层 (Business Layer)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │ 文本分句引擎  │  │ 角色识别模块  │  │ 音频缓冲与预加载管理  │ │
│  │ (Sentence    │  │ (NLP 角色    │  │ (Audio Buffer &      │ │
│  │  Segmenter)  │  │  Detection)  │  │  Preload Manager)    │ │
│  └──────────────┘  └──────────────┘  └──────────────────────┘ │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │ 多音字预处理  │  │ SSML 生成器   │  │ 音色切换调度器        │ │
│  │ (Polyphone   │  │ (SSML        │  │ (Voice Scheduler)    │ │
│  │  Resolver)   │  │  Generator)  │  │                      │ │
│  └──────────────┘  └──────────────┘  └──────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                      引擎层 (Engine Layer)                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Sherpa-ONNX 统一推理引擎                      │  │
│  │    (支持 Piper / Kokoro / Matcha / Zipvoice 等多模型)     │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌────────────────────┐  ┌────────────────────────────────┐   │
│  │  ONNX Runtime      │  │  模型管理器 (Model Manager)     │   │
│  │  (推理后端)         │  │  (按需加载/缓存/卸载)            │   │
│  └────────────────────┘  └────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│                      数据层 (Data Layer)                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ 小说文本文件 │  │ TTS 模型文件 │  │ 角色-音色映射配置        │ │
│  │ (EPUB/TXT)  │  │ (.onnx 等)  │  │ (JSON/YAML)             │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 技术选型决策

| 需求维度 | 推荐方案 | 备选方案 | 说明 |
|---------|---------|---------|------|
| **最小资源** | Piper (int8, ~22MB) | Matcha-TTS | Piper RTF < 0.3，CPU 实时 |
| **最高音质** | Kokoro-82M (~82MB) | Matcha-TTS | MOS 4.5，开源顶级 |
| **角色区分** | Kokoro 多 speaker | Zipvoice 克隆 | Kokoro 原生支持多说话人 |
| **中文多音字** | 应用层预处理 + SSML | 自定义词典 | 引擎层不解决，需前置处理 |
| **iOS 集成** | Sherpa-ONNX XCFramework | 自行编译 ONNX Runtime | Sherpa-ONNX 官方支持 iOS |

**推荐组合**: **Sherpa-ONNX + Kokoro-82M (中文模型)** 作为主力，Piper 作为轻量降级方案。

---

## 2. 环境准备与构建

### 2.1 系统要求

- **macOS** (必须，iOS 开发只能在 macOS 上进行)
- **Xcode** 14.2+ (推荐 15.x 或更高)
- **CMake** 3.25.1+ (`brew install cmake`)
- **iOS 部署版本**: >= 13.0
- **Python 3** (用于模型下载和预处理脚本)

### 2.2 构建 Sherpa-ONNX iOS 框架

#### 步骤 1: 克隆源码

```bash
mkdir -p ~/open-source
cd ~/open-source
git clone https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx
```

#### 步骤 2: 执行构建脚本

```bash
# 构建 iOS 版本（包含模拟器和真机架构）
./build-ios.sh
```

构建完成后，会在 `build-ios` 目录下生成：
- `sherpa-onnx.xcframework` — Sherpa-ONNX 框架
- `ios-onnxruntime/1.16.2/onnxruntime.xcframework` — ONNX Runtime 框架

> **注意**: 如果构建过程中遇到 CMake 错误：
> ```
> CMake Error at toolchains/ios.toolchain.cmake:544 (get_filename_component):
> ```
> 请执行：
> ```bash
> sudo xcode-select --install
> sudo xcodebuild -license
> ```
> 然后删除 `build-ios` 目录重新构建。

#### 步骤 3: 验证构建产物

```bash
ls -la build-ios/
# 应包含:
# - sherpa-onnx.xcframework
# - ios-onnxruntime/
```

---

## 3. 模型选型与下载

### 3.1 模型对比表

| 模型 | 类型 | 大小 | 中文支持 | 多说话人 | 音质(MOS) | 适用场景 |
|------|------|------|---------|---------|----------|---------|
| **Piper zh_CN-huayan** | VITS | ~22MB (int8) | ✅ | ❌ (单说话人) | 3.3 | 资源极度敏感 |
| **Kokoro v1.0 multi-lang** | 自研 | ~82MB | ✅ 中英混合 | ✅ (多 speaker) | 4.5 | **推荐主力** |
| **Matcha-TTS zh-baker** | Matcha | ~150MB | ✅ | ❌ | 4.2 | 高质量单说话人 |
| **Zipvoice** | 语音克隆 | ~100MB | 依赖模型 | ✅ (克隆) | 4.0+ | 角色克隆 |

### 3.2 推荐模型下载

#### 方案 A: Kokoro 中文多语言模型 (推荐)

```bash
# 创建模型目录
mkdir -p ~/sherpa-models/kokoro-zh
cd ~/sherpa-models/kokoro-zh

# 下载 Kokoro multi-lang v1.0 (支持中英混合)
# 从 Hugging Face 下载
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2
tar xvf kokoro-multi-lang-v1_0.tar.bz2

# 目录结构应为:
# kokoro-multi-lang-v1_0/
# ├── model.onnx          # 声学模型
# ├── tokens.txt          # 词表
# ├── voices.bin          # 说话人音色数据
# └── README.md
```

#### 方案 B: Piper 中文模型 (轻量备选)

```bash
mkdir -p ~/sherpa-models/piper-zh
cd ~/sherpa-models/piper-zh

# 下载 Piper 中文模型
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-huayan-medium.tar.bz2
tar xvf vits-piper-zh_CN-huayan-medium.tar.bz2

# 目录结构:
# vits-piper-zh_CN-huayan-medium/
# ├── zh_CN-huayan-medium.onnx
# ├── zh_CN-huayan-medium.onnx.json
# └── espeak-ng-data/     # 音素数据
```

#### 方案 C: Matcha-TTS 中文模型 (高质量)

```bash
mkdir -p ~/sherpa-models/matcha-zh
cd ~/sherpa-models/matcha-zh

# 下载 Matcha-TTS 中文模型
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/matcha-icefall-zh_baker.tar.bz2
tar xvf matcha-icefall-zh_baker.tar.bz2

# 目录结构:
# matcha-icefall-zh_baker/
# ├── model-steps-3.onnx   # 声学模型
# ├── hifigan_v2.onnx      # 声码器
# ├── tokens.txt
# ├── lexicon.txt
# └── dict/                # 发音词典
```

### 3.3 模型文件添加到 Xcode

1. 在 Xcode 中，右键点击项目 -> **Add Files to "YourProject"...**
2. 选择模型文件夹，确保勾选：
   - ☑️ **Create folder references** (保持目录结构)
   - ☑️ **Copy items if needed**
3. 在 **Build Phases -> Copy Bundle Resources** 中确认模型文件已包含

---

## 4. iOS 集成实战

### 4.1 Xcode 项目配置

#### 步骤 1: 创建新项目

- 打开 Xcode -> File -> New -> Project
- 选择 **iOS -> App**
- 语言: **Swift**
- 界面: **SwiftUI** (推荐) 或 UIKit
- 最低部署版本: **iOS 13.0**

#### 步骤 2: 添加框架

将以下文件拖入项目 (到 Frameworks 组或根目录):

```
build-ios/sherpa-onnx.xcframework
build-ios/ios-onnxruntime/1.16.2/onnxruntime.xcframework
```

在 **General -> Frameworks, Libraries, and Embedded Content** 中：
- 确保两个框架的 **Embed** 选项设置为 **"Embed & Sign"**

#### 步骤 3: 配置 Build Settings

```
Build Settings:
├── FRAMEWORK_SEARCH_PATHS = $(PROJECT_DIR)/../../build-ios
├── HEADER_SEARCH_PATHS = $(PROJECT_DIR)/../../build-ios/sherpa-onnx.xcframework/Headers
├── OTHER_LDFLAGS = -lc++
├── SWIFT_OBJC_BRIDGING_HEADER = $(PROJECT_DIR)/../../swift-api-examples/SherpaOnnx-Bridging-Header.h
└── CLANG_ENABLE_MODULES = YES
```

#### 步骤 4: 创建桥接头文件

创建 `YourProject-Bridging-Header.h`:

```objc
#ifndef YourProject_Bridging_Header_h
#define YourProject_Bridging_Header_h

// Sherpa-ONNX C API
#include "c-api.h"

#endif
```

在 **Build Settings -> Swift Compiler - General -> Objective-C Bridging Header** 中设置路径：
```
$(PROJECT_DIR)/YourProject/YourProject-Bridging-Header.h
```

### 4.2 Swift TTS 封装类

#### SherpaOnnxTTSManager.swift

```swift
import Foundation
import AVFoundation

/// TTS 引擎类型
enum TTSEngineType {
    case piper       // 轻量快速
    case kokoro      // 高质量多说话人
    case matcha      // 高质量单说话人
}

/// TTS 配置
struct TTSConfig {
    let engine: TTSEngineType
    let modelPath: String
    let tokensPath: String
    let lexiconPath: String?
    let dictDir: String?
    let voicesPath: String?      // Kokoro 专用
    let numThreads: Int32
    let sampleRate: Int32
}

/// 生成的音频数据
struct TTSResult {
    let samples: [Float]
    let sampleRate: Int32
    let duration: Double
}

/// Sherpa-ONNX TTS 管理器
class SherpaOnnxTTSManager: ObservableObject {

    // MARK: - Published Properties
    @Published var isSpeaking = false
    @Published var currentProgress: Double = 0.0
    @Published var currentSpeaker: Int32 = 0

    // MARK: - Private Properties
    private var tts: OpaquePointer?
    private var audioPlayer: AVAudioPlayer?
    private var engineQueue = DispatchQueue(label: "com.yourapp.tts.engine", qos: .userInitiated)
    private var audioSession: AVAudioSession?

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    deinit {
        destroyTTS()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession?.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: - TTS Initialization

    /// 初始化 Piper TTS
    func initializePiper(modelName: String, tokensName: String, dataDir: String? = nil) -> Bool {
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "onnx"),
              let tokensPath = Bundle.main.path(forResource: tokensName, ofType: "txt") else {
            print("Model files not found")
            return false
        }

        let vitsConfig = SherpaOnnxOfflineTtsVitsModelConfig(
            model: modelPath,
            lexicon: nil,
            tokens: tokensPath,
            dataDir: dataDir,
            dictDir: nil,
            noiseScale: 0.667,
            noiseScaleW: 0.8,
            lengthScale: 1.0
        )

        let modelConfig = SherpaOnnxOfflineTtsModelConfig(
            vits: vitsConfig,
            numThreads: 2,      // iPhone 建议 2 线程
            debug: 0,
            provider: "cpu"
        )

        var config = SherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1
        )

        tts = SherpaOnnxCreateOfflineTts(&config)
        return tts != nil
    }

    /// 初始化 Kokoro TTS (推荐)
    func initializeKokoro(modelName: String, voicesName: String, tokensName: String) -> Bool {
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "onnx"),
              let voicesPath = Bundle.main.path(forResource: voicesName, ofType: "bin"),
              let tokensPath = Bundle.main.path(forResource: tokensName, ofType: "txt") else {
            print("Kokoro model files not found")
            return false
        }

        let kokoroConfig = SherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: voicesPath,
            tokens: tokensPath,
            lexicon: nil,
            dataDir: nil,
            dictDir: nil,
            lengthScale: 1.0
        )

        let modelConfig = SherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig,
            numThreads: 2,
            debug: 0,
            provider: "cpu"
        )

        var config = SherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1
        )

        tts = SherpaOnnxCreateOfflineTts(&config)
        return tts != nil
    }

    /// 初始化 Matcha-TTS
    func initializeMatcha(acousticModel: String, vocoder: String, tokensName: String, lexiconName: String, dictDir: String) -> Bool {
        guard let acousticPath = Bundle.main.path(forResource: acousticModel, ofType: "onnx"),
              let vocoderPath = Bundle.main.path(forResource: vocoder, ofType: "onnx"),
              let tokensPath = Bundle.main.path(forResource: tokensName, ofType: "txt"),
              let lexiconPath = Bundle.main.path(forResource: lexiconName, ofType: "txt") else {
            print("Matcha model files not found")
            return false
        }

        let matchaConfig = SherpaOnnxOfflineTtsMatchaModelConfig(
            acousticModel: acousticPath,
            vocoder: vocoderPath,
            lexicon: lexiconPath,
            tokens: tokensPath,
            dictDir: dictDir,
            lengthScale: 1.0
        )

        let modelConfig = SherpaOnnxOfflineTtsModelConfig(
            matcha: matchaConfig,
            numThreads: 2,
            debug: 0,
            provider: "cpu"
        )

        var config = SherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1
        )

        tts = SherpaOnnxCreateOfflineTts(&config)
        return tts != nil
    }

    // MARK: - TTS Synthesis

    /// 合成文本为音频 (同步，建议在后台线程调用)
    func synthesize(text: String, speakerId: Int32 = 0, speed: Float = 1.0) -> TTSResult? {
        guard let tts = tts else {
            print("TTS not initialized")
            return nil
        }

        // 生成音频
        let audio = SherpaOnnxOfflineTtsGenerate(tts, text, speakerId, speed)

        guard let audio = audio, audio.pointee.numSamples > 0 else {
            print("TTS generation failed")
            return nil
        }

        // 提取样本数据
        let numSamples = Int(audio.pointee.numSamples)
        let sampleRate = audio.pointee.sampleRate
        var samples = [Float](repeating: 0, count: numSamples)

        memcpy(&samples, audio.pointee.samples, numSamples * MemoryLayout<Float>.size)

        let duration = Double(numSamples) / Double(sampleRate)

        // 释放音频对象
        SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio)

        return TTSResult(samples: samples, sampleRate: sampleRate, duration: duration)
    }

    /// 异步合成并播放
    func speak(text: String, speakerId: Int32 = 0, speed: Float = 1.0, completion: (() -> Void)? = nil) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }

            guard let result = self.synthesize(text: text, speakerId: speakerId, speed: speed) else {
                DispatchQueue.main.async { completion?() }
                return
            }

            self.playAudio(samples: result.samples, sampleRate: result.sampleRate) {
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    completion?()
                }
            }
        }
    }

    // MARK: - Audio Playback

    private func playAudio(samples: [Float], sampleRate: Int32, completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            do {
                // 写入临时 WAV 文件
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "tts_output_\(UUID().uuidString).wav")
                try self.writeWavFile(samples: samples, sampleRate: Int(sampleRate), to: tempURL)

                // 播放
                self.audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                self.audioPlayer?.prepareToPlay()

                // 设置完成回调
                NotificationCenter.default.addObserver(
                    forName: AVAudioSession.interruptionNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    completion()
                }

                self.isSpeaking = true
                self.audioPlayer?.play()

                // 监听播放完成
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    guard let player = self.audioPlayer else {
                        timer.invalidate()
                        completion()
                        return
                    }
                    self.currentProgress = Double(player.currentTime) / Double(player.duration)
                    if !player.isPlaying {
                        timer.invalidate()
                        completion()
                    }
                }

            } catch {
                print("Audio playback failed: \(error)")
                completion()
            }
        }
    }

    /// 将浮点样本写入 WAV 文件
    private func writeWavFile(samples: [Float], sampleRate: Int, to url: URL) throws {
        let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!

        let audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "TTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer creation failed"])
        }
        buffer.frameLength = frameCount

        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        try audioFile.write(from: buffer)
    }

    // MARK: - Control Methods

    func stop() {
        audioPlayer?.stop()
        isSpeaking = false
        currentProgress = 0.0
    }

    func pause() {
        audioPlayer?.pause()
        isSpeaking = false
    }

    func resume() {
        audioPlayer?.play()
        isSpeaking = true
    }

    // MARK: - Cleanup

    private func destroyTTS() {
        if let tts = tts {
            SherpaOnnxDestroyOfflineTts(tts)
            self.tts = nil
        }
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func cleanup() {
        destroyTTS()
        try? audioSession?.setActive(false)
    }
}
```

### 4.3 SwiftUI 使用示例

#### ContentView.swift

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var ttsManager = SherpaOnnxTTSManager()
    @State private var inputText = "你好，欢迎使用 Sherpa-ONNX 语音合成。这是一段测试文本。"
    @State private var selectedSpeaker: Int32 = 0
    @State private var speed: Float = 1.0

    // Kokoro 说话人列表 (根据模型实际 voices.bin 中的数量调整)
    let speakers = [
        (id: 0, name: "默认女声"),
        (id: 1, name: "男声 A"),
        (id: 2, name: "男声 B"),
        (id: 3, name: "女声 (温柔)"),
        (id: 4, name: "女声 (活泼)"),
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 文本输入
                TextEditor(text: $inputText)
                    .frame(height: 150)
                    .border(Color.gray, width: 1)
                    .padding()

                // 说话人选择
                Picker("说话人", selection: $selectedSpeaker) {
                    ForEach(speakers, id: \.id) { speaker in
                        Text(speaker.name).tag(Int32(speaker.id))
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                // 语速调节
                HStack {
                    Text("语速: \((speed * 100).formatted(.number.precision(.fractionLength(0))))%")
                    Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                }
                .padding(.horizontal)

                // 播放进度
                if ttsManager.isSpeaking {
                    ProgressView(value: ttsManager.currentProgress)
                        .padding(.horizontal)
                }

                // 控制按钮
                HStack(spacing: 30) {
                    Button(action: { ttsManager.stop() }) {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundColor(.red)
                    }

                    Button(action: playTTS) {
                        Image(systemName: ttsManager.isSpeaking ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(inputText.isEmpty)
                }
                .padding()

                Spacer()
            }
            .navigationTitle("小说朗读 TTS")
            .onAppear {
                initializeTTS()
            }
        }
    }

    private func initializeTTS() {
        // 使用 Kokoro 初始化 (推荐)
        let success = ttsManager.initializeKokoro(
            modelName: "model",
            voicesName: "voices",
            tokensName: "tokens"
        )

        if !success {
            print("Kokoro initialization failed, trying Piper fallback")
            // 降级到 Piper
            _ = ttsManager.initializePiper(
                modelName: "zh_CN-huayan-medium",
                tokensName: "tokens"
            )
        }
    }

    private func playTTS() {
        if ttsManager.isSpeaking {
            ttsManager.pause()
        } else {
            ttsManager.speak(
                text: inputText,
                speakerId: selectedSpeaker,
                speed: speed
            )
        }
    }
}
```

---

## 5. 小说场景专项优化

### 5.1 文本分句与段落管理

小说文本通常很长，需要智能分句和段落管理：

```swift
/// 小说文本分句引擎
class NovelTextSegmenter {

    /// 分句规则：按标点符号分割，保持上下文连贯
    func segment(text: String, maxLength: Int = 100) -> [String] {
        let sentenceDelimiters = CharacterSet(charactersIn: "。！？.!?\n")
        var sentences: [String] = []
        var currentSentence = ""

        for char in text {
            currentSentence.append(char)

            if sentenceDelimiters.contains(char.unicodeScalars.first!) {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // 如果句子太长，进一步分割
                    if trimmed.count > maxLength {
                        sentences.append(contentsOf: splitLongSentence(trimmed, maxLength: maxLength))
                    } else {
                        sentences.append(trimmed)
                    }
                }
                currentSentence = ""
            }
        }

        // 处理剩余文本
        if !currentSentence.isEmpty {
            sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return sentences
    }

    private func splitLongSentence(_ sentence: String, maxLength: Int) -> [String] {
        // 按逗号、分号等进一步分割
        let subDelimiters = CharacterSet(charactersIn: "，,；;")
        var parts: [String] = []
        var current = ""

        for char in sentence {
            current.append(char)
            if subDelimiters.contains(char.unicodeScalars.first!) && current.count >= maxLength / 2 {
                parts.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts.isEmpty ? [sentence] : parts
    }
}
```

### 5.2 角色识别与音色映射

```swift
/// 小说角色识别器
class NovelCharacterDetector {

    struct CharacterProfile {
        let name: String
        let defaultSpeakerId: Int32
        let aliases: [String]  // 别名，如 "林总"、"小林"
    }

    private var characters: [CharacterProfile] = []
    private var dialoguePattern: NSRegularExpression?

    init() {
        // 中文对话正则："xxx" 或 「xxx」 或 'xxx'
        dialoguePattern = try? NSRegularExpression(
            pattern: "(["「『"'])(.*?)(["」』"'])",
            options: []
        )
    }

    /// 从小说文本中提取角色 (简单实现，可用 NLP 模型增强)
    func extractCharacters(from text: String) -> [CharacterProfile] {
        // 1. 提取带引号的对话前的说话人提示
        // 例如: 张三说："你好"
        let pattern = try! NSRegularExpression(
            pattern: "([\u4e00-\u9fa5]{1,6})(?:说|道|喊|问|答|叫道|问道|回答|喃喃)[：:]",
            options: []
        )

        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, options: [], range: range)

        var names = Set<String>()
        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: text) {
                names.insert(String(text[nameRange]))
            }
        }

        // 分配默认 speaker ID
        return names.enumerated().map { index, name in
            CharacterProfile(
                name: name,
                defaultSpeakerId: Int32(index % 5),  // 循环使用可用音色
                aliases: []
            )
        }
    }

    /// 分析段落，返回 (文本, 说话人ID) 数组
    func analyzeParagraph(_ paragraph: String) -> [(text: String, speakerId: Int32)] {
        var result: [(String, Int32)] = []
        let range = NSRange(paragraph.startIndex..., in: paragraph)

        guard let matches = dialoguePattern?.matches(in: paragraph, options: [], range: range) else {
            return [(paragraph, 0)]  // 旁白用默认音色
        }

        var lastEnd = paragraph.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: paragraph),
                  let contentRange = Range(match.range(at: 2), in: paragraph) else { continue }

            // 匹配前的文本 (旁白)
            if matchRange.lowerBound > lastEnd {
                let narration = String(paragraph[lastEnd..<matchRange.lowerBound])
                if !narration.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append((narration, 0))  // 旁白: speaker 0
                }
            }

            // 对话内容
            let dialogue = String(paragraph[contentRange])
            let speakerId = detectSpeaker(for: paragraph, before: matchRange.lowerBound)
            result.append((dialogue, speakerId))

            lastEnd = matchRange.upperBound
        }

        // 剩余文本
        if lastEnd < paragraph.endIndex {
            let remaining = String(paragraph[lastEnd...])
            if !remaining.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append((remaining, 0))
            }
        }

        return result
    }

    private func detectSpeaker(for text: String, before index: String.Index) -> Int32 {
        // 简单启发式：根据前文最近的说话人提示判断
        // 实际可用 NLP 模型或规则库改进
        let prefix = String(text[..<index])

        for (i, char) in characters.enumerated() {
            if prefix.contains(char.name) || char.aliases.contains(where: { prefix.contains($0) }) {
                return char.defaultSpeakerId
            }
        }

        return 0  // 默认
    }
}
```

### 5.3 中文多音字预处理

```swift
/// 多音字处理器
class PolyphoneResolver {

    /// 常见多音字规则库
    private let polyphoneRules: [String: [String: String]] = [
        "长": [
            "长度": "cháng", "长短": "cháng", "长江": "cháng",
            "长大": "zhǎng", "成长": "zhǎng", "校长": "zhǎng"
        ],
        "行": [
            "行走": "xíng", "行动": "xíng", "进行": "xíng",
            "银行": "háng", "行业": "háng", "行列": "háng"
        ],
        "重": [
            "重要": "zhòng", "重量": "zhòng", "重视": "zhòng",
            "重复": "chóng", "重新": "chóng", "重叠": "chóng"
        ],
        "还": [
            "还有": "hái", "还是": "hái", "还好": "hái",
            "归还": "huán", "还钱": "huán", "偿还": "huán"
        ],
        "地": [
            "地方": "dì", "地球": "dì", "土地": "dì",
            "慢慢地": "de", "高兴地": "de", "认真地": "de"
        ],
        "得": [
            "得到": "dé", "获得": "dé", "取得": "dé",
            "跑得快": "de", "说得好": "de", "做得好": "de",
            "要不得": "děi", "得去": "děi"
        ],
        "着": [
            "看着": "zhe", "听着": "zhe", "走着": "zhe",
            "着火": "zháo", "着急": "zháo", "睡着": "zháo",
            "着陆": "zhuó", "着手": "zhuó", "穿着": "zhuó"
        ],
        "了": [
            "好了": "le", "走了": "le", "吃了": "le",
            "了解": "liǎo", "了不起": "liǎo", "明了": "liǎo"
        ]
    ]

    /// 处理文本中的多音字，返回带拼音标注的文本 (用于 SSML)
    func resolve(_ text: String) -> String {
        var result = text

        for (char, rules) in polyphoneRules {
            for (context, pinyin) in rules {
                // 简单替换：在上下文中标注拼音
                // 实际应使用更精确的上下文分析
                if result.contains(context) {
                    // 使用 SSML phoneme 标签
                    let ssml = "<phoneme alphabet=\"py\" ph=\"\(pinyin)\">\(char)</phoneme>"
                    result = result.replacingOccurrences(of: context, with: ssml)
                }
            }
        }

        return result
    }

    /// 生成 SSML 文本 (Sherpa-ONNX 有限支持)
    func toSSML(_ text: String) -> String {
        let resolved = resolve(text)
        return "<speak>\(resolved)</speak>"
    }
}
```

### 5.4 音频缓冲与预加载管理

```swift
/// TTS 音频缓冲管理器
class TTSBufferManager {

    private var buffer: [(text: String, audio: TTSResult?, speakerId: Int32)] = []
    private let maxBufferSize = 10
    private var currentIndex = 0
    private let ttsManager: SherpaOnnxTTSManager
    private let preloadQueue = DispatchQueue(label: "com.yourapp.tts.preload", qos: .background)

    init(ttsManager: SherpaOnnxTTSManager) {
        self.ttsManager = ttsManager
    }

    /// 加载章节文本到缓冲区
    func loadChapter(sentences: [String], speakerMap: [Int: Int32]) {
        buffer = sentences.enumerated().map { index, text in
            (text: text, audio: nil, speakerId: speakerMap[index, default: 0])
        }
        currentIndex = 0

        // 预加载前 3 句
        preloadAhead(from: 0, count: 3)
    }

    /// 获取当前句子的音频 (如果没有则实时合成)
    func getCurrentAudio() -> TTSResult? {
        guard currentIndex < buffer.count else { return nil }

        // 如果已缓存，直接返回
        if let audio = buffer[currentIndex].audio {
            return audio
        }

        // 实时合成
        let item = buffer[currentIndex]
        let result = ttsManager.synthesize(
            text: item.text,
            speakerId: item.speakerId,
            speed: 1.0
        )

        // 缓存结果
        buffer[currentIndex].audio = result

        // 预加载后续
        preloadAhead(from: currentIndex + 1, count: 2)

        return result
    }

    /// 前进到下一句
    func next() -> Bool {
        guard currentIndex < buffer.count - 1 else { return false }
        currentIndex += 1
        return true
    }

    /// 后退到上一句
    func previous() -> Bool {
        guard currentIndex > 0 else { return false }
        currentIndex -= 1
        return true
    }

    /// 跳转到指定句子
    func seek(to index: Int) -> Bool {
        guard index >= 0 && index < buffer.count else { return false }
        currentIndex = index
        preloadAhead(from: index, count: 3)
        return true
    }

    /// 后台预加载
    private func preloadAhead(from index: Int, count: Int) {
        preloadQueue.async { [weak self] in
            guard let self = self else { return }

            for i in index..<min(index + count, self.buffer.count) {
                if self.buffer[i].audio == nil {
                    let item = self.buffer[i]
                    self.buffer[i].audio = self.ttsManager.synthesize(
                        text: item.text,
                        speakerId: item.speakerId,
                        speed: 1.0
                    )
                }
            }

            // 清理过远的缓存
            self.cleanupCache(keepAround: index)
        }
    }

    /// 清理远离当前位置的缓存，控制内存
    private func cleanupCache(keepAround current: Int) {
        for i in 0..<buffer.count {
            if abs(i - current) > maxBufferSize && buffer[i].audio != nil {
                buffer[i].audio = nil  // 释放内存
            }
        }
    }

    /// 当前进度
    var progress: (current: Int, total: Int) {
        return (currentIndex + 1, buffer.count)
    }
}
```

---

## 6. 性能调优与资源管理

### 6.1 内存优化策略

| 策略 | 实现方式 | 效果 |
|------|---------|------|
| **模型按需加载** | 不使用时卸载模型，释放 ONNX Runtime 内存 | 节省 100-200MB |
| **音频缓存 LRU** | 只缓存当前章节前后 10 句的音频 | 控制内存 < 50MB |
| **后台合成限制** | 最多 2 个后台合成任务 | 避免 CPU 过载 |
| **低内存降级** | 内存紧张时切换到 Piper (22MB) | 保证基础功能 |

### 6.2 线程配置建议

```swift
// iPhone 设备线程建议
let deviceModel = UIDevice.current.model
let numThreads: Int32 = {
    switch deviceModel {
    case "iPhone":
        // 根据处理器代际调整
        if ProcessInfo.processInfo.processorCount >= 6 {
            return 4  // A15+ 可用 4 线程
        } else {
            return 2  // 旧设备 2 线程
        }
    case "iPad":
        return 4  // iPad 通常性能更好
    default:
        return 2
    }
}()
```

### 6.3 App 包大小优化

```
策略:
1. 模型不作为 Bundle 资源打包，改为 App 内下载
2. 首次启动时引导用户下载所需语言模型
3. 支持模型压缩包 (tar.bz2) 下载后解压
4. 提供 "精简版" (Piper, 22MB) 和 "完整版" (Kokoro, 82MB) 选项
```

### 6.4 电池与发热优化

- **合成批次控制**: 不要一次性合成整章，按句子/段落分批
- **后台暂停**: App 进入后台时暂停合成队列
- **低电量模式**: 检测到 Low Power Mode 时自动降低线程数、切换轻量模型

---

## 7. 常见问题与解决方案

### Q1: 构建时提示 "CMake Error at toolchains/ios.toolchain.cmake"

**解决**:
```bash
sudo xcode-select --install
sudo xcodebuild -license
rm -rf build-ios
./build-ios.sh
```

### Q2: 运行时崩溃 "Library not loaded: @rpath/sherpa-onnx.xcframework"

**解决**: 检查 Build Settings:
```
FRAMEWORK_SEARCH_PATHS = $(PROJECT_DIR)/../../build-ios
LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/Frameworks
```

### Q3: 中文多音字读错

**解决**: Sherpa-ONNX 引擎本身不解决多音字，需要在应用层预处理：
1. 使用 `pypinyin` 或自定义规则库标注拼音
2. 通过 SSML `<phoneme>` 标签指定发音 (部分模型支持)
3. 建立小说领域专用词典

### Q4: 音频播放有爆音/杂音

**解决**:
- 检查样本数据范围是否在 [-1.0, 1.0]
- 确保 WAV 文件头正确写入
- 使用 `AVAudioSession` 正确配置音频会话

### Q5: 模型文件太大，App 超过 200MB OTA 限制

**解决**:
- 模型改为运行时下载 (On-Demand Resources 或自定义下载)
- 使用 `tar.bz2` 压缩格式
- 提供模型选择界面，用户按需下载

### Q6: Kokoro 多说话人如何知道有哪些 speaker ID 可用？

**解决**: `voices.bin` 文件包含说话人信息，可以通过以下方式获取数量：
```swift
// 在 SherpaOnnxTTSManager 中添加
func getNumSpeakers() -> Int32 {
    guard let tts = tts else { return 0 }
    return SherpaOnnxOfflineTtsNumSpeakers(tts)
}
```

---

## 8. 参考资源

### 官方文档

- [Sherpa-ONNX 官方文档](https://k2-fsa.github.io/sherpa/onnx/index.html)
- [iOS 构建指南](https://k2-fsa.github.io/sherpa/onnx/ios/build-sherpa-onnx-swift.html)
- [Swift API 示例](https://k2-fsa.github.io/sherpa/onnx/swift-api/examples.html)
- [TTS 预训练模型列表](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/index.html)

### GitHub 仓库

- [Sherpa-ONNX 主仓库](https://github.com/k2-fsa/sherpa-onnx)
- [iOS TTS 示例代码](https://github.com/k2-fsa/sherpa-onnx/tree/master/ios-swiftui/SherpaOnnxTts)
- [Swift API 示例](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples)
- [React Native 封装](https://github.com/XDcobra/react-native-sherpa-onnx)

### 模型下载

- [Hugging Face - Sherpa-ONNX TTS Samples](https://huggingface.co/csukuangfj/sherpa-onnx-tts-samples)
- [GitHub Releases - TTS Models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models)

### 社区项目参考

- [VoxSherpa TTS](https://github.com/CodeBySonu95/VoxSherpa-TTS) — Android 离线 TTS，支持 Kokoro + Piper
- [BreezeApp](https://github.com/k2-fsa/sherpa-onnx) — MediaTek 开发的 iOS/Android 离线 AI 应用

---

## 附录: 快速启动检查清单

- [ ] macOS + Xcode 14.2+ 已安装
- [ ] CMake 已安装 (`brew install cmake`)
- [ ] 克隆 `sherpa-onnx` 仓库
- [ ] 执行 `./build-ios.sh` 成功
- [ ] 下载 Kokoro 或 Piper 中文模型
- [ ] 创建 Xcode 项目并添加 `.xcframework`
- [ ] 配置 Bridging Header 和 Build Settings
- [ ] 实现 `SherpaOnnxTTSManager` 封装类
- [ ] 测试基础 TTS 功能
- [ ] 实现文本分句和角色识别
- [ ] 添加多音字预处理
- [ ] 优化内存和性能
- [ ] 处理模型下载和更新逻辑

---

> **提示**: 本指南基于 Sherpa-ONNX 最新稳定版本。API 可能随版本更新而变化，建议关注 [GitHub Releases](https://github.com/k2-fsa/sherpa-onnx/releases) 获取最新信息。
