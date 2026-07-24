import AppKit
import SwiftUI

/// Hosts the two SwiftUI panels. Windows are kept alive between openings so text
/// fields don't lose their editing state when a panel is closed and reopened.
final class PanelWindows: NSObject, NSWindowDelegate {
    static let shared = PanelWindows()

    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var tasksWindow: NSWindow?

    private func makeWindow<V: View>(title: String, size: CGSize, root: V) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: root)
        window.center()
        return window
    }

    func showSettings(controller: PetController) {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Settings", size: CGSize(width: 460, height: 580),
                                        root: SettingsView(onBreakChange: { [weak controller] in
                                            controller?.resetBreakTimer()
                                        }))
        }
        present(settingsWindow)
    }

    func showTasks() {
        if tasksWindow == nil {
            tasksWindow = makeWindow(title: "Tasks", size: CGSize(width: 460, height: 520),
                                     root: TasksView())
        }
        present(tasksWindow)
    }

    func showAbout() {
        if aboutWindow == nil {
            aboutWindow = makeWindow(title: "", size: CGSize(width: 380, height: 470),
                                     root: AboutView())
        }
        present(aboutWindow)
    }

    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)     // so the panel can take keyboard focus
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Drop the Dock icon again once no panel is left on screen.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let stillOpen = [self.settingsWindow, self.aboutWindow, self.tasksWindow]
                .contains { $0?.isVisible == true }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
