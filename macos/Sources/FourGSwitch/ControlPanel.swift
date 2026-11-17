import AppKit
import SwiftUI

/// An ordinary resizable Mac panel gives keyboard and assistive-technology users a persistent surface.
/// Opening it is also available to App Intents; it does not depend on a menu-bar popover being visible.
@MainActor final class ControlPanelPresenter {
    static let shared = ControlPanelPresenter()
    private var panel: NSPanel?
    func show() {
        if panel == nil {
            let value = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
                                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                backing: .buffered, defer: false)
            value.title = "4G 网卡开关"
            value.isReleasedWhenClosed = false
            value.hidesOnDeactivate = false
            value.contentMinSize = NSSize(width: 320, height: 240)
            value.contentView = NSHostingView(rootView: ScrollView { WidgetView(model: AppModel.shared) })
            value.center()
            panel = value
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

enum AccessibilityPreview {
    @MainActor static func render(to path: String) throws {
        _ = NSApplication.shared
        let model = AppModel(demo: true)
        let hosting = NSHostingView(rootView: WidgetView(model: model).frame(width: 336)
            .environment(\.controlActiveState, .active))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 336, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        window.setContentSize(NSSize(width: 336, height: max(fitting.height, 240)))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw ModemPreviewError.noImage }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ModemPreviewError.noImage }
        try png.write(to: URL(fileURLWithPath: path))
        window.close()
    }
    enum ModemPreviewError: Error { case noImage }
}
