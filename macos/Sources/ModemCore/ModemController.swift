import Foundation
import CModemUSB

private final class USBSession {
    private let pointer: OpaquePointer
    private init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { fg_close(pointer) }
    static func open() throws -> USBSession {
        var error = [CChar](repeating: 0, count: 512)
        guard let pointer = fg_open(&error, error.count) else { throw ModemError.transport(String(cString: error)) }
        let session = USBSession(pointer)
        // Validate the exact interface with an AT/OK exchange before any configuration write.
        _ = try session.command("AT", timeout: 1500)
        return session
    }
    @discardableResult func command(_ command: String, timeout: UInt32 = 2500) throws -> String {
        var response = [CChar](repeating: 0, count: 8192)
        var error = [CChar](repeating: 0, count: 512)
        let result = fg_command(pointer, command, &response, response.count, timeout, &error, error.count)
        guard result == 0 else { throw ModemError.transport(String(cString: error)) }
        let text = String(cString: response)
        guard !ATProtocol.rejected(text) else { throw ModemError.rejected }
        guard ATProtocol.acknowledged(text) else { throw ModemError.invalidResponse }
        return text
    }
    func values() throws -> (USBMode, Bool) {
        let mode = try ATProtocol.value(command("AT+QCFG=\"usbnet\""), key: "usbnet")
        let auto = try ATProtocol.value(command("AT+QCFG=\"qcautoconnect\""), key: "qcautoconnect")
        guard let typed = USBMode(rawValue: mode) else { throw ModemError.invalidResponse }
        return (typed, auto == 1)
    }
}

public actor ModemController: DeviceOperating {
    public init() {}
    public func snapshot() throws -> Snapshot {
        let session = try USBSession.open()
        let (mode, auto) = try session.values()
        return Snapshot(mode: mode, autoConnect: auto,
                        protocolApplied: fg_protocol_matches(Int32(mode.rawValue)) == 1,
                        networkReady: fg_network_ready() == 1)
    }
    private func configure(_ target: USBMode) throws {
        let session = try USBSession.open()
        let (mode, auto) = try session.values()
        if !auto {
            try session.command("AT+QCFG=\"qcautoconnect\",1")
            guard try ATProtocol.value(session.command("AT+QCFG=\"qcautoconnect\""), key: "qcautoconnect") == 1 else { throw ModemError.invalidResponse }
        }
        if mode != target {
            do { try session.command("AT+QCFG=\"usbnet\",\(target.rawValue)", timeout: 4000) }
            catch ModemError.transport { /* USB can disappear before acknowledgement. Always verify after reconnect. */ }
        }
    }
    private func reboot() throws {
        let session = try USBSession.open()
        do { try session.command("AT+CFUN=1,1", timeout: 4000) }
        catch ModemError.transport { /* A verified reconnect is required by the caller. */ }
    }
    private func restoreAutoConnect() throws {
        let session = try USBSession.open()
        try session.command("AT+QCFG=\"qcautoconnect\",1")
        guard try ATProtocol.value(session.command("AT+QCFG=\"qcautoconnect\""), key: "qcautoconnect") == 1 else { throw ModemError.invalidResponse }
    }
    private func applied(_ target: USBMode, progress: @Sendable (String) -> Void) async throws -> Snapshot {
        let start = ProcessInfo.processInfo.systemUptime
        var restarted = false
        while ProcessInfo.processInfo.systemUptime - start < 90 {
            try Task.checkCancellation()
            // Observe descriptors first; do not touch the interface while it is disappearing.
            if fg_protocol_matches(Int32(target.rawValue)) == 1,
               let state = try? snapshot(), state.mode == target, state.protocolApplied { return state }
            if !restarted, ProcessInfo.processInfo.systemUptime - start >= 5,
               let state = try? snapshot(), state.mode == target, !state.protocolApplied {
                progress("正在等待模块重启")
                try reboot(); restarted = true
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw ModemError.timeout
    }
    public func switchMode(to target: USBMode, progress: @escaping @Sendable (String) -> Void) async throws -> Snapshot {
        let before = try snapshot()
        if before.mode == target && before.autoConnect && before.protocolApplied && (target == .windows || before.networkReady) { return before }
        progress("正在保存网卡模式")
        try configure(target)
        progress("正在等待 USB 重连")
        var state = try await applied(target, progress: progress)
        if !state.autoConnect {
            progress("正在恢复自动联网")
            try restoreAutoConnect()
            state = try snapshot()
        }
        guard state.mode == target, state.autoConnect, state.protocolApplied else { throw ModemError.invalidResponse }
        if target == .apple && !state.networkReady {
            progress("正在等待网络地址")
            let start = ProcessInfo.processInfo.systemUptime
            while ProcessInfo.processInfo.systemUptime - start < 15 {
                if fg_network_ready() == 1 { return try snapshot() }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return state
    }
}
