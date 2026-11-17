import SwiftUI
import AppKit
import AppIntents
import ModemCore

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var presentation = DeviceStatus()
    private let coordinator = DeviceCoordinator.shared
    private var observer: Task<Void, Never>?
    private var timer: Timer?
    private var submitting = false
    private var previousAnnouncement: String?
    let isDemo: Bool
    var state: Snapshot? { presentation.snapshot }
    var isWorking: Bool { presentation.isWorking || submitting }
    var connected: Bool { !submitting && presentation.connected }
    var error: String? { presentation.error }
    var progress: String { presentation.phase ?? "正在读取配置" }
    init(demo: Bool = false, demoStatus: DeviceStatus? = nil) {
        isDemo = demo
        if demo {
            presentation = demoStatus ?? DeviceStatus(snapshot: Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: true))
            return
        }
        observer = Task { [weak self, coordinator] in
            let stream = await coordinator.updates()
            for await value in stream {
                guard let self else { return }
                let previous = self.presentation
                self.presentation = value
                self.announceChange(from: previous, to: value)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }
    deinit { observer?.cancel(); timer?.invalidate() }
    func refresh() async { guard !isDemo else { return }; presentation = await coordinator.refresh() }
    func setMacMode(_ enabled: Bool) async {
        guard !isDemo, !isWorking, state != nil else { return }
        submitting = true; objectWillChange.send()
        defer { submitting = false; objectWillChange.send() }
        do { presentation = try await coordinator.setMode(enabled ? .apple : .windows) }
        catch { presentation = await coordinator.currentStatus() }
    }
    func copyDiagnostic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((state?.diagnostic ?? "未读取到配置\n") + "状态：\(presentation.accessibilityValue)\n版本：\(AppVersion.current)", forType: .string)
    }
    private func announceChange(from old: DeviceStatus, to new: DeviceStatus) {
        guard !isDemo, NSWorkspace.shared.isVoiceOverEnabled else { return }
        // Polling and intermediate phases must not repeatedly interrupt VoiceOver.
        guard old.isWorking != new.isWorking || old.connected != new.connected || old.error != new.error else { return }
        let message = new.announcement
        guard message != previousAnnouncement else { return }
        previousAnnouncement = message
        NSAccessibility.post(element: NSApplication.shared,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

enum AppVersion {
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "FGReleaseVersion") as? String ?? "3.0.0-beta.2" }
}

struct WidgetView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var bodySize = 14.0
    @ScaledMetric(relativeTo: .caption) private var detailSize = 12.0
    private var selection: Binding<Bool> {
        Binding(get: { model.presentation.macModeSelected }, set: { value in Task { await model.setMacMode(value) } })
    }
    private var statusSymbol: String {
        if model.isWorking { return "arrow.triangle.2.circlepath" }
        if model.connected { return "checkmark.circle.fill" }
        if model.presentation.preparedForWindows { return "eject.circle" }
        if model.error != nil { return "exclamationmark.circle" }
        return "clock"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("4G 网卡").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    Button("打开独立面板") { ControlPanelPresenter.shared.show() }.keyboardShortcut("o", modifiers: .command)
                    Button("复制诊断", action: model.copyDiagnostic).keyboardShortcut("c", modifiers: [.command, .shift])
                    Divider()
                    Button("退出") { if !model.isWorking { NSApplication.shared.terminate(nil) } }
                        .keyboardShortcut("q", modifiers: .command).disabled(model.isWorking)
                } label: { Label("更多选项", systemImage: "ellipsis").labelStyle(.iconOnly).frame(minWidth: 28, minHeight: 28) }
                .menuStyle(.borderlessButton).fixedSize().help("更多选项")
                .accessibilityIdentifier("four-g-more")
            }
            Toggle("在这台 Mac 使用", isOn: selection)
                .toggleStyle(.switch).tint(model.connected ? Color.green : Color.orange)
                .controlSize(.regular).frame(minHeight: 36)
                .disabled(model.isWorking || model.state == nil)
                .accessibilityValue(model.presentation.accessibilityValue)
                .accessibilityHint("开启用于 Mac 或 iPad，关闭后准备给 Windows 使用。切换期间请保持 USB 连接。")
                .accessibilityIdentifier("four-g-mode-toggle")
                .keyboardShortcut("m", modifiers: [.command, .shift])
            VStack(alignment: .leading, spacing: 5) {
                Label(model.presentation.title, systemImage: statusSymbol).fontWeight(.medium)
                Text(model.presentation.detail).font(.system(size: detailSize))
                    .foregroundStyle(contrast == .increased ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("网卡状态")
            .accessibilityValue(model.presentation.accessibilityValue)
            .accessibilityIdentifier("four-g-status")
            if model.isWorking {
                HStack(spacing: 8) {
                    if !reduceMotion { ProgressView().controlSize(.small).accessibilityHidden(true) }
                    Text("请勿拔出网卡").font(.system(size: detailSize))
                }
            }
            Divider()
            HStack {
                Text("DJI 4G").font(.system(size: detailSize)).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.borderless).disabled(model.isWorking)
                .keyboardShortcut("r", modifiers: .command).help("刷新状态（⌘R）")
                .accessibilityIdentifier("four-g-refresh")
            }
        }
        .font(.system(size: bodySize)).padding(18)
        .frame(minWidth: 304, idealWidth: 336, maxWidth: .infinity, alignment: .leading)
        .background {
            if reduceTransparency || contrast == .increased { Color(nsColor: .windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
        }
        .transaction { transaction in if reduceMotion { transaction.animation = nil } }
        .accessibilityElement(children: .contain)
        .task { await model.refresh() }
    }
}

struct FourGSwitchApp: App {
    @StateObject private var model = AppModel.shared
    init() { FourGShortcuts.updateAppShortcutParameters() }
    var body: some Scene {
        MenuBarExtra {
            WidgetView(model: model).frame(width: 336)
        } label: {
            Label("4G 网卡", systemImage: model.connected ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.circle")
                .accessibilityLabel("4G 网卡")
                .accessibilityValue(model.presentation.accessibilityValue)
        }.menuBarExtraStyle(.window)
    }
}

@main enum Launcher {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--version") { print("FourGSwitch \(AppVersion.current)"); return }
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--verify-system-integration" {
            do { try SystemIntegrationChecks.run(output: CommandLine.arguments[2]); return }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--render-preview" {
            do { try AccessibilityPreview.render(to: CommandLine.arguments[2]); return }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
        FourGSwitchApp.main()
    }
}
