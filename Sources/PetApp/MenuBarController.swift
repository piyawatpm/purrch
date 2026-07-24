import AppKit

/// The menu bar item. The menu is rebuilt on every open so checkmarks and the
/// pet's name are always current.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = Settings.shared
    private unowned let controller: PetController
    private let menu = NSMenu()

    init(controller: PetController) {
        self.controller = controller
        super.init()

        let icon = NSImage(systemSymbolName: "cat", accessibilityDescription: "Pet")
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pet")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = settings.name
        refreshBadge()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshBadge), name: TaskStore.didChange, object: nil)

        menu.delegate = self
        statusItem.menu = menu
    }

    /// Keeps the open-task count next to the menu bar icon.
    @objc private func refreshBadge() {
        let open = TaskStore.shared.openCount
        statusItem.button?.title = open > 0 ? " \(open)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let name = settings.name
        statusItem.button?.toolTip = name
        menu.removeAllItems()

        menu.addItem(header(name))

        let open = TaskStore.shared.openCount
        let tasksItem = item(open > 0 ? "Tasks (\(open))…" : "Tasks…", #selector(openTasks), key: "t")
        if settings.quickAddEnabled {
            tasksItem.toolTip = "Quick add from anywhere: \(GlobalHotKey.quickAddDescription)"
        }
        menu.addItem(tasksItem)
        menu.addItem(.separator())
        menu.addItem(submenu("Mode",
                             options: [("Free Roam", 0), ("Follow Cursor", 1),
                                       ("Follow Active Window", 2), ("Rest in Place", 3)],
                             current: modeTag(settings.companionMode),
                             action: #selector(setMode(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Come Here", #selector(comeHere)))
        menu.addItem(item("Feed \(name)", #selector(feed)))
        menu.addItem(item("Drop a Mouse", #selector(dropMouse)))
        menu.addItem(animationTesterMenu())
        menu.addItem(item(settings.hidden ? "Show \(name)" : "Hide \(name)", #selector(toggleHidden)))
        menu.addItem(item("Sit", #selector(sitNow)))
        menu.addItem(item("Sleep Now", #selector(sleepNow)))
        menu.addItem(.separator())

        menu.addItem(submenu("Size", options: [("Small", 2), ("Medium", 3), ("Large", 4), ("Huge", 5)],
                             current: settings.scale, action: #selector(setScale(_:))))
        menu.addItem(submenu("Speed", options: [("Slow", 6), ("Normal", 10), ("Fast", 16), ("Zoomies", 24)],
                             current: Int((settings.speed * 10).rounded()), action: #selector(setSpeed(_:))))
        menu.addItem(submenu("Nap After", options: [("1 min", 1), ("5 min", 5), ("15 min", 15), ("30 min", 30)],
                             current: settings.sleepMinutes, action: #selector(setSleep(_:))))
        menu.addItem(submenu("Break Reminders",
                             options: [("Off", 0), ("Every 20 min", 20), ("Every 30 min", 30),
                                       ("Every 60 min", 60)],
                             current: settings.breakMinutes, action: #selector(setBreak(_:))))
        menu.addItem(.separator())

        menu.addItem(check("Climb on Windows", settings.perchOnWindows, #selector(togglePerch)))
        menu.addItem(check("Playful Antics", settings.anticsEnabled, #selector(toggleAntics)))
        menu.addItem(check("Clingy", settings.clingyEnabled, #selector(toggleClingy)))
        menu.addItem(collarMenu())
        menu.addItem(check("Time-of-Day Hellos", settings.greetingsEnabled, #selector(toggleGreetings)))
        menu.addItem(check("Sound", settings.soundEnabled, #selector(toggleSound)))
        let volumeItem = submenu("Volume",
                                 options: [("25%", 25), ("50%", 50), ("75%", 75), ("100%", 100)],
                                 current: Int((settings.volume * 100).rounded()),
                                 action: #selector(setVolume(_:)))
        volumeItem.isEnabled = settings.soundEnabled
        menu.addItem(volumeItem)
        menu.addItem(check("Launch at Login", settings.launchAtLogin, #selector(toggleLaunch)))
        menu.addItem(check("Hide From Screen Recording", settings.hideFromCapture, #selector(toggleCapture)))
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("About \(name)…", #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))
    }

    // MARK: - Item builders

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor])
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func check(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let item = self.item(title, action)
        item.state = on ? .on : .off
        return item
    }

    private func submenu(_ title: String, options: [(String, Int)],
                         current: Int, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, value) in options {
            let child = NSMenuItem(title: label, action: action, keyEquivalent: "")
            child.target = self
            child.tag = value
            child.state = value == current ? .on : .off
            sub.addItem(child)
        }
        parent.submenu = sub
        return parent
    }

    /// Opens the same menu from a right-click on the cat himself.
    func popUpAtMouse() {
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Actions

    @objc private func comeHere() { controller.comeHere() }
    @objc private func feed() { controller.feed() }
    @objc private func dropMouse() { controller.dropMouse() }

    /// A submenu listing every animation, so any of them can be played on demand.
    private func animationTesterMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Test Animation", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for name in controller.allAnimations {
            let child = NSMenuItem(title: name.capitalized, action: #selector(playAnimation(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = name
            sub.addItem(child)
        }
        parent.submenu = sub
        return parent
    }
    @objc private func playAnimation(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { controller.playAnimation(name) }
    }
    @objc private func toggleAntics() { settings.anticsEnabled.toggle() }
    @objc private func toggleGreetings() { settings.greetingsEnabled.toggle() }
    @objc private func toggleClingy() { settings.clingyEnabled.toggle() }

    private func collarMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Collar", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, value) in [("None", "none"), ("Band", "band"), ("Bell", "bell"),
                               ("Bow Tie", "bowtie"), ("Bandana", "bandana")] {
            let child = NSMenuItem(title: label, action: #selector(setCollar(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = value
            child.state = settings.collarStyle == value ? .on : .off
            sub.addItem(child)
        }
        parent.submenu = sub
        return parent
    }
    @objc private func setCollar(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String { settings.collarStyle = v }
    }

    private func modeTag(_ m: String) -> Int {
        ["roam": 0, "followCursor": 1, "followWindow": 2, "rest": 3][m] ?? 0
    }
    @objc private func setMode(_ sender: NSMenuItem) {
        settings.companionMode = ["roam", "followCursor", "followWindow", "rest"][sender.tag]
    }
    @objc private func toggleHidden() { controller.toggleHidden() }
    @objc private func sitNow() { controller.sitNow() }
    @objc private func sleepNow() { controller.sleepNow() }
    @objc private func togglePerch() { settings.perchOnWindows.toggle() }
    @objc private func toggleSound() { settings.soundEnabled.toggle() }
    @objc private func setVolume(_ sender: NSMenuItem) { settings.volume = Double(sender.tag) / 100.0 }
    @objc private func toggleLaunch() { settings.launchAtLogin.toggle() }
    @objc private func toggleCapture() { settings.hideFromCapture.toggle() }
    @objc private func setScale(_ sender: NSMenuItem) { settings.scale = sender.tag }
    @objc private func setSpeed(_ sender: NSMenuItem) { settings.speed = Double(sender.tag) / 10.0 }
    @objc private func setSleep(_ sender: NSMenuItem) { settings.sleepMinutes = sender.tag }

    @objc private func setBreak(_ sender: NSMenuItem) {
        settings.breakMinutes = sender.tag
        controller.resetBreakTimer()
    }

    @objc private func openTasks() { PanelWindows.shared.showTasks() }
    @objc private func openSettings() { PanelWindows.shared.showSettings(controller: controller) }
    @objc private func openAbout() { PanelWindows.shared.showAbout() }
    @objc private func quit() { NSApp.terminate(nil) }
}
