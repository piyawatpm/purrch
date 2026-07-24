import AppKit
import SwiftUI

/// Owns the window, drives the simulation clock, and handles the timed behaviours
/// (falling asleep when you step away, break reminders).
final class PetController: NSObject {
    let brain = PetBrain()

    private let window = PetWindow()
    private let bowlWindow = BowlWindow()
    private let mouseWindow = MouseWindow()
    private let toyOverlay = ToyPlacementOverlay()
    private let view: PetView
    private let popover = NSPopover()
    private let controlPopover = NSPopover()
    private let settings = Settings.shared
    private var timer: Timer?
    private var lastTick = CFAbsoluteTimeGetCurrent()
    private var lastBreak = Date()
    private var appliedScale: Int
    private var playedCrunch = false
    private var quickAddHotKey: GlobalHotKey?

    private let breakMessages = [
        "stretch?", "drink some water", "look away for a bit",
        "stand up?", "rest your eyes", "come back in a minute",
    ]

    override init() {
        appliedScale = settings.scale
        view = PetView(brain: brain)
        super.init()
        window.contentView = view
        applyScale()
        window.orderFrontRegardless()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        controlPopover.behavior = .transient
        controlPopover.animates = true

        view.onClick = { [weak self] in self?.handleClick() }
        view.onRightClick = { [weak self] in self?.showControlPanel() }
        let trace = CommandLine.arguments.contains("--trace")
        brain.onMeow = { Sounds.shared.play(.meow) }
        brain.onStateChange = { [weak self] state in
            guard let self else { return }
            if trace {
                NSLog("state -> \(state)  pos=(\(Int(self.brain.position.x)),\(Int(self.brain.position.y)))  " +
                      "perch=\(self.brain.perch.map { Int($0.y) }.map(String.init) ?? "floor")  " +
                      "bowl=\(self.brain.bowl.map { Int($0.x) }.map(String.init) ?? "nil")  " +
                      "mouse=\(self.brain.mouse.map { Int($0.x) }.map(String.init) ?? "nil")  " +
                      "caught=\(self.brain.mouseCaught)  clingy=\(self.brain.isClingy)  " +
                      "full=\(self.brain.bowlFull)  collar=\(SpriteLibrary.shared.loadedStyle)")
            }
            self.window.invalidateCursorRects(for: view)
            if state == .happy { Sounds.shared.play(.meow) }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: Settings.didChange, object: nil)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                // A display was added, removed, or moved. Get him back onto real
                // estate that still exists before repositioning his window.
                self?.brain.reconcileScreens()
                self?.applyScale()
            }
        NotificationCenter.default.addObserver(
            self, selector: #selector(paletteChanged),
            name: Settings.paletteChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(allTasksDone),
            name: TaskStore.allDoneToday, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(taskCompleted),
            name: TaskStore.taskCompleted, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshQuickAddHotKey),
            name: Settings.quickAddChanged, object: nil)
        refreshQuickAddHotKey()

        TaskStore.shared.pruneHistory()

        start()
    }

    // MARK: - Clock

    private func start() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common keeps him moving while menus are open or a window is being resized.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = min(0.1, now - lastTick)       // clamp so a wake-from-sleep doesn't teleport him
        lastTick = now

        guard !settings.hidden else { return }

        brain.tick(dt: dt)
        view.stepParticles(dt: dt)
        checkSleep()
        checkBreak()
        checkTimeOfDay()

        window.setFrameOrigin(PetView.windowOrigin(for: brain.position, scale: settings.scale))
        view.needsDisplay = true

        // The bowl is declarative: whatever the brain says, the window mirrors.
        if let bowl = brain.bowl {
            bowlWindow.show(at: bowl, kind: brain.bowlKind, full: brain.bowlFull, scale: settings.scale)
        } else {
            bowlWindow.hide()
        }

        if let mouse = brain.mouse {
            mouseWindow.show(at: mouse, kind: brain.toyKind, running: brain.mouseRunning,
                             facingRight: brain.mouseFacingRight, scale: settings.scale)
        } else {
            mouseWindow.hide()
        }

        if brain.state == .eat, !playedCrunch {
            playedCrunch = true
            Sounds.shared.play(.crunch)
        } else if brain.state != .eat {
            playedCrunch = false
        }
    }

    // MARK: - Click

    /// A click both greets him and brings up the day's list.
    private func handleClick() {
        brain.pet()
        view.burstHearts()
        toggleTaskPopover()
    }

    func toggleTaskPopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.contentViewController = NSHostingController(
            rootView: TaskPopoverView(onOpenFullList: { [weak self] in
                self?.popover.performClose(nil)
                PanelWindows.shared.showTasks()
            }))
        // The panel can't take focus itself, so the app has to come forward for
        // the popover's text field to accept typing.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: view.popoverAnchorRect, of: view, preferredEdge: .maxY)
        brain.hold()
    }

    func feed() {
        brain.feed()
    }

    /// The organised control panel shown when you right-click the cat.
    func debugShowControlPanel() { showControlPanel() }

    private func showControlPanel() {
        if controlPopover.isShown { controlPopover.performClose(nil); return }
        if popover.isShown { popover.performClose(nil) }

        let actions = PetControlActions(
            comeHere: { [weak self] in self?.comeHere() },
            feed:     { [weak self] in self?.feed() },
            placeToy: { [weak self] in self?.startPlacingToy() },
            sit:      { [weak self] in self?.sitNow() },
            sleep:    { [weak self] in self?.sleepNow() },
            hide:     { [weak self] in self?.toggleHidden() },
            openTasks:   { PanelWindows.shared.showTasks() },
            openSettings:{ [weak self] in guard let self else { return }
                           PanelWindows.shared.showSettings(controller: self) },
            openAbout:   { PanelWindows.shared.showAbout() },
            close:    { [weak self] in self?.controlPopover.performClose(nil) })

        controlPopover.contentViewController = NSHostingController(rootView: PetControlPanel(actions: actions))
        NSApp.activate(ignoringOtherApps: true)
        controlPopover.show(relativeTo: view.popoverAnchorRect, of: view, preferredEdge: .maxY)
    }

    func dropMouse() { brain.dropMouse() }

    /// Arms placement mode: the next click drops the selected toy there.
    func startPlacingToy() {
        toyOverlay.begin(kind: settings.selectedToy) { [weak self] point in
            guard let self else { return }
            self.brain.placeToy(at: point, kind: self.settings.selectedToy)
        }
    }

    /// Plays a named animation on the cat — used by the Animation Tester.
    func playAnimation(_ name: String) {
        guard let state = PetState(rawValue: name) else { return }
        brain.wake()
        brain.forceState(state, for: 6)
    }

    /// Every animation the cat has, for the tester menu.
    var allAnimations: [String] { PetState.allCases.map { $0.rawValue } }

    @objc private func refreshQuickAddHotKey() {
        guard settings.quickAddEnabled else {
            quickAddHotKey = nil
            return
        }
        guard quickAddHotKey == nil else { return }
        quickAddHotKey = GlobalHotKey.quickAdd { [weak self] in
            DispatchQueue.main.async { self?.quickAdd() }
        }
        if quickAddHotKey == nil {
            NSLog("quick-add shortcut is already claimed by another app")
        }
    }

    /// Opens the list wherever it can be reached: on the cat if he's on screen,
    /// otherwise the full window.
    func quickAdd() {
        if settings.hidden {
            PanelWindows.shared.showTasks()
            return
        }
        brain.wake()
        if !popover.isShown { toggleTaskPopover() }
    }

    @objc private func taskCompleted() {
        // One meal per completion burst — ticking three things off doesn't queue
        // three dinners.
        guard brain.bowl == nil else { return }
        brain.feed()
    }

    private func checkSleep() {
        guard brain.state != .sleep else { return }
        brain.considerSleeping()
    }

    private func checkBreak() {
        let minutes = settings.breakMinutes
        guard minutes > 0 else { return }
        guard Date().timeIntervalSince(lastBreak) >= Double(minutes) * 60 else { return }
        // Don't nag someone who isn't at the machine.
        guard brain.cachedIdleSeconds() < 60 else { return }

        lastBreak = Date()
        brain.comeHere()
        let open = TaskStore.shared.openCount
        let message = open > 0 && Bool.random()
            ? (open == 1 ? "1 task left — take a breather" : "\(open) tasks left — take a breather")
            : breakMessages.randomElement()!
        brain.say(message, for: 7)
        Sounds.shared.play(.meow)
    }

    @objc private func paletteChanged() {
        SpriteLibrary.shared.applyPalette()
        view.needsDisplay = true
    }

    @objc private func allTasksDone() {
        brain.wake()
        brain.celebrate("all done \u{2665}")
        view.burstHearts()
    }

    private var lastTimeCheck = Date.distantPast
    private func checkTimeOfDay() {
        let now = Date()
        guard now.timeIntervalSince(lastTimeCheck) > 60 else { return }
        lastTimeCheck = now
        let hour = Calendar.current.component(.hour, from: now)
        let atKeyboard = brain.cachedIdleSeconds() < 90
        // The special night moment isn't gated on the greetings toggle — it's a
        // quiet rare treat, not a nudge.
        brain.considerSpecial(hour: hour, atKeyboard: atKeyboard)
        guard settings.greetingsEnabled else { return }
        brain.considerTimeOfDay(hour: hour, atKeyboard: atKeyboard)
    }

    /// Restart the break interval, e.g. after the user changes it in Settings.
    func resetBreakTimer() { lastBreak = Date() }

    // MARK: - Settings

    @objc private func settingsChanged() {
        if settings.scale != appliedScale {
            appliedScale = settings.scale
            applyScale()
        }
        window.sharingType = settings.hideFromCapture ? .none : .readOnly
        if settings.hidden {
            window.orderOut(nil)
        } else if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    private func applyScale() {
        let size = PetView.windowSize(scale: settings.scale)
        let origin = PetView.windowOrigin(for: brain.position, scale: settings.scale)
        window.setFrame(CGRect(origin: origin, size: size), display: true)
        view.frame = CGRect(origin: .zero, size: size)
        window.invalidateCursorRects(for: view)
    }

    // MARK: - Commands from the menu

    func toggleHidden() { settings.hidden.toggle() }

    func applyCaptureSetting() {
        window.sharingType = settings.hideFromCapture ? .none : .readOnly
    }

    func sitNow() { brain.wake(); brain.sitNow() }

    func sleepNow() { brain.forceSleep() }

    func comeHere() { brain.wake(); brain.comeHere() }

    func greet(_ text: String) { brain.wake(); brain.say(text, for: 5) }
}

extension PetController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        brain.release()
    }
}
