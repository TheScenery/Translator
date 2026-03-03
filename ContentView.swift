import SwiftUI
import AppKit
import NaturalLanguage
import Translation

// 可选中、可复制、不可编辑的文本（macOS 上 NSTextView 更可靠）
struct SelectableTextLabel: NSViewRepresentable {
    let text: String
    let placeholder: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let content = text.isEmpty ? placeholder : text
        if textView.string != content {
            textView.string = content
            textView.textColor = text.isEmpty ? .secondaryLabelColor : .labelColor
        }
    }
}

// 支持的双语对：显示名称与 locale identifier
struct LanguageOption: Identifiable, Hashable {
    let id: String
    let name: String
    let localeIdentifier: String
    
    static let options: [LanguageOption] = [
        LanguageOption(id: "zh-Hans", name: "简体中文", localeIdentifier: "zh-Hans"),
        LanguageOption(id: "zh-Hant", name: "繁体中文", localeIdentifier: "zh-Hant"),
        LanguageOption(id: "en", name: "English", localeIdentifier: "en"),
        LanguageOption(id: "ja", name: "日本語", localeIdentifier: "ja"),
        LanguageOption(id: "ko", name: "한국어", localeIdentifier: "ko"),
        LanguageOption(id: "fr", name: "Français", localeIdentifier: "fr"),
        LanguageOption(id: "de", name: "Deutsch", localeIdentifier: "de"),
        LanguageOption(id: "es", name: "Español", localeIdentifier: "es"),
        LanguageOption(id: "ru", name: "Русский", localeIdentifier: "ru"),
        LanguageOption(id: "ar", name: "العربية", localeIdentifier: "ar"),
    ]
}

struct ContentView: View {
    @State private var inputText = ""
    @State private var translatedText = ""
    @State private var detectedLanguageName: String?
    @State private var isTranslating = false
    @State private var errorMessage: String?
    
    // 双语对：左语种 / 右语种（自动检测为其中一种则翻译成另一种）
    @State private var languageA: LanguageOption = .options[0]  // 简体中文
    @State private var languageB: LanguageOption = .options[2] // English
    
    @State private var configuration: TranslationSession.Configuration?
    @State private var autoTranslateTask: Task<Void, Never>?
    @State private var translationTimeoutTask: Task<Void, Never>?
    @State private var pendingTranslateText: String = ""
    @State private var cachedSessionAtoB: TranslationSession?
    @State private var cachedSessionBtoA: TranslationSession?
    /// 本次通过 translationTask 拿到的 session 要缓存到哪个方向（由 translate() 设置，runTranslation 使用）
    @State private var pendingCacheDirectionIsAtoB: Bool = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 语言对选择
                HStack(spacing: 12) {
                    languagePicker(selection: $languageA, label: "语言 A")
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    languagePicker(selection: $languageB, label: "语言 B")
                }
                .padding()
                .background(.ultraThinMaterial)
                .onChange(of: languageA.id) { _, _ in clearSessionCache() }
                .onChange(of: languageB.id) { _, _ in clearSessionCache() }
                
                Divider()
                
                HStack(alignment: .top, spacing: 0) {
                    // 输入区（检测到语言固定占一行，避免编辑框随显隐跳动）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("检测到: \(detectedLanguageName ?? "—")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TextEditor(text: $inputText)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .frame(minHeight: 120)
                            .onChange(of: inputText) { _, newValue in
                                triggerAutoTranslate(newValue: newValue)
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    
                    Divider()
                    
                    // 译文区（NSTextView：可选中、可复制、不可编辑）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("译文")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SelectableTextLabel(
                            text: translatedText,
                            placeholder: "翻译结果将显示在这里"
                        )
                        .frame(minHeight: 120)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
                
                // 翻译中时显示进度
                if isTranslating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("正在翻译…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("本地翻译")
            .translationTask(configuration) { session in
                await runTranslation(using: session)
            }
        }
    }
    
    private func languagePicker(selection: Binding<LanguageOption>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(LanguageOption.options) { opt in
                    Text(opt.name).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
    
    private func clearSessionCache() {
        cachedSessionAtoB = nil
        cachedSessionBtoA = nil
    }
    
    /// 检测输入文本的主导语言，返回 (source, target, 是否为 A→B)
    private func detectAndResolveDirection() -> (source: Locale.Language, target: Locale.Language, isAtoB: Bool)? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        
        guard let dominant = recognizer.dominantLanguage else {
            errorMessage = "无法识别输入语言"
            return nil
        }
        
        let sourceId = dominant.rawValue
        let langAId = languageA.localeIdentifier
        let langBId = languageB.localeIdentifier
        
        func matches(_ option: LanguageOption, _ nlId: String) -> Bool {
            if option.localeIdentifier.hasPrefix("zh") && nlId.hasPrefix("zh") { return true }
            return option.localeIdentifier == nlId || option.localeIdentifier.prefix(2) == nlId.prefix(2)
        }
        
        if matches(languageA, sourceId) {
            detectedLanguageName = languageA.name
            return (Locale.Language(identifier: langAId), Locale.Language(identifier: langBId), true)
        }
        if matches(languageB, sourceId) {
            detectedLanguageName = languageB.name
            return (Locale.Language(identifier: langBId), Locale.Language(identifier: langAId), false)
        }
        detectedLanguageName = languageA.name
        return (Locale.Language(identifier: langAId), Locale.Language(identifier: langBId), true)
    }
    
    /// 输入变化时延迟触发翻译（停止输入约 0.6 秒后自动翻译）
    private func triggerAutoTranslate(newValue: String) {
        autoTranslateTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            translatedText = ""
            detectedLanguageName = nil
            errorMessage = nil
            return
        }
        autoTranslateTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(0.6))
            } catch { return }
            guard !Task.isCancelled else { return }
            translate()
        }
    }
    
    private func translate() {
        errorMessage = nil
        translatedText = ""
        
        guard let direction = detectAndResolveDirection() else { return }
        
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let isAtoB = direction.isAtoB
        let cachedSession = isAtoB ? cachedSessionAtoB : cachedSessionBtoA
        
        // 有缓存则直接用 Session 翻译
        if let session = cachedSession {
            pendingTranslateText = trimmed
            isTranslating = true
            translationTimeoutTask?.cancel()
            startTimeoutTask()
            Task { @MainActor in
                await translateWithSession(session, text: trimmed, isAtoB: isAtoB)
            }
            return
        }
        
        // 请求新方向时清空另一方向的缓存，避免框架只保留一个 session 时旧缓存失效导致崩溃
        if isAtoB { cachedSessionBtoA = nil } else { cachedSessionAtoB = nil }
        
        translationTimeoutTask?.cancel()
        isTranslating = true
        pendingTranslateText = trimmed
        pendingCacheDirectionIsAtoB = isAtoB
        configuration = TranslationSession.Configuration(
            source: direction.source,
            target: direction.target
        )
        startTimeoutTask()
    }
    
    /// 使用已有 Session 翻译（用于缓存命中时）
    @MainActor
    private func translateWithSession(_ session: TranslationSession, text: String, isAtoB: Bool) async {
        defer {
            isTranslating = false
            translationTimeoutTask?.cancel()
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            let response = try await session.translate(t)
            translatedText = response.targetText
            errorMessage = nil
        } catch {
            errorMessage = "翻译失败: \(error.localizedDescription)"
            if isAtoB { cachedSessionAtoB = nil } else { cachedSessionBtoA = nil }
        }
        pendingTranslateText = ""
    }
    
    private func startTimeoutTask() {
        translationTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(20))
            } catch { return }
            if isTranslating {
                isTranslating = false
                errorMessage = "翻译超时，请到 系统设置 > 通用 > 语言与地区 > 翻译语言 检查并下载所需语言包"
            }
        }
    }
    
    @MainActor
    private func runTranslation(using session: TranslationSession) async {
        let isAtoB = pendingCacheDirectionIsAtoB
        if isAtoB { cachedSessionAtoB = session } else { cachedSessionBtoA = session }
        
        defer {
            isTranslating = false
            translationTimeoutTask?.cancel()
            // 不置 nil：保持 configuration 可让 session 不被框架释放，避免第二次用缓存时崩溃
        }
        let text = pendingTranslateText.isEmpty ? inputText.trimmingCharacters(in: .whitespacesAndNewlines) : pendingTranslateText
        guard !text.isEmpty else { return }
        
        do {
            let response = try await session.translate(text)
            translatedText = response.targetText
            errorMessage = nil
        } catch {
            errorMessage = "翻译失败: \(error.localizedDescription)"
        }
        pendingTranslateText = ""
    }
}

#Preview {
    ContentView()
}
