import AppIntents
import AppKit
import Foundation
import ModemCore

enum FourGTargetMode: String, AppEnum {
    case macAndIPad, windows
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "目标模式")
    static var caseDisplayRepresentations: [FourGTargetMode: DisplayRepresentation] = [
        .macAndIPad: "Mac / iPad", .windows: "Windows"
    ]
    var usbMode: USBMode { self == .macAndIPad ? .apple : .windows }
}

enum FourGReportedMode: String, AppEnum {
    case macAndIPad, windows, unconfirmed
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "已确认的网卡模式")
    static var caseDisplayRepresentations: [FourGReportedMode: DisplayRepresentation] = [
        .macAndIPad: "Mac / iPad", .windows: "Windows", .unconfirmed: "尚未确认"
    ]
}

struct FourGStatusEntity: AppEntity {
    static let deviceIdentifier = "dji-4g-2ca3-4006"
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "4G 网卡状态")
    static var defaultQuery = FourGStatusQuery()
    var id: String
    @Property(title: "已确认模式") var mode: FourGReportedMode
    @Property(title: "状态说明") var summary: String
    @Property(title: "Mac 网络已连接") var connected: Bool
    @Property(title: "正在切换") var busy: Bool
    @Property(title: "USB 模式已确认") var configurationVerified: Bool
    @Property(title: "已准备给 Windows 使用") var preparedForWindows: Bool
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "4G 网卡", subtitle: "\(summary)", image: .init(systemName: "antenna.radiowaves.left.and.right"))
    }
    init(_ status: DeviceStatus) {
        id = Self.deviceIdentifier
        if status.configurationVerified, let current = status.snapshot?.mode {
            mode = current == .apple ? .macAndIPad : .windows
        } else { mode = .unconfirmed }
        summary = status.accessibilityValue
        connected = status.connected; busy = status.isWorking
        configurationVerified = status.configurationVerified
        preparedForWindows = status.preparedForWindows
    }
}

struct FourGStatusQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FourGStatusEntity] {
        guard identifiers.contains(FourGStatusEntity.deviceIdentifier) else { return [] }
        return [FourGStatusEntity(await DeviceCoordinator.shared.refresh())]
    }
    func suggestedEntities() async throws -> [FourGStatusEntity] {
        [FourGStatusEntity(await DeviceCoordinator.shared.refresh())]
    }
}

struct GetFourGStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "查询 4G 网卡状态"
    static var description = IntentDescription("返回已确认模式、连接状态和切换状态，可用于快捷指令中的条件判断。")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult & ReturnsValue<FourGStatusEntity> & ProvidesDialog {
        let status = await DeviceCoordinator.shared.refresh()
        return .result(value: FourGStatusEntity(status), dialog: "\(status.accessibilityValue)")
    }
}

struct UseFourGOnMacIntent: AppIntent {
    static var title: LocalizedStringResource = "在 Mac 使用 4G 网卡"
    static var description = IntentDescription("设置 Mac / iPad 模式并核对结果。重复执行会保持相同模式，不会反向切换。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    func perform() async throws -> some IntentResult & ReturnsValue<FourGStatusEntity> & ProvidesDialog {
        let status = try await DeviceCoordinator.shared.setMode(.apple)
        return .result(value: FourGStatusEntity(status), dialog: "\(status.accessibilityValue)")
    }
}

struct PrepareFourGForWindowsIntent: AppIntent {
    static var title: LocalizedStringResource = "准备给 Windows 使用 4G 网卡"
    static var description = IntentDescription("设置 Windows 模式并确认配置，完成后可拔下模块连接 Windows。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    func perform() async throws -> some IntentResult & ReturnsValue<FourGStatusEntity> & ProvidesDialog {
        let status = try await DeviceCoordinator.shared.setMode(.windows)
        return .result(value: FourGStatusEntity(status), dialog: "\(status.accessibilityValue)")
    }
}

struct SetFourGModeIntent: AppIntent {
    static var title: LocalizedStringResource = "设置 4G 网卡模式"
    static var description = IntentDescription("选择明确的目标模式，适合快捷指令和个人自动化。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "目标模式") var mode: FourGTargetMode
    static var parameterSummary: some ParameterSummary { Summary("将 4G 网卡设置为 \(\.$mode)") }
    func perform() async throws -> some IntentResult & ReturnsValue<FourGStatusEntity> & ProvidesDialog {
        let status = try await DeviceCoordinator.shared.setMode(mode.usbMode)
        return .result(value: FourGStatusEntity(status), dialog: "\(status.accessibilityValue)")
    }
}

struct OpenFourGPanelIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 4G 网卡面板"
    static var description = IntentDescription("打开支持键盘和辅助技术的独立控制面板。")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        ControlPanelPresenter.shared.show()
        return .result()
    }
}

struct FourGShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetFourGStatusIntent(),
                    phrases: ["用 \(.applicationName) 查询网卡状态"],
                    shortTitle: "查看网卡状态", systemImageName: "antenna.radiowaves.left.and.right")
        AppShortcut(intent: UseFourGOnMacIntent(),
                    phrases: ["用 \(.applicationName) 在 Mac 使用网卡"],
                    shortTitle: "在 Mac 使用", systemImageName: "laptopcomputer")
        AppShortcut(intent: PrepareFourGForWindowsIntent(),
                    phrases: ["用 \(.applicationName) 准备给 Windows 使用网卡"],
                    shortTitle: "准备给 Windows", systemImageName: "arrow.right.square")
        AppShortcut(intent: OpenFourGPanelIntent(),
                    phrases: ["打开 \(.applicationName) 的网卡面板"],
                    shortTitle: "打开网卡面板", systemImageName: "switch.2")
    }
}

enum SystemIntegrationChecks {
    enum Failure: Error { case invalidEntity, invalidIntentRegistration }
    static func run(output: String) throws {
        let connected = DeviceStatus(snapshot: Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: true))
        let waiting = DeviceStatus(snapshot: Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: false))
        let switching = DeviceStatus(snapshot: connected.snapshot, isWorking: true, phase: "正在等待 USB 重连")
        let failed = DeviceStatus(error: "请连接大疆 4G 模块")
        guard FourGStatusEntity(connected).connected,
              !FourGStatusEntity(waiting).connected,
              FourGStatusEntity(switching).busy,
              FourGStatusEntity(switching).mode == .unconfirmed,
              !FourGStatusEntity(switching).configurationVerified,
              FourGStatusEntity(failed).mode == .unconfirmed else { throw Failure.invalidEntity }
        guard FourGShortcuts.appShortcuts.count == 4,
              !UseFourGOnMacIntent.openAppWhenRun,
              !PrepareFourGForWindowsIntent.openAppWhenRun,
              OpenFourGPanelIntent.openAppWhenRun else { throw Failure.invalidIntentRegistration }
        try "PASS: structured App Intents status, explicit target actions, busy/error states, four App Shortcuts\n".write(toFile: output, atomically: true, encoding: .utf8)
    }
}
