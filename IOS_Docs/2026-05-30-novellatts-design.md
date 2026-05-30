# NovellaTTS 设计文档

> **创建日期**：2026-05-30  
> **状态**：已确认，待实现  
> **分支**：IOS-NewLook → 合入 IOS  

---

## 1. 背景与目标

现有 TTS 基于 iOS 系统 `AVSpeechSynthesizer`，音质有限，无法区分角色声音。

**目标**：在 iOS 小说阅读器 App 中实现高质量、角色感知的流式朗读系统，支持：

- 角色声音自动区分（旁白 / 男主 / 女主 / 配角）
- 语气语调感知（轻声 / 怒吼 / 哭泣等情态词映射参数）
- 用户自定义音色克隆（参考音频 < 3 秒）
- 流式播放（句级流水线，首字延迟 ≤ 500ms）
- 平滑升级路径（Phase 1 → Phase 2 仅替换引擎层）

---

## 2. 架构方案：并行预处理 + 流式 TTS（方案 B）

```
章节载入时（后台异步）
  LLMCharacterAnalyzer 分析全章 → 建立 CharacterVoiceMap

点击朗读时
  SentenceQueue → TextNormalizer → SentenceSplitter
       │
       ├── DialogueRuleEngine（规则匹配说话人，< 1ms）
       │         └── 失败时 → LLMCharacterAnalyzer（实时，100-200ms）
       │
       ├── VoiceRegistry（角色 → VoiceConfig + SpeakingStyle）
       │
       └── TTSEngine（逐句合成，并发预生成 2 句缓冲）
                 │
           AudioPipeline（AVAudioEngine 流式播放）
                 │
           speakingRange 回调 → UI 高亮 + 自动翻页
```

---

## 3. 组件边界

| 组件 | 职责 | 依赖 |
|------|------|------|
| `NovellaTTSEngine` | 主控协调器，替代现有 `TTSManager` | 以下全部 |
| `TextNormalizer` | 数字/日期/符号 → 可读文本 | 纯 Swift |
| `SentenceSplitter` | 章节文本 → `[SentenceUnit]` | 纯 Swift |
| `CharacterDetector` | 句子 → `SpeechInstruction`（谁说+怎么说）| 规则 + LLM |
| `DialogueRuleEngine` | 正则匹配说话标记（如"林峰说/道"）| 纯 Swift |
| `LLMCharacterAnalyzer` | Qwen3-0.6B 章节预处理 + 实时 fallback | llama.cpp / MLX |
| `VoiceRegistry` | 角色 ID → VoiceConfig，管理预设+克隆 | 本地存储 |
| `VoiceCloneManager` | 用户录音 → speaker embedding 提取 + 持久化 | Sherpa-ONNX |
| `SherpaKokoroEngine` | Kokoro 文本→PCM（Phase 1）| Sherpa-ONNX XCFramework |
| `ZipVoiceEngine` | ZipVoice 文本→PCM（Phase 2）| Sherpa-ONNX XCFramework |
| `AudioPipeline` | PCM 缓冲 + AVAudioEngine 流式播放 | AVFoundation |

### 目录结构

```
App/Features/TTS/
├── NovellaTTSEngine.swift
├── Pipeline/
│   ├── TextNormalizer.swift
│   ├── SentenceSplitter.swift
│   └── AudioPipeline.swift
├── CharacterDetection/
│   ├── CharacterDetector.swift
│   ├── DialogueRuleEngine.swift
│   ├── CharacterVoiceMap.swift
│   ├── CharacterProfile.swift
│   └── LLMCharacterAnalyzer.swift
├── VoiceRegistry/
│   ├── VoiceRegistry.swift
│   ├── PresetVoice.swift
│   └── VoiceCloneManager.swift
└── Engines/
    ├── TTSEngine.swift            ← 协议定义
    ├── SherpaKokoroEngine.swift   ← Phase 1
    └── ZipVoiceEngine.swift       ← Phase 2（桩，待实现）
```

---

## 4. 文本归一化（TextNormalizer）

纯 Swift 规则，按优先级顺序执行，无网络/模型依赖：

| 规则 | 示例输入 | 示例输出 |
|------|---------|---------|
| 千分位金额 | `1,234.56元` | `一千二百三十四点五六元` |
| 年份（4位）| `2024年` | `二零二四年` |
| 月日 | `10月1日` | `十月一日` |
| 时间 | `14:30` | `十四点三十分` |
| 纯整数 ≤ 9999 | `3` | `三` |
| 纯整数 ≥ 10000 | `12000` | `一万两千` |
| 百分比 | `98%` | `百分之九十八` |
| 连续停顿符 | `……` `——` | `<pause>` 标记 |
| HTML 实体/零宽字符 | `&nbsp;` `​` | 删除 |

---

## 5. 断句（SentenceSplitter）

**策略**：硬边界强制断句 + 长句按软边界二次分割：

- **硬边界**（必须断）：`。！？…\n`
- **软边界**（句长 > 50 字时断）：`，；：`
- **最大句长**：80 字（超出在最近软边界截断）
- **最小句长**：5 字（太短与后一句合并）

```swift
struct SentenceUnit {
    let index: Int              // 在章节中的顺序
    let text: String            // 归一化后文本
    let charOffset: Int         // 章节字符偏移（与 pageStartOffset 坐标一致）
    let charLength: Int
    let speechInstruction: SpeechInstruction
}
```

---

## 6. 角色检测（CharacterDetector）

### 6.1 两层检测流程

```
章节载入 ──► LLMCharacterAnalyzer.analyzeChapter()
                → CharacterVoiceMap（角色表，后台异步完成）

朗读时每句 ──► DialogueRuleEngine.detect(sentence)
                → 命中（~80%）：直接返回 SpeakerID
                → 未命中：LLMCharacterAnalyzer.detectSpeaker(sentence, context)
                              → 返回 SpeakerID（100-200ms）
```

### 6.2 DialogueRuleEngine 规则

**实际覆盖格式（命中率约 70-75%）：**

| 覆盖级别 | 格式示例 | 匹配方式 |
|---------|---------|---------|
| ✅ 完全覆盖 | `林峰冷声道："我不去。"` | 姓名 + 说话动词 + 引号 |
| ✅ 完全覆盖 | `"我不去，"林峰道。` | 引号 + 姓名 + 说话动词 |
| ✅ 完全覆盖 | `"我不去。"林峰皱眉。` | 引号结束后紧接人名 |
| ✅ 完全覆盖 | `林峰：「我不去。」` | 姓名 + 冒号 + 书名号 |
| ✅ 完全覆盖 | `林峰："我不去。"` | 姓名 + 冒号 + 引号 |
| ⚠️ 部分覆盖 | `"走。"林峰看了她一眼，"你别拦我。"` | 第二段引号需上下文，置信度低 |
| ⚠️ 部分覆盖 | `【林峰】：内容` `<林峰>内容` | 特殊标记格式，需按书源扩展规则 |
| ❌ 不覆盖→LLM | `"走。"` | 纯引号无人名，规则无法判断 |
| ❌ 不覆盖→LLM | `他冷声道："走。"` | 代词替代姓名，无法从规则知道"他"是谁 |
| ❌ 不覆盖→LLM | 两人交替对话无标注 | 上下文推断，只能靠 LLM |

说话动词词典（可配置扩展）：
`说 道 问 答 喊 叫 笑 哭 骂 低声 大声 沉声 淡淡 冷声 厉声 笑道 叹道 嗤道 喝道 怒道`

未命中 → 返回 nil → 交给 `LLMCharacterAnalyzer`（已有角色表，实时推断约 100-200ms）。

### 6.3 LLMCharacterAnalyzer

**章节预处理 Prompt（建角色表）**：
```
分析以下小说片段，列出所有角色，输出 JSON：
{"characters": [
  {"name": "林峰", "gender": "male", "age": "young",
   "role": "protagonist", "personality": "冷峻"},
  ...
]}
片段（前2000字）：{text}
```

**实时 fallback Prompt**：
```
上文：{前2句}
当前句：{当前句}
已知角色：{角色列表}
谁在说话？只回答角色名或"旁白"，不超过4个字。
```

**LLM Backend 选择**：
```swift
enum LLMBackend { case llamaCpp, mlx }
// A14-A16 → llama.cpp（Qwen3-0.6B-Q4_K_M.gguf）
// A17+    → MLX（Qwen3-0.6B-4bit）
// 两者实现同一 LLMInference 协议
```

### 6.4 角色画像与声音自动分配

```swift
struct CharacterProfile {
    let name: String
    let gender: Gender          // male / female / unknown
    let ageGroup: AgeGroup      // child / young / adult / elder
    let role: CharacterRole     // protagonist / heroine / villain / supporting
    let personality: String     // "冷峻" / "温柔" 等（用于未来扩展）
}
```

分配逻辑：

| gender + age + role | 分配声音 |
|--------------------|---------|
| male + young + protagonist | `protagonist` |
| female + young + heroine | `heroine` |
| male + elder + any | `elder_male` |
| any + child + any | `child` |
| male + any + villain | `villain` |
| 其他 | 按 gender 循环分配 `neutral_m/f` |

### 6.5 语气语调参数（SpeakingStyle）

从对话标记中提取情态词，映射为 TTS 参数调整：

```swift
struct SpeakingStyle {
    var rateMultiplier: Float   = 1.0
    var pitchOffset: Float      = 0.0   // 在 AVAudioUnitTimePitch 层应用
    var volumeMultiplier: Float = 1.0
}
```

| 情态词 | rate | pitch | volume |
|-------|------|-------|--------|
| 轻声/低声道 | -15% | -5% | -10% |
| 大声/厉声喝道 | +10% | +8% | +15% |
| 哭泣着说/泣道 | -20% | -3% | -5% |
| 冷冷地说/淡淡道 | -10% | -8% | 0% |
| 笑着说/笑道 | +5% | +5% | +5% |
| 怒吼/怒喝 | +15% | +15% | +20% |

### 6.6 SpeechInstruction

```swift
struct SpeechInstruction {
    let speakerID: SpeakerID
    let voiceConfig: VoiceConfig
    let styleParams: SpeakingStyle
}
```

---

## 7. TTS 引擎层

### 7.1 TTSEngine 协议

```swift
protocol TTSEngine {
    func synthesize(
        text: String,
        voice: VoiceConfig,
        style: SpeakingStyle,
        onChunk: @escaping (AudioChunk) -> Void,
        onComplete: @escaping () -> Void
    ) async throws
    func warmup() async
    var isReady: Bool { get }
}
```

### 7.2 Phase 1：SherpaKokoroEngine

- **模型**：`kokoro-multi-lang-v1.1-int8`，140MB
- **集成**：Sherpa-ONNX XCFramework via SPM，官方有完整 iOS SwiftUI Demo
- **流式策略**：句级流水线（并发预生成 2 句），模拟流式效果
- **SpeakingStyle 应用**：rate 在 Kokoro 参数层，pitch/volume 在 AudioPipeline AVAudioEngine 层

### 7.3 Phase 2：ZipVoiceEngine

- **模型**：`sherpa-onnx-zipvoice-distill-int8-zh-en-emilia`，104MB + vocoder 52MB = 156MB
- **优势**：Flow Matching 架构，中文质量优于 Kokoro；原生零样本音色克隆
- **切换成本**：仅替换 `Engines/ZipVoiceEngine.swift`，上层架构不变

### 7.4 Phase 3（待条件成熟）：ZipVoice-Dialog

- 官方已确认"尚未支持对话模型 ONNX"（截至 2025 年末）
- 设 GitHub 监控（`k2-fsa/sherpa-onnx` + `k2-fsa/ZipVoice`），待 ONNX 就绪评估
- 届时作为 `TTSEngine` 的第三个实现插入，架构无需改动

---

## 8. 音色管理（VoiceRegistry）

### 8.1 预设音色库（8个角色槽位）

> **注意**：Kokoro multi-lang v1.1 共 103 个 speaker，Speaker ID 需在集成阶段试听确认。
> 下表角色槽位已定，具体 Speaker ID 在 Phase 1a 集成工作中由人工试听后填入。

| 角色槽位 ID | 名称 | Kokoro Speaker ID | 音色特征 |
|------------|------|------------------|---------|
| `narrator` | 旁白 | 待集成后试听确定 | 中性偏稳，清晰不突兀 |
| `protagonist` | 男主 | 待集成后试听确定 | 青年男声，有力度 |
| `heroine` | 女主 | 待集成后试听确定 | 青年女声，清亮 |
| `elder_male` | 老者 | 待集成后试听确定 | 成熟低沉男声 |
| `young_female` | 少女 | 待集成后试听确定 | 清甜偏高女声 |
| `villain` | 反派 | 待集成后试听确定 | 低沉冷峻男声 |
| `child` | 孩童 | 待集成后试听确定 | 童声，偏高 |
| `neutral` | 通用备用 | 待集成后试听确定 | 中性兜底声音 |

**Phase 1a 专项工作**：集成 Sherpa-ONNX + Kokoro 后，对全部 103 个 speaker 生成
15 秒中文样本，由产品确认每个角色槽位对应哪个 Speaker ID，耗时约半天。

### 8.2 用户音色克隆（VoiceCloneManager）

**录音要求**（ZipVoice 官方建议）：
- 时长：**< 3 秒**（过长降速降质）
- 格式：WAV，16kHz / 24kHz，单声道
- 内容：自然说话片段（无需朗读固定文本）

**流程**：
```
1. 引导 UI 录音（2-3秒自然说话）
2. AVAudioRecorder → WAV
3. SherpaKokoroEngine/ZipVoiceEngine.extractEmbedding(WAV) → Float[] embedding
4. VoiceCloneManager.save(embedding, name) → 持久化
5. VoiceRegistry.register(clonedVoice) → 可分配给角色
```

**存储路径**：
```
Documents/VoiceClones/
├── {uuid}.embedding    (Float32 binary，~512B)
└── {uuid}.meta.json    {"name": "我的声音", "created": "2026-05-30T10:00:00Z"}
```

---

## 9. 音频流水线（AudioPipeline）

### 9.1 AVAudioEngine 图

```
AVAudioPlayerNode（PCM 输入）
  └── AVAudioUnitTimePitch（pitch/rate 实时微调）
        └── AVAudioMixerNode
              └── outputNode（扬声器）
```

选用 AVAudioEngine 而非直接 AVAudioPlayer，原因：支持 `SpeakingStyle.pitchOffset` 实时应用，无需重新合成。

### 9.2 句级流水线

```
生成池（并发 2 句）：
  句 N 合成中 ──► 句 N 播放
  句 N+1 合成中 ──────► 句 N+1 播放
  句 N+2 合成中 ──────────► 句 N+2 播放

首字延迟目标：≤ 500ms
```

### 9.3 speakingRange 回调

```swift
// 每句播放完成时更新，与现有高亮+翻页系统完全兼容
playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) {
    DispatchQueue.main.async {
        self.speakingRange = NSRange(
            location: sentence.charOffset,
            length: sentence.charLength
        )
    }
}
```

`speakingRange` 坐标系与现有 `pageStartOffset` 一致（均基于 `\n\n→\n` 归一化后的章节文本）。

### 9.4 暂停/恢复

```swift
pause():  playerNode.pause() + generationPool.suspend()
resume(): playerNode.play()  + generationPool.resume()
// pause 保留已 schedule 的 buffer，resume 从中断位置继续
```

---

## 10. 与现有系统集成

### 10.1 迁移策略

`NovellaTTSEngine` 暴露与 `TTSManager` **相同的公开接口**，`ReaderViewModel` 无需修改：

```swift
// 保持不变
func speak(_ text: String, bookName: String, chapterTitle: String, onFinish: @escaping () -> Void)
func pause() / resume() / stop()
@Published var isPlaying: Bool
@Published var speakingRange: NSRange?
@Published var remainingSeconds: Int?
```

`ReaderViewModel.ttsManager` 类型改为 `any TTSProtocol`，用户可在设置里选择"系统 TTS / 高质量 TTS"。

### 10.2 现有功能复用

- 朗读高亮：`MixedContentView.allHighlights()` 不变
- 自动翻页：`ReaderViewModel.subscribeToTTSSpeakingRange()` 不变
- 定时停止：`TTSProtocol` 包含 `startTimer/cancelTimer`，逻辑不变

---

## 11. 实现阶段

### Phase 1a：基础设施（约 3 周）
- `TextNormalizer` + `SentenceSplitter`
- `SherpaKokoroEngine`（固定单一声音跑通流程）
- `AudioPipeline`（流式播放 + speakingRange 回调）
- `NovellaTTSEngine` 接口对齐，与 `ReaderViewModel` 对接

### Phase 1b：角色系统（约 2 周）
- `DialogueRuleEngine`（规则匹配）
- `CharacterVoiceMap` + `VoiceRegistry`（8 个预设声音）
- `CharacterProfile` 自动分配声音
- `SpeakingStyle` 情态词映射

### Phase 1c：LLM + 克隆（约 2 周）
- `LLMCharacterAnalyzer`（llama.cpp / MLX 双 backend）
- `VoiceCloneManager`（用户录音 < 3 秒，embedding 提取）
- 低内存设备自动降级为纯规则模式

### Phase 2：ZipVoice 引擎升级（约 1 周）
- 替换 `Engines/ZipVoiceEngine.swift`
- 验证音质提升和 Voice Clone 效果

### Phase 3（条件成熟后）：ZipVoice-Dialog
- 监控 `k2-fsa/sherpa-onnx` ONNX 支持进度
- 就绪后作为第三引擎实现插入

---

## 12. 技术风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Sherpa-ONNX iOS 集成（Kokoro）| 低 | 高 | 官方完整 iOS SwiftUI Demo 可参考 |
| Kokoro 中文质量不及预期 | 中 | 中 | Phase 2 ZipVoice 可快速切换（TTSEngine 协议隔离）|
| Qwen3-0.6B 内存超限（低端机）| 中 | 中 | 低内存自动降级纯规则模式 |
| llama.cpp Swift 绑定不稳定 | 低 | 高 | 锁定版本，协议封装隔离 |
| Voice Clone 效果差 | 低 | 低 | 参考音频仅 < 3 秒，低门槛；引导 UI 降噪预处理 |
| ZipVoice-Dialog ONNX 长期不发布 | 高 | 低 | 架构不依赖对话模型，CharacterDetector 实现多角色效果 |

---

## 13. 不在本期范围

- 第三方 TTS 云服务（在线模式）
- 后台持续播放 / 控制中心集成（现有锁屏控制已实现，此处不扩展）
- 方言支持（粤语等）
- 情感 TTS 模型（超出当前模型能力边界）
