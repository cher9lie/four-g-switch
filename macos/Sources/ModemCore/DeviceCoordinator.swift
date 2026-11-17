import Foundation

public protocol DeviceOperating: Sendable {
    func snapshot() async throws -> Snapshot
    func switchMode(to target: USBMode, progress: @escaping @Sendable (String) -> Void) async throws -> Snapshot
}

public struct DeviceStatus: Equatable, Sendable {
    public var snapshot: Snapshot?
    public var isWorking: Bool
    public var phase: String?
    public var error: String?
    public init(snapshot: Snapshot? = nil, isWorking: Bool = false, phase: String? = nil, error: String? = nil) {
        self.snapshot = snapshot; self.isWorking = isWorking; self.phase = phase; self.error = error
    }
    public var connected: Bool { !isWorking && error == nil && snapshot?.macConnected == true }
    public var configurationVerified: Bool { !isWorking && error == nil && snapshot?.autoConnect == true && snapshot?.protocolApplied == true }
    public var macModeSelected: Bool { snapshot?.mode == .apple && snapshot?.autoConnect == true && snapshot?.protocolApplied == true }
    public var preparedForWindows: Bool { configurationVerified && snapshot?.preparedForWindows == true }
    public var title: String {
        if isWorking { return "正在切换" }
        if connected { return "Mac 已连接" }
        if preparedForWindows { return "已准备给 Windows 使用" }
        if macModeSelected { return "正在等待网络地址" }
        if let error { return error.hasPrefix("请连接") ? "未连接网卡" : "状态待确认" }
        return "正在识别网卡"
    }
    public var detail: String {
        if isWorking { return phase ?? "请保持 USB 连接" }
        if connected { return "Mac 与 iPad 使用同一模式" }
        if preparedForWindows { return "可以拔下网卡并连接 Windows" }
        if macModeSelected { return "Mac / iPad 模式已开启" }
        return error ?? "请稍候"
    }
    public var accessibilityValue: String { title + "。" + detail }
    public var announcement: String {
        if isWorking { return "正在切换网卡模式，请勿拔出网卡。" }
        return accessibilityValue
    }
}

/// UI, App Intents and entity queries share this actor. An actor alone is not a lock across await:
/// the explicit operation flag prevents a second writer while USB is reconnecting.
public actor DeviceCoordinator {
    public static let shared = DeviceCoordinator(controller: ModemController())
    private let controller: any DeviceOperating
    private var status = DeviceStatus()
    private var reading = false
    private var operation: UUID?
    private var revision = 0
    private var observers: [UUID: AsyncStream<DeviceStatus>.Continuation] = [:]
    private var lastPublished: DeviceStatus?
    public init(controller: any DeviceOperating) { self.controller = controller }
    public func currentStatus() -> DeviceStatus { status }
    public func updates() -> AsyncStream<DeviceStatus> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        }
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private func publish() {
        guard status != lastPublished else { return }
        lastPublished = status
        for continuation in observers.values { continuation.yield(status) }
    }
    public func refresh() async -> DeviceStatus {
        guard operation == nil, !reading else { return status }
        reading = true
        let startedAtRevision = revision
        defer { reading = false }
        do {
            let value = try await controller.snapshot()
            // A user action may start while this read is in flight. Never clear its busy state.
            if revision == startedAtRevision && operation == nil {
                status.snapshot = value; status.error = nil; status.phase = nil
            }
        } catch {
            if revision == startedAtRevision && operation == nil { status.snapshot = nil; status.error = error.localizedDescription }
        }
        publish()
        return status
    }
    private func record(_ phase: String, for id: UUID) {
        guard operation == id else { return }
        status.phase = phase; publish()
    }
    public func setMode(_ target: USBMode) async throws -> DeviceStatus {
        guard operation == nil else { throw ModemError.busy }
        let id = UUID(); operation = id
        revision += 1
        status.isWorking = true; status.error = nil; status.phase = "正在读取配置"; publish()
        do {
            let value = try await controller.switchMode(to: target) { [weak self] phase in
                Task { await self?.record(phase, for: id) }
            }
            status = DeviceStatus(snapshot: value)
            operation = nil; publish()
            return status
        } catch {
            status = DeviceStatus(error: error.localizedDescription)
            operation = nil; publish()
            throw error
        }
    }
}
