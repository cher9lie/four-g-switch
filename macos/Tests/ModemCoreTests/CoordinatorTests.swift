import XCTest
import ModemCore

private actor SimulatedDevice: DeviceOperating {
    var value = Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: true)
    var writes = 0
    var reads = 0
    var fail = false
    func setFailure() { fail = true }
    func snapshot() throws -> Snapshot { reads += 1; return value }
    func counts() -> (Int, Int) { (reads, writes) }
    func switchMode(to target: USBMode, progress: @escaping @Sendable (String) -> Void) async throws -> Snapshot {
        writes += 1; progress("正在等待 USB 重连")
        try await Task.sleep(nanoseconds: 150_000_000)
        if fail { throw ModemError.timeout }
        value = Snapshot(mode: target, autoConnect: true, protocolApplied: true, networkReady: target == .apple)
        return value
    }
}

final class CoordinatorTests: XCTestCase {
    func testConcurrentSystemActionCannotStartASecondUSBWrite() async throws {
        let device = SimulatedDevice(); let coordinator = DeviceCoordinator(controller: device)
        _ = await coordinator.refresh()
        let first = Task { try await coordinator.setMode(.windows) }
        for _ in 0..<50 {
            if await coordinator.currentStatus().isWorking { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let pending = await coordinator.refresh()
        XCTAssertTrue(pending.isWorking); XCTAssertFalse(pending.connected)
        do { _ = try await coordinator.setMode(.apple); XCTFail("Concurrent writer was accepted") }
        catch ModemError.busy { }
        let result = try await first.value
        XCTAssertTrue(result.preparedForWindows)
        let counts = await device.counts(); XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testFailedWriteDoesNotExposeCachedSuccess() async throws {
        let device = SimulatedDevice(); let coordinator = DeviceCoordinator(controller: device)
        let before = await coordinator.refresh(); XCTAssertTrue(before.connected)
        await device.setFailure()
        do { _ = try await coordinator.setMode(.windows); XCTFail("Expected timeout") } catch ModemError.timeout { }
        let after = await coordinator.currentStatus()
        XCTAssertFalse(after.connected); XCTAssertFalse(after.configurationVerified); XCTAssertNil(after.snapshot)
    }
    func testWaitingForAddressIsNotReportedAsConnected() {
        let status = DeviceStatus(snapshot: Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: false))
        XCTAssertFalse(status.connected)
        XCTAssertTrue(status.configurationVerified)
        XCTAssertEqual(status.title, "正在等待网络地址")
        XCTAssertTrue(status.accessibilityValue.contains("等待网络地址"))
    }
}
