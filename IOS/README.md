# Legado iOS

Android 版 [Legado](https://github.com/gedoor/legado) 小说阅读器的 iOS 移植，使用 SwiftUI 重写。

## 功能特性

- 书源管理（导入 / 检测 / 调试 / 深度检查）
- 全书源并发搜索
- 发现 / 分类浏览（HTML + JSON 书源）
- 分页阅读器（TextKit 2，支持 CJK 禁则、文字选择）
- 目录 / 书签 / 高亮划线 / 书内搜索
- 正文图片渲染、TTS 朗读（ZipVoice 零样本声音克隆）
- WebDAV 云同步

---

## 环境要求

| 项目 | 版本 |
|------|------|
| Xcode | 26.0 或更高 |
| iOS 部署目标 | 16.0+ |
| Swift | 5.9+ |
| macOS（开发机） | 15.0+ |

---

## 快速开始

```bash
git clone git@github.com:cl7502/legado.git
cd legado/IOS
```

Swift Package Manager 依赖（Alamofire / SwiftSoup / GRDB）会在 Xcode 首次打开时**自动下载**，无需手动操作。

**需要手动下载**的有两类：大型二进制框架 + TTS 模型（详见下方）。

---

## 手动依赖配置

> 这两类文件超过 GitHub 100 MB 限制，不纳入版本控制，需要在本地手动放置后才能编译和使用 TTS。

### 1. ONNX Runtime xcframework

TTS 引擎（Sherpa-ONNX）依赖 ONNX Runtime 静态框架。

**目标路径：**
```
IOS/Legado/Frameworks/onnxruntime.xcframework/
```

**下载来源：** Sherpa-ONNX 的 iOS 发布包已内含匹配版本的 onnxruntime，推荐直接从 sherpa-onnx 的 Release 包中提取（见下方第 2 步）。

若需单独下载，在 [microsoft/onnxruntime Releases](https://github.com/microsoft/onnxruntime/releases) 页面找到与 Sherpa-ONNX 版本兼容的包（当前项目使用 ORT API Version 17，对应 onnxruntime ≥ 1.17）。

---

### 2. Sherpa-ONNX xcframework

**目标路径：**
```
IOS/Legado/Frameworks/sherpa-onnx.xcframework/
```

**下载步骤：**

1. 前往 [k2-fsa/sherpa-onnx Releases](https://github.com/k2-fsa/sherpa-onnx/releases)
2. 找到最新版本，下载 iOS 专用压缩包，文件名格式为：
   ```
   sherpa-onnx-v{VERSION}-ios.tar.bz2
   ```
3. 解压后将 `sherpa-onnx.xcframework` 和 `onnxruntime.xcframework` 复制到：
   ```
   IOS/Legado/Frameworks/
   ```

**解压命令示例：**
```bash
# 下载（以 1.10.x 为例，请替换为实际最新版本号）
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.10.x/sherpa-onnx-v1.10.x-ios.tar.bz2
tar -xjf sherpa-onnx-v1.10.x-ios.tar.bz2
cp -r sherpa-onnx.xcframework  legado/IOS/Legado/Frameworks/
cp -r onnxruntime.xcframework   legado/IOS/Legado/Frameworks/
```

**目录结构确认：**
```
IOS/Legado/Frameworks/
├── sherpa-onnx.xcframework/
│   ├── ios-arm64/
│   ├── ios-arm64_x86_64-simulator/
│   └── Headers/
└── onnxruntime.xcframework/
    ├── ios-arm64/
    ├── ios-arm64_x86_64-simulator/
    └── macos-arm64_x86_64/
```

---

### 3. ZipVoice TTS 模型

TTS 朗读功能使用 [ZipVoice](https://github.com/k2-fsa/sherpa-onnx) 零样本声音克隆模型（中英双语）。**不配置此项时，TTS 功能不可用，其余功能不受影响。**

**目标路径：**
```
IOS/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia/
```

**下载来源：** HuggingFace

```bash
# 方法 A：使用 huggingface-cli（推荐）
pip install huggingface_hub
huggingface-cli download k2-fsa/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia \
  --local-dir legado/IOS/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia

# 方法 B：手动从 HuggingFace 网页下载
# https://huggingface.co/k2-fsa/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia
```

**必需文件：**

| 文件 | 大小（约） | 说明 |
|------|-----------|------|
| `encoder.int8.onnx` | ~120 MB | 编码器（量化版） |
| `decoder.int8.onnx` | ~119 MB | 解码器（量化版） |
| `vocos_24khz.onnx` | ~52 MB | Vocoder 声码器 |
| `tokens.txt` | < 1 MB | 词表 |
| `lexicon.txt` | < 1 MB | 词典 |
| `espeak-ng-data/` | ~2 MB | 音素数据目录 |

**目录结构确认：**
```
IOS/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia/
├── encoder.int8.onnx
├── decoder.int8.onnx
├── vocos_24khz.onnx
├── tokens.txt
├── lexicon.txt
└── espeak-ng-data/
    ├── af_dict
    ├── am_dict
    └── ...（其余语言数据）
```

> **注意：** 模型体积较大（合计约 300 MB），下载时间视网络而定。国内网络访问 HuggingFace 可能需要代理。

---

## 参考音频（已内置）

声音克隆所需的参考音频文件已随代码一起提交，无需额外下载：

```
IOS/Legado/App/Resources/VoiceReferences/
├── ref_tingting.wav
├── ref_meijia.wav
├── ref_narrator_f.wav
├── ref_narrator_f2.wav
├── ref_male_mature.wav
└── ref_male_low.wav
```

如需添加自定义声音，将 WAV 文件（推荐 16 kHz / 16-bit 单声道，3-10 秒）放入此目录，并在 `preset_voices.json` 中配置。

---

## 构建步骤

完成上述依赖配置后：

1. 用 Xcode 打开 `IOS/Legado.xcodeproj`
2. 选择目标设备（真机或模拟器）
3. 等待 SPM 自动解析完成
4. `Cmd + B` 构建 / `Cmd + R` 运行

**模拟器注意事项：**

- 模拟器使用 `ios-arm64_x86_64-simulator` slice，真机使用 `ios-arm64` slice，Xcode 自动选择
- TTS 在模拟器上可正常运行（框架包含 x86_64 + arm64 通用 slice）

---

## 依赖汇总

| 依赖 | 来源 | 管理方式 |
|------|------|---------|
| Alamofire 5.8+ | GitHub | Swift Package Manager（自动） |
| SwiftSoup 2.7+ | GitHub | Swift Package Manager（自动） |
| GRDB 6.24+ | GitHub | Swift Package Manager（自动） |
| sherpa-onnx.xcframework | k2-fsa/sherpa-onnx Releases | **手动下载** |
| onnxruntime.xcframework | 随 sherpa-onnx 发布包一起 | **手动下载** |
| ZipVoice 模型 | HuggingFace k2-fsa | **手动下载**（TTS 可选） |
| VoiceReferences（参考音频） | 本仓库 | 已内置 |

---

## 常见问题

**Q: 编译报错 `framework not found sherpa-onnx`**  
A: 检查 `IOS/Legado/Frameworks/sherpa-onnx.xcframework/` 是否存在，路径不对会导致 Xcode 找不到框架。

**Q: 编译报错 `framework not found onnxruntime`**  
A: 同上，检查 `IOS/Legado/Frameworks/onnxruntime.xcframework/` 路径。

**Q: TTS 按钮灰色 / 不可用**  
A: 检查 `IOS/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia/` 目录是否存在且包含全部必需文件（尤其是 `encoder.int8.onnx`）。

**Q: GRDB submodule 报错（删除 DerivedData 后）**  
A: 执行以下命令修复：
```bash
git -C ~/Library/Developer/Xcode/DerivedData/SourcePackages/checkouts/GRDB.swift \
  submodule deinit SQLiteCustom/src
```

**Q: 首次启动模拟器报 `FBSOpenApplicationServiceErrorDomain Code 1`**  
A: 清空模拟器后重装：
```bash
xcrun simctl erase <SIMULATOR_UUID>
```
