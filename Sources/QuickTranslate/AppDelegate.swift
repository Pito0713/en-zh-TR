import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let model = TranslatorModel()
    private lazy var panel = TranslatorPanel(model: model)
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "QuickTranslate")

        let menu = NSMenu()
        let open = NSMenuItem(title: "開啟翻譯 (⌃⌥T)", action: #selector(togglePanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // 全域快捷鍵 ⌃⌥T（Carbon API，不需要輔助使用權限）
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.togglePanel()
        }
        if hotKey == nil {
            NSLog("QuickTranslate: ⌃⌥T 註冊失敗，可能已被其他 App 佔用")
        }
        installEditMenu()
        installControlVPaste()
        model.warmUp()
        panel.present() // 啟動就顯示在桌面

    }

    /// 沒有 Edit 選單時 ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z 不會送到輸入框，所以要補一個。
    private func installEditMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "結束 QuickTranslate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "編輯")
        edit.addItem(NSMenuItem(title: "還原", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "剪下", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "拷貝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "貼上", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    /// 額外支援 Windows 習慣的 ⌃V 貼上（只在本 App 視窗內生效）。
    private func installControlVPaste() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .control, event.charactersIgnoringModifiers?.lowercased() == "v" {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return nil
            }
            return event
        }
    }

    @objc func togglePanel() {
        if panel.isVisible && panel.isKeyWindow {
            panel.orderOut(nil)
        } else {
            panel.present()
        }
    }
}
