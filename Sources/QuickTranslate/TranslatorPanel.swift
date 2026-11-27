import AppKit
import SwiftUI

/// 常駐桌面的翻譯小視窗（有關閉鈕，點別處不會消失）。
final class TranslatorPanel: NSPanel {
    private let model: TranslatorModel

    init(model: TranslatorModel) {
        self.model = model
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        level = .normal
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // 玻璃透明背景：Liquid Glass 墊底，透明度 glassOpacity，文字維持不透明
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let container = NSView()
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 16
        glass.alphaValue = Self.glassOpacity
        glass.frame = container.bounds
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)

        let host = NSHostingView(rootView: TranslatorView(model: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        contentView = container

        // 記住使用者拖曳後的位置；第一次則放在螢幕中上方
        if !setFrameUsingName(Self.frameName), let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - f.height * 0.25 - frame.height))
        }
        // 舊版存的尺寸可能不同，位置沿用、尺寸固定（保持頂端位置不動）
        if frame.size != Self.size {
            setFrame(NSRect(x: frame.minX, y: frame.maxY - Self.size.height,
                            width: Self.size.width, height: Self.size.height), display: false)
        }
        setFrameAutosaveName(Self.frameName)
    }

    static let size = NSSize(width: 560, height: 330)
    private static let frameName = "QuickTranslatePanel"
    /// 玻璃背景透明度（1.0 = 最實、數字越小越透）
    private static let glassOpacity: CGFloat = 0.95

    override var canBecomeKey: Bool { true }

    /// Esc 關閉
    override func cancelOperation(_ sender: Any?) {
        model.stopSpeaking()
        orderOut(nil)
    }

    func present() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        model.focusInput()
    }
}

struct TranslatorView: View {
    @Bindable var model: TranslatorModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            header
            inputCard
            outputCard
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(width: TranslatorPanel.size.width, height: TranslatorPanel.size.height)
        // 新版 SDK 會替透明標題列保留 safe area，把整個版面往下推；這裡要自己排到最頂
        .ignoresSafeArea()
        .background(hiddenShortcuts)
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { focused = true }
    }

    // MARK: 語言列（和左上角關閉鈕同一行）

    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("來源語言", selection: $model.manualDirection) {
                    Text("自動偵測").tag(Direction?.none)
                    Text("中文").tag(Direction?.some(.zhToEn))
                    Text("English").tag(Direction?.some(.enToZh))
                }
                .pickerStyle(.inline)
            } label: {
                Text(sourceLabel)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("選擇來源語言（⌘1 自動 · ⌘2 中文 · ⌘3 English）")

            Button { model.swap() } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .help("互換：結果換到輸入框並反向翻譯（⌘⇧X）")
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(model.output.isEmpty && model.manualDirection == nil)

            Text(targetLabel)
                .foregroundStyle(.primary)

            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button { model.translateNow() } label: {
                Label("翻譯", systemImage: "character.bubble")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: .command)
            .help("翻譯（Enter 或 ⌘Enter）")
            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.leading, 50) // 讓出左上角關閉鈕
        .frame(height: 26)
    }

    private var sourceLabel: String {
        if let m = model.manualDirection { return m.sourceName }
        return model.input.isEmpty ? "自動偵測" : "自動偵測・\(model.direction.sourceName)"
    }

    private var targetLabel: String {
        if model.manualDirection == nil && model.input.isEmpty { return "中 ↔ 英" }
        return model.direction.targetName
    }

    // MARK: 輸入

    private var inputCard: some View {
        TextField("輸入中文或英文…", text: $model.input, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .lineLimit(1...3)
            .focused($focused)
            .onSubmit { model.submit() }
            .onChange(of: model.input) { model.inputChanged() }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 34)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if !model.input.isEmpty {
                    Button {
                        model.input = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("清除")
                    .padding(10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { model.toggleSpeakInput() } label: {
                        Image(systemName: model.inputSpeaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(model.inputSpeaker.isSpeaking ? "停止朗讀" : "朗讀原文（⌘⇧I）")
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .padding(8)
                }
            }
    }

    // MARK: 結果

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                Group {
                    if let err = model.errorMessage {
                        Text(err).foregroundStyle(.red).font(.system(size: 13))
                    } else if model.output.isEmpty {
                        Text(model.isBusy ? "翻譯中…" : "按 Enter 翻譯").foregroundStyle(.tertiary)
                    } else {
                        Text(model.output).textSelection(.enabled)
                            .opacity(model.isStale ? 0.4 : 1)
                    }
                }
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 4) {
                if let detected = model.mismatchedDirection {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("輸入看起來是\(detected.sourceName)")
                        .foregroundStyle(.secondary)
                    Button("改成 \(detected.sourceName) → \(detected.targetName)") {
                        model.manualDirection = detected
                    }
                    .buttonStyle(.link)
                } else if model.isStale {
                    Text("輸入已修改，按 Enter 重新翻譯").foregroundStyle(.secondary)
                } else if let note = model.engineNote {
                    Text(note).foregroundStyle(.tertiary)
                }
                Spacer()
                Button { model.toggleSpeak() } label: {
                    Image(systemName: model.speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless)
                .help(model.speaker.isSpeaking ? "停止朗讀" : "朗讀翻譯結果（⌘⇧S）")
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.output.isEmpty)

                Button { model.copyOutput() } label: {
                    Label(model.copiedFlash ? "已複製" : "複製",
                          systemImage: model.copiedFlash ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("複製結果（翻譯後再按 Enter / ⌘⇧C）")
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.output.isEmpty)
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 底部提示

    private var footer: some View {
        Text("Enter 翻譯，再按一次複製 · ⌘⇧S 朗讀 · ⌘⇧X 互換 · ⌥Enter 換行 · Esc 收起")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 隱藏的快捷鍵：⌘1/2/3 切換來源語言
    private var hiddenShortcuts: some View {
        Group {
            Button("") { model.manualDirection = nil }.keyboardShortcut("1")
            Button("") { model.manualDirection = .zhToEn }.keyboardShortcut("2")
            Button("") { model.manualDirection = .enToZh }.keyboardShortcut("3")
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
