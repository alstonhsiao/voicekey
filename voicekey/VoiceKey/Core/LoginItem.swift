import AppKit
import ServiceManagement

enum LoginItemStatus: String, Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case unknown

    var isEffectivelyEnabled: Bool { self == .enabled }

    var displayText: String {
        switch self {
        case .enabled: return "已啟用"
        case .notRegistered: return "未啟用"
        case .requiresApproval: return "等待系統批准"
        case .notFound: return "找不到登入項目（請安裝到「應用程式」資料夾）"
        case .unknown: return "狀態不明"
        }
    }
}

enum LoginItem {
    static func mapStatus(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    static func currentStatus() -> LoginItemStatus {
        mapStatus(SMAppService.mainApp.status)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let current = SMAppService.mainApp.status
        if enabled {
            if current == .enabled { return }
            do {
                try SMAppService.mainApp.register()
            } catch {
                throw SettingsApplyError.loginItem(error.localizedDescription)
            }
        } else {
            if current == .notRegistered { return }
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                throw SettingsApplyError.loginItem(error.localizedDescription)
            }
        }
    }

    static func openSystemSettings() {
        let specs = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?LoginItems",
        ]
        for spec in specs {
            if let url = URL(string: spec), NSWorkspace.shared.open(url) { return }
        }
    }
}

enum SystemSettingsOpener {
    static func openMicrophone() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibility() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openLoginItems() {
        LoginItem.openSystemSettings()
    }

    private static func open(_ spec: String) {
        guard let url = URL(string: spec) else { return }
        NSWorkspace.shared.open(url)
    }
}
