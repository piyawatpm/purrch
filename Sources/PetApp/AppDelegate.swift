import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // menu bar only, no Dock icon

        let controller = PetController()
        self.controller = controller
        menuBar = MenuBarController(controller: controller)

        let settings = Settings.shared
        controller.applyCaptureSetting()

        // Lets a panel be opened straight from the command line, which is how the UI
        // gets exercised without clicking through the menu bar.
        let args = CommandLine.arguments
        let debugFlags = ["--tasks", "--about", "--settings", "--feed", "--popover", "--edge-test", "--complete-task", "--perch-test", "--anim-cycle", "--emotions", "--mouse", "--mode", "--clingy", "--mouse-ledge", "--stargaze", "--sleep", "--sleep-persist", "--bellyplay", "--panel", "--sleep-disturb", "--bubble", "--toy-floor", "--toy-high", "--toy-sulk"]
        if args.contains(where: debugFlags.contains) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if args.contains("--tasks") { PanelWindows.shared.showTasks() }
                if args.contains("--about") { PanelWindows.shared.showAbout() }
                if args.contains("--settings") { PanelWindows.shared.showSettings(controller: controller) }
                // Delayed so it can be combined with --perch-test: he settles on a
                // ledge first, then gets fed there.
                if args.contains("--feed") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { controller.feed() }
                }
                if args.contains("--popover") { controller.toggleTaskPopover() }
                if args.contains("--edge-test") { controller.brain.debugPatrolEdge(rightward: true) }
                if args.contains("--perch-test") { NSLog(controller.brain.debugDropOntoWindow()) }
                if args.contains("--anim-cycle") { controller.brain.debugCycleAnimations() }
                if args.contains("--emotions") { controller.brain.debugEmotions() }
                if args.contains("--mouse") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { controller.dropMouse() }
                }
                if let i = args.firstIndex(of: "--mode"), i + 1 < args.count {
                    Settings.shared.companionMode = args[i + 1]
                }
                if args.contains("--clingy") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { controller.brain.debugClingy() }
                }
                if args.contains("--mouse-ledge") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { NSLog(controller.brain.debugMouseOnLedge()) }
                }
                if args.contains("--stargaze") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.brain.forceState(.stargaze, for: 4.0) }
                }
                if args.contains("--sleep") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.sleepNow() }
                }
                if args.contains("--sleep-persist") {
                    // Sleep, then keep poking cachedIdleSeconds low by simulating a pet
                    // after a delay to prove manual sleep persists then wakes on interaction.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.sleepNow() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { controller.brain.pet() }
                }
                if args.contains("--bellyplay") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.brain.forceState(.bellyplay, for: 4.0) }
                }
                if args.contains("--panel") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.debugShowControlPanel() }
                }
                if args.contains("--sleep-disturb") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.brain.debugSleepDisturb() }
                }
                if args.contains("--bubble") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { controller.brain.say("got a treat?", for: 30) }
                }
                if args.contains("--toy-floor") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.brain.debugPlaceToy(reachable: true) }
                }
                if args.contains("--toy-sulk") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.brain.debugPlaceToy(reachable: false) }
                }
                if args.contains("--toy-high") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.brain.debugPlaceToy(reachable: false) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 16.0) { controller.brain.debugPetNow() }
                }
                if args.contains("--complete-task"),
                   let open = TaskStore.shared.today.first(where: { !$0.isDone }) {
                    TaskStore.shared.toggle(open)
                }
            }
        }

        if !settings.hasOnboarded {
            settings.hasOnboarded = true
            // Let him land first, then say hello and open Settings so the name can be set.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                controller.greet("hello \u{2665}")
                PanelWindows.shared.showSettings(controller: controller)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Right-clicking the cat opens the same menu as the menu bar item.
    @objc func showMenuFromPet(_ sender: Any?) {
        menuBar?.popUpAtMouse()
    }
}
