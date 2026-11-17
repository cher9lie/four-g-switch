// swift-tools-version: 5.9
import PackageDescription
import Foundation
let usbPrefix = ProcessInfo.processInfo.environment["LIBUSB_PREFIX"] ?? "/opt/homebrew/opt/libusb"
let package = Package(
    name: "FourGSwitch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FourGSwitch", targets: ["FourGSwitch"])],
    targets: [
        .target(name: "CModemUSB", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-I\(usbPrefix)/include/libusb-1.0"])],
                linkerSettings: [.unsafeFlags(["-L\(usbPrefix)/lib", "-lusb-1.0"]), .linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("SystemConfiguration")]),
        .target(name: "ModemCore", dependencies: ["CModemUSB"]),
        .executableTarget(name: "FourGSwitch", dependencies: ["ModemCore"]),
        .testTarget(name: "ModemCoreTests", dependencies: ["ModemCore", "CModemUSB"])
    ])
