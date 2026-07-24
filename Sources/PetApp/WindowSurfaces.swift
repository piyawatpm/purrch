import AppKit

/// A ledge he can stand on: either a screen's floor or the top edge of someone
/// else's window. Coordinates are AppKit (origin bottom-left, y up).
struct Surface: Equatable {
    let minX: CGFloat
    let maxX: CGFloat
    /// The walking line — the top edge of the window, or the screen's floor.
    let y: CGFloat
    let isGround: Bool

    func contains(x: CGFloat) -> Bool { x >= minX && x <= maxX }
    var width: CGFloat { maxX - minX }
}

/// Finds the top edges of other apps' windows so the cat can perch on them.
///
/// Uses `CGWindowListCopyWindowInfo`, which reports window *bounds* without any
/// permission prompt — only window titles require Screen Recording, and we never
/// ask for those. Results are cached because the query walks every window on the
/// system and the simulation ticks 30 times a second.
final class WindowSurfaces {
    private(set) var surfaces: [Surface] = []
    private var lastRefresh: CFAbsoluteTime = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Windows smaller than this are dialogs, tooltips and shadows — not ledges.
    private let minimumWidth: CGFloat = 140
    private let minimumHeight: CGFloat = 80

    func refreshIfStale(interval: TimeInterval = 0.4) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRefresh >= interval else { return }
        lastRefresh = now
        refresh()
    }

    /// The frontmost ordinary window, in the same coordinates as `surfaces`.
    private(set) var frontmost: Surface?

    func refresh() {
        // CoreGraphics measures from the top-left of the primary display; AppKit
        // measures from its bottom-left.
        let primaryTop = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY
            ?? NSScreen.main?.frame.maxY ?? 0

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        // The list is front-to-back, so the first qualifying window is frontmost.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var front: Surface?

        surfaces = info.compactMap { window -> Surface? in
            // Layer 0 is ordinary application windows. Anything else is the menu
            // bar, the Dock, a floating panel, or the cat himself.
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  pid != ownPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.15,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w >= minimumWidth, h >= minimumHeight
            else { return nil }

            let surface = Surface(minX: x, maxX: x + w, y: primaryTop - y, isGround: false)
            if front == nil, let frontPID, pid == frontPID { front = surface }
            return surface
        }
        frontmost = front ?? surfaces.first
    }

    func frontmostSurface() -> Surface? { frontmost }

    /// Every ledge directly under a given x, the screen floor included.
    func supports(at x: CGFloat, groundY: CGFloat, screen: NSScreen) -> [Surface] {
        var found = surfaces.filter { $0.contains(x: x) }
        found.append(Surface(minX: screen.visibleFrame.minX, maxX: screen.visibleFrame.maxX,
                             y: groundY, isGround: true))
        return found
    }

    /// True if a ledge matching this one is still there — a window may have been
    /// closed, moved, or scrolled out from under him.
    func stillExists(_ surface: Surface, at x: CGFloat) -> Bool {
        surface.isGround || surfaces.contains {
            abs($0.y - surface.y) < 6 && $0.contains(x: x)
        }
    }
}
