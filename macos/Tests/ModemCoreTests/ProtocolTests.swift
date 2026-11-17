import XCTest
import Foundation
import ModemCore
import CModemUSB

final class ProtocolTests: XCTestCase {
    struct Fixture: Decodable { let name: String; let key: String; let response: String; let expected: Int? }
    func testSharedProtocolFixtures() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/protocol-cases.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: file))
        for fixture in fixtures {
            if let expected = fixture.expected { XCTAssertEqual(try ATProtocol.value(fixture.response, key: fixture.key), expected, fixture.name) }
            else { XCTAssertThrowsError(try ATProtocol.value(fixture.response, key: fixture.key), fixture.name) }
        }
    }
    func testUnverifiedStatesNeverGreen() {
        XCTAssertFalse(Snapshot(mode: .windows, autoConnect: true, protocolApplied: true, networkReady: true).macConnected)
        XCTAssertFalse(Snapshot(mode: .apple, autoConnect: false, protocolApplied: true, networkReady: true).macConnected)
        XCTAssertFalse(Snapshot(mode: .apple, autoConnect: true, protocolApplied: false, networkReady: true).macConnected)
        XCTAssertFalse(Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: false).macConnected)
        XCTAssertTrue(Snapshot(mode: .apple, autoConnect: true, protocolApplied: true, networkReady: true).macConnected)
    }
    func testCommandAllowlist() {
        XCTAssertEqual(fg_command_allowed("AT+QCFG=\"usbnet\",1"), 1)
        XCTAssertEqual(fg_command_allowed("AT+QCFG=\"usbnet\",3"), 0)
        XCTAssertEqual(fg_command_allowed("AT+QCFG=\"usbcfg\",0"), 0)
        XCTAssertEqual(fg_command_allowed("AT\rAT+CFUN=1,1"), 0)
    }
}
