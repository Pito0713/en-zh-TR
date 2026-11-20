import Foundation
import ServiceManagement

/// 開機（登入）自動啟動，使用 SMAppService 註冊為登入項目。
@MainActor
enum LaunchAtLogin {
    private static let didSetupKey = "LaunchAtLoginDidSetup"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("QuickTranslate: 登入項目設定失敗：\(error.localizedDescription)")
        }
    }

    /// 第一次啟動時預設開啟；之後尊重使用者在選單裡的選擇。
    static func enableOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSetupKey) else { return }
        setEnabled(true)
        defaults.set(true, forKey: didSetupKey)
    }
}
