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
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
    public static func acknowledged(_ text: String) -> Bool {
        matches(#"(?:^|\r?\n)OK\r?(?:\n|$)"#, text)
    }
    public static func rejected(_ text: String) -> Bool {
        matches(#"(?:^|\r?\n)(?:ERROR|\+CM[ES] ERROR[^\r\n]*)\r?(?:\n|$)"#, text)
    }
    public static func value(_ response: String, key: String) throws -> Int {
        guard acknowledged(response), !rejected(response) else { throw ModemError.invalidResponse }
        let pattern = #"\+QCFG:\s*""# + NSRegularExpression.escapedPattern(for: key) + #""\s*,\s*(\d+)"#
        let expression = try NSRegularExpression(pattern: pattern)
        guard let match = expression.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range(at: 1), in: response), let value = Int(response[range]),
              value == 0 || value == 1 else { throw ModemError.invalidResponse }
        return value
    }
}
