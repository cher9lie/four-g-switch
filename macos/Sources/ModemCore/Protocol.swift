import Foundation

public enum ModemError: LocalizedError {
    case transport(String)
    case rejected
    case invalidResponse
    case timeout
    public var errorDescription: String? {
        switch self {
        case .transport(let message): return message
        case .rejected: return "模块拒绝了设置，已停止切换"
        case .invalidResponse: return "模块配置尚未确认，请刷新后检查"
        case .timeout: return "尚未确认切换结果，请保持连接后刷新"
        }
    }
}

public enum USBMode: Int, Sendable {
    case windows = 0
    case apple = 1
}

public struct Snapshot: Sendable {
    public let mode: USBMode
    public let autoConnect: Bool
    public let protocolApplied: Bool
    public let networkReady: Bool
    public init(mode: USBMode, autoConnect: Bool, protocolApplied: Bool, networkReady: Bool) {
        self.mode = mode; self.autoConnect = autoConnect
        self.protocolApplied = protocolApplied; self.networkReady = networkReady
    }
    public var macConnected: Bool { mode == .apple && autoConnect && protocolApplied && networkReady }
    public var preparedForWindows: Bool { mode == .windows && autoConnect && protocolApplied }
    public var diagnostic: String {
        "DJI 4G / 2CA3:4006\nusbnet=\(mode.rawValue)\nqcautoconnect=\(autoConnect ? 1 : 0)\nUSB 接口已应用：\(protocolApplied)\n模块网络地址已获取：\(networkReady)\n"
    }
}

public enum ATProtocol {
    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    }
    public static func acknowledged(_ text: String) -> Bool {
        lines(text).contains("OK")
    }
    public static func rejected(_ text: String) -> Bool {
        lines(text).contains { $0 == "ERROR" || $0.hasPrefix("+CME ERROR") || $0.hasPrefix("+CMS ERROR") }
    }
    public static func value(_ response: String, key: String) throws -> Int {
        guard acknowledged(response), !rejected(response) else { throw ModemError.invalidResponse }
        var values: [Int] = []
        for line in lines(response) where line.hasPrefix("+QCFG:") {
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            let fields = payload.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 2,
                  fields[0].trimmingCharacters(in: .whitespaces) == "\"\(key)\"" else { continue }
            let text = fields[1].trimmingCharacters(in: .whitespaces)
            guard text == "0" || text == "1", let value = Int(text) else { throw ModemError.invalidResponse }
            values.append(value)
        }
        guard values.count == 1, let value = values.first else { throw ModemError.invalidResponse }
        return value
    }
}
