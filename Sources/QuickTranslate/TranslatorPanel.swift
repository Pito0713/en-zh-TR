import AppKit
import SwiftUI

/// 常駐桌面的翻譯小視窗（有關閉鈕，點別處不會消失）。
final class TranslatorPanel: NSPanel {
    private let model: TranslatorModel

    init(model: TranslatorModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
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
        setFrameAutosaveName(Self.frameName)
    }

    private static let frameName = "QuickTranslatePanel"
    /// 玻璃背景透明度（1.0 = 最實、數字越小越透）
    private static let glassOpacity: CGFloat = 0.95

    override var canBecomeKey: Bool { true }

    /// Esc 關閉
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.input.isEmpty ? "自動判斷中 ↔ 英" : model.direction.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }

            TextField("輸入中文或英文…", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { model.copyOutput() }
                .onChange(of: model.input) { model.inputChanged() }

            Divider()

            ScrollView {
                Group {
                    if let err = model.errorMessage {
                        Text(err).foregroundStyle(.red)
                    } else if model.output.isEmpty {
                        Text("翻譯結果會即時顯示在這裡").foregroundStyle(.tertiary)
                    } else {
                        Text(model.output).textSelection(.enabled)
                    }
                }
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Enter 複製結果 · ⌘V 貼上 · ⌥Enter 換行 · Esc 收起")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(model.copiedFlash ? "已複製 ✓" : "複製") { model.copyOutput() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.output.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 34) // 留空間給左上角關閉鈕
        .padding(.bottom, 14)
        .frame(width: 560, height: 280)
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { focused = true }
    }
}
