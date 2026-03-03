# 本地翻译 (Translator)

基于 **macOS 系统自带** 的翻译与语言识别能力实现的本地双语翻译应用，无需联网、无需 API Key。

## 功能

- **双语互译**：在两种语言之间互相翻译（如 中文 ↔ English）
- **自动检测输入语言**：使用系统 Natural Language 框架识别当前输入是哪种语言
- **自动选择翻译方向**：根据检测结果自动从「语言 A → 语言 B」或「语言 B → 语言 A」翻译
- **完全本地**：使用 Apple Translation 框架，翻译在设备上完成，不依赖网络

## 系统要求

- **macOS 15.0 (Sequoia)** 或更高（Translation 框架要求）
- **Xcode 16** 或更高（若需自行编译）

首次使用某对语言时，系统可能会提示下载对应语言包，同意即可。

## 如何运行

1. 用 **Xcode** 打开项目：
   - 双击 `Translator.xcodeproj`，或在 Xcode 中选择 **File → Open** 打开该文件。
2. 选择运行目标为 **My Mac**。
3. 点击 **Run (⌘R)** 编译并运行。

> 说明：Translation 框架在模拟器上可能不可用，建议在真机 Mac 上运行。

## 使用方式

1. 在顶部选择 **语言 A** 和 **语言 B**（例如：简体中文 与 English）。
2. 在左侧输入框中输入或粘贴要翻译的文本。
3. 点击 **「翻译」**：
   - 应用会先自动检测输入语言（显示「检测到: xxx」）。
   - 若检测为语言 A，则翻译成语言 B；若为语言 B，则翻译成语言 A。
4. 译文会显示在右侧区域。

## 技术说明

- **语言检测**：`NaturalLanguage.NLLanguageRecognizer`
- **翻译**：`Translation.TranslationSession`（系统内置、设备端翻译）
- **界面**：SwiftUI，仅支持 macOS

## 项目结构

```
Translator/
├── TranslatorApp.swift      # 应用入口
├── ContentView.swift        # 主界面与翻译逻辑
├── Assets.xcassets          # 资源
├── Translator.xcodeproj     # Xcode 工程
└── README.md
```

## 许可证

本示例仅供学习与参考使用。
