import SwiftUI
import AppKit
import ModemCore

@MainActor final class AppModel: ObservableObject {
    @Published var state: Snapshot?
    @Published var isWorking = false
    @Published var error: String?
    @Published var progress = "正在识别"
    private let controller = ModemController()
    private var isReading = false
    private var timer: Timer?
    var connected: Bool { !isWorking && error == nil && state?.macConnected == true }
    var headline: String {
        if isWorking { return "正在切换" }
        if connected { return "本机使用" }
        if state?.preparedForWindows == true { return "Windows 模式" }
        if state?.mode == .apple { return "等待网络" }
        return error == nil ? "正在识别" : "未连接网卡"
    }
    var subtitle: String {
        if isWorking { return "请勿拔出网卡" }
        if connected { return "Mac 已连接" }
        if state?.preparedForWindows == true { return "可以拔下网卡" }
        if state?.mode == .apple { return "Mac / iPad 模式已开启" }
        return "插入后自动识别"
    }
    init(demo: Bool = false) {
        if demo {
            state = Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: true)
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }
    func refresh() async {
        guard !isWorking, !isReading else { return }
        isReading = true
        defer { isReading = false }
        do { state = try await controller.snapshot(); error = nil }
        catch { state = nil; self.error = error.localizedDescription }
    }
    func toggle() async {
        guard !isWorking, let current = state else { return }
        let target: USBMode = current.mode == .apple && current.autoConnect ? .windows : .apple
        isWorking = true; error = nil; progress = "正在读取配置"
        defer { isWorking = false }
        do {
            state = try await controller.switchMode(to: target) { [weak self] phase in
                Task { @MainActor in if self?.isWorking == true { self?.progress = phase } }
            }
        } catch { state = nil; self.error = error.localizedDescription }
    }
    func copyDiagnostic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((state?.diagnostic ?? "未读取到配置\n") + "状态：\(error ?? subtitle)\n版本：3.0.0", forType: .string)
    }
}

struct WidgetView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("4G 网卡").fontWeight(.semibold)
                Spacer()
                Menu {
                    Button("复制诊断", action: model.copyDiagnostic)
                    Divider()
                    Button("退出") { if !model.isWorking { NSApplication.shared.terminate(nil) } }
                        .disabled(model.isWorking)
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 24) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多选项")
            }
            HStack(spacing: 16) {
                Button { Task { await model.toggle() } } label: {
                    Image(systemName: "power")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(model.connected ? Color.white : Color.secondary)
                        .frame(width: 72, height: 72)
                        .background(model.connected ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain).disabled(model.isWorking || model.state == nil)
                .accessibilityLabel(model.state?.mode == .apple ? "准备给 Windows 使用" : "在这台 Mac 使用")
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.headline).font(.system(size: 16, weight: .semibold))
                    Text(model.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }
            if model.isWorking {
                Text(model.progress).font(.system(size: 12)).foregroundStyle(.secondary)
            } else if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack {
                Text("DJI 4G").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(model.isWorking).accessibilityLabel("刷新状态")
            }
        }
        .font(.system(size: 14))
        .padding(18).frame(width: 328)
        .background(.regularMaterial)
    }
}

struct FourGSwitchApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra("4G 网卡", systemImage: model.connected ? "power.circle.fill" : "power.circle") {
            WidgetView(model: model)
        }.menuBarExtraStyle(.window)
    }
}

@main enum Launcher {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--version") { print("FourGSwitch 3.0.0"); return }
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--render-preview" {
            _ = NSApplication.shared
            let renderer = ImageRenderer(content: WidgetView(model: AppModel(demo: true)))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2])) } catch { exit(1) }
            return
        }
        FourGSwitchApp.main()
    }
}
