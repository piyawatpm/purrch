import AppKit
import IOKit

/// The simulation: where the cat is, what he's doing, and what he does next.
///
/// Positions are in AppKit screen coordinates (origin bottom-left, y up). `position`
/// is his feet — the point where he meets the floor — which keeps the maths the same
/// whatever sprite scale is in use.
final class PetBrain {
    private(set) var state: PetState = .idle
    private(set) var position: CGPoint = .zero
    private(set) var facingRight = true
    private(set) var stateElapsed: TimeInterval = 0

    /// Set while a bubble is showing; the view draws it above his head.
    private(set) var speech: String?
    private(set) var speechStartedAt: CFAbsoluteTime = 0
    private var speechRemaining: TimeInterval = 0

    private var animElapsed: TimeInterval = 0
    private(set) var frameIndex = 0

    private var velocity = CGVector.zero
    private var stateDuration: TimeInterval = 2
    private var homeScreen: NSScreen?

    /// Where the food bowl is sitting, in screen coordinates at floor level.
    private(set) var bowl: CGPoint?
    private(set) var bowlKind = "kibble"
    private(set) var bowlFull = true
    private var bowlLingering: TimeInterval = 0
    /// Why he is walking somewhere specific, and where to.
    private enum Errand { case meal, cursor, summons, mouse }
    private var errand: Errand?
    private var walkTarget: CGFloat?
    private var errandElapsed: TimeInterval = 0

    /// Frozen in place while his task list is open.
    private(set) var isHeld = false

    /// True while he's fussing over the cursor, so the view can tell.
    private(set) var isClingy = false
    private var clingyAffectionCd: TimeInterval = 0
    /// Test seam: when set, stands in for the real cursor position.
    var debugCursor: CGPoint?

    /// Height he started falling from, so a long drop can land harder.
    private var fallPeakY: CGFloat = 0
    private var pendingDizzy = false
    private var runLaps = 0
    /// Set when a yawn is a prelude to sleep rather than just a stretch of the jaw.
    private var sleepy = false
    /// Stops the time-of-day greetings firing more than once each.
    private var lastGreetedHour = -1

    /// How he spends his time: free roam, following the cursor, following the
    /// active window, or resting in place.
    enum Mode: String { case roam, followCursor, followWindow, rest }
    var mode: Mode { Mode(rawValue: settings.companionMode) ?? .roam }

    /// A placed toy, if one is out. The user drops it; he goes to reach it.
    private(set) var mouse: CGPoint?                // the toy's position
    private(set) var mouseRunning = false           // whether the toy sprite animates
    private var toyFacingRight = true
    var mouseFacingRight: Bool { toyFacingRight }
    let mouseCaught = false                          // kept for the debug trace
    private(set) var toyKind = "mouse"              // mouse | ball | feather
    private var toySurface: Surface?               // the ledge it sits on, nil = floor
    private var toyReachable = true
    private var toyReached = false
    private var toyTryTime: TimeInterval = 0        // time spent failing to reach it
    private var reachingToy = false                // lets him land on a toy's ledge
    private var toyFalling = false                 // the toy is dropping under gravity
    private var toyVelY: CGFloat = 0
    private var toyLandY: CGFloat = 0              // the surface it will settle on
    /// A lasting sulk when he can't reach a toy — cleared only by petting him.
    private(set) var angryMood = false
    private var angryPromptCd: TimeInterval = 0
    private var angryTimeLeft: TimeInterval = 0    // he gets over it on his own eventually
    private var pounceCooldown: TimeInterval = 0
    private var catHuntMul: CGFloat = 3.4           // his pursuit sprint multiplier

    /// The ledge he is standing on. nil means the screen floor.
    private(set) var perch: Surface?
    private let surfaces = WindowSurfaces()
    private let gravity: CGFloat = 1400

    var onStateChange: ((PetState) -> Void)?
    /// Called when he wants to make a sound with a line of chatter.
    var onMeow: (() -> Void)?

    private var chatterCd: TimeInterval = .random(in: 18...40)

    private let settings = Settings.shared
    private let lib = SpriteLibrary.shared

    // Walking speed in points/sec at speed multiplier 1.0.
    private let baseSpeed: CGFloat = 34

    init() {
        homeScreen = NSScreen.main
        position = startPosition()
    }

    // MARK: - Geometry

    private func startPosition() -> CGPoint {
        let screen = homeScreen ?? NSScreen.screens.first
        guard let f = screen?.visibleFrame else { return .zero }
        return CGPoint(x: f.midX, y: f.minY)
    }

    /// The screen he's currently standing on, falling back to the nearest one.
    private var currentScreen: NSScreen {
        if let s = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: position.x, y: position.y + 1)) }) {
            return s
        }
        return nearestScreen(to: position)
    }

    private func nearestScreen(to point: CGPoint) -> NSScreen {
        // Compare against the whole rect, not just midX, so a tall screen stacked
        // above another isn't judged solely on horizontal distance.
        let byDistance = NSScreen.screens.min { a, b in
            distance(from: point, to: a.frame) < distance(from: point, to: b.frame)
        }
        return byDistance ?? NSScreen.screens.first ?? NSScreen.main!
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// The screen's own floor.
    private var groundY: CGFloat { currentScreen.visibleFrame.minY }

    /// The line he is currently walking along — a window's top edge when perched.
    private var supportY: CGFloat { perch?.y ?? groundY }

    /// The stretch of x he can walk without falling off.
    private var walkableRange: (lo: CGFloat, hi: CGFloat) {
        if let perch {
            // Windows are ledges: he may walk right up to the corner.
            let inset = min(edgeMargin * 0.35, max(0, perch.width / 2 - 1))
            return (perch.minX + inset, perch.maxX - inset)
        }
        let f = currentScreen.visibleFrame
        let m = min(edgeMargin, f.width / 2 - 1)
        return (f.minX + m, f.maxX - m)
    }

    /// How close to a screen edge he may stand: exactly far enough that no part of
    /// him is clipped, measured from the artwork rather than guessed at.
    private var edgeMargin: CGFloat {
        lib.contentHalfWidth * CGFloat(settings.scale)
    }

    /// Keeps an x inside a screen's walkable strip.
    private func clampToWalkable(_ x: CGFloat, on screen: NSScreen) -> CGFloat {
        let f = screen.visibleFrame
        let margin = min(edgeMargin, f.width / 2 - 1)
        return min(max(x, f.minX + margin), f.maxX - margin)
    }

    // MARK: - Perching

    /// The highest ledge crossed on the way down between two heights.
    private func landing(at x: CGFloat, from highY: CGFloat, to lowY: CGFloat) -> Surface? {
        let candidates = (settings.perchOnWindows || reachingToy)
            ? surfaces.supports(at: x, groundY: groundY, screen: currentScreen)
            : [Surface(minX: currentScreen.visibleFrame.minX,
                       maxX: currentScreen.visibleFrame.maxX,
                       y: groundY, isGround: true)]
        return candidates
            .filter { $0.y <= highY + 0.5 && $0.y >= lowY - 0.5 }
            .max { $0.y < $1.y }
    }

    /// A ledge close enough above him to be worth jumping for.
    private func jumpTarget() -> Surface? {
        guard settings.perchOnWindows, perch == nil else { return nil }
        return surfaces.supports(at: position.x, groundY: groundY, screen: currentScreen)
            .filter { !$0.isGround && $0.y > position.y + 40 && $0.y < position.y + maxJump }
            .min { $0.y < $1.y }          // the lowest reachable one
    }

    private func tryJumpToWindow() -> Bool {
        guard let target = jumpTarget() else { return false }
        leap(toHeight: target.y - position.y + 30)
        return true
    }

    private func startFalling(dx: CGFloat) {
        perch = nil
        velocity = CGVector(dx: dx, dy: 0)
        fallPeakY = position.y
        enter(.fall, for: 6)
    }

    /// How high he can leap, in points — the base scaled by the jump-height setting.
    var maxJump: CGFloat { 300 * CGFloat(settings.jumpHeight) }

    /// An upward leap to `height` points, showing the jump animation (vs the flail
    /// of a fall). Lands via the same physics.
    private func leap(toHeight height: CGFloat, dx: CGFloat = 0) {
        perch = nil
        velocity = CGVector(dx: dx, dy: sqrt(2 * gravity * max(20, height)))
        fallPeakY = position.y
        enter(.jump, for: 6)
    }

    /// Drops him if the window he was standing on has moved, closed, or scrolled away.
    private func validatePerch() {
        guard let current = perch else { return }
        guard settings.perchOnWindows else {
            startFalling(dx: 0)
            return
        }
        if !surfaces.stillExists(current, at: position.x) {
            startFalling(dx: 0)
        }
    }

    /// A screen sharing the edge we're walking off, so he can cross displays.
    /// Only side-by-side screens qualify — there's no walkable path between
    /// displays stacked vertically, so at those edges he simply turns around.
    private func neighbour(goingRight: Bool) -> NSScreen? {
        let f = currentScreen.frame
        return NSScreen.screens.first { other in
            guard other != currentScreen else { return false }
            let o = other.frame
            let touches = goingRight ? abs(o.minX - f.maxX) < 4 : abs(o.maxX - f.minX) < 4
            let overlapsVertically = o.maxY > f.minY && o.minY < f.maxY
            return touches && overlapsVertically
        }
    }

    /// Called when displays are added, removed, or rearranged. Without this he can
    /// be left standing on coordinates that no longer belong to any screen — his
    /// window parked off-screen forever.
    func reconcileScreens() {
        cancelErrand()
        perch = nil
        surfaces.refresh()
        if NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: position.x, y: position.y + 1)) }) {
            position.x = clampToWalkable(position.x, on: currentScreen)
            position.y = groundY
            return
        }
        let screen = nearestScreen(to: position)
        position = CGPoint(x: clampToWalkable(position.x, on: screen), y: screen.visibleFrame.minY)
        if state == .fall || state == .drag { enter(.idle, for: 1.5) }
    }

    // MARK: - Tick

    func tick(dt: TimeInterval) {
        stateElapsed += dt
        if speechRemaining > 0 {
            speechRemaining -= dt
            if speechRemaining <= 0 { speech = nil }
        }

        if angryMood {
            angryTimeLeft -= dt
            if angryTimeLeft <= 0 { calmDown() }
        }

        if bowlLingering > 0 {
            bowlLingering -= dt
            if bowlLingering <= 0 { bowl = nil }
        } else if bowl != nil, !isDining {
            // Safety net: a meal that got interrupted anyway shouldn't leave a
            // bowl sitting on the desktop indefinitely.
            bowlLingering = 2.0
        }

        if settings.perchOnWindows {
            surfaces.refreshIfStale()
            if state != .drag, state != .fall { validatePerch() }
        } else if perch != nil {
            startFalling(dx: 0)
        }

        // While the task list is open he sits still rather than wandering off
        // and dragging the popover with him.
        if isHeld {
            advanceAnimation(dt)
            return
        }

        if pounceCooldown > 0 { pounceCooldown -= dt }
        if mouse != nil { updateMouse(dt) }

        // A clingy cat drops everything to be near your cursor.
        if tickClingy(dt) {
            advanceAnimation(dt)
            return
        }
        applyMode(dt)

        switch state {
        case .idle:   tickIdle()
        case .walk:   if mouse == nil || toyReached { tickWalk(dt) }
        case .sit, .groom: tickResting()
        case .sleep:  tickSleep(dt)
        case .drag:   break                 // position is driven by the mouse
        case .fall:   tickFall(dt)
        case .jump:   tickFall(dt)
        case .happy:  if stateElapsed > 1.8 { enter(.idle) }
        case .eat:    tickEat()

        case .land:
            // Springs back up, or sits down seeing stars if it was a long way.
            if stateElapsed > clipDuration(.land) {
                if pendingDizzy {
                    pendingDizzy = false
                    enter(.dizzy, for: .random(in: 2.5...4))
                } else {
                    enter(.idle, for: .random(in: 0.8...1.6))
                }
            }
        case .dizzy, .scratch, .loaf, .wiggle:
            if stateElapsed > stateDuration { enter(.idle, for: .random(in: 1...2.5)) }
        case .stretch:
            if stateElapsed > max(stateDuration, clipDuration(.stretch)) {
                enter(.idle, for: .random(in: 1.5...3))
            }
        case .yawn:
            if stateElapsed > clipDuration(.yawn) {
                // A yawn brought on by tiredness leads straight to sleep; a
                // spontaneous one just settles him down.
                enter(sleepy ? .sleep : .sit, for: sleepy ? .infinity : .random(in: 2...4))
            }
        case .run:    tickRun(dt)
        case .pounce: tickPounce(dt)
        case .play:
            if stateElapsed > stateDuration {
                if toyReached { removeMouse(); toyReached = false }
                enter(.idle, for: .random(in: 1...2))
            }
        case .love, .angry, .curious, .surprise, .purr,
             .flop, .rollover, .arch, .beg, .sniff, .knead, .blep, .chatter, .rub,
             .stargaze, .bellyplay:
            if stateElapsed > stateDuration { enter(.idle, for: .random(in: 1...2)) }
        }

        considerChatter(dt)
        advanceAnimation(dt)
    }

    /// Every so often he pipes up on his own — a sudden meow, a request for a
    /// treat, or a small thought. Only when he's calm and not already saying
    /// something, so it never talks over itself.
    private func considerChatter(_ dt: TimeInterval) {
        guard speech == nil, !isHeld, mouse == nil, bowl == nil, !isClingy else { return }
        switch state {
        case .idle, .sit, .loaf, .groom, .walk: break
        default: return
        }
        chatterCd -= dt
        guard chatterCd <= 0 else { return }
        chatterCd = .random(in: 45...110)

        switch Int.random(in: 0..<100) {
        case 0..<36:                                    // a sudden meow
            onMeow?()
            say(["meow", "mrrp", "mrow", "prrrt", "mew", "meww"].randomElement()!, for: 2.6)
        case 36..<60:                                   // asking for a treat
            if state == .idle || state == .sit || state == .loaf {
                enter(.beg, for: 3.4)
            }
            say(["treat?", "snack?", "got a treat?", "feed me?", "hungry…", "one treat?"].randomElement()!, for: 4)
        case 60..<82:                                   // a little thought
            say(["hmm", "so warm", "nice", "boop", "\u{2665}", "…", "cozy"].randomElement()!, for: 2.6)
        default:                                        // wanting attention
            say(["hi", "pet me?", "hey", "look", "still here?"].randomElement()!, for: 3)
        }
    }

    /// Animations that play through once and hold on the last frame rather than
    /// looping: a squash, a stretch, a yawn.
    private var isOneShot: Bool {
        switch state {
        case .fall, .land, .stretch, .yawn, .surprise, .arch, .pounce, .rollover, .stargaze, .jump:
            return true
        default:
            return false
        }
    }

    private func advanceAnimation(_ dt: TimeInterval) {
        let clip = lib.clip(state)
        animElapsed += dt
        if animElapsed >= clip.frameDuration {
            animElapsed -= clip.frameDuration
            if isOneShot {
                frameIndex = min(frameIndex + 1, clip.frames.count - 1)
            } else {
                frameIndex = (frameIndex + 1) % max(1, clip.frames.count)
            }
        }
    }

    /// How long a one-shot clip takes to play through, so states can be timed to
    /// the artwork instead of to a guessed number.
    private func clipDuration(_ state: PetState) -> TimeInterval {
        let clip = lib.clip(state)
        return Double(clip.frames.count) * clip.frameDuration
    }

    /// When the cursor lingers near him he becomes clingy: trots to keep up with
    /// it, then rubs and shows hearts once he's alongside. Roam mode only — the
    /// other modes already decide where he goes, and rest means leave him be.
    /// Returns true while it's actively in control.
    private func tickClingy(_ dt: TimeInterval) -> Bool {
        guard settings.clingyEnabled, mode == .roam, !angryMood,
              mouse == nil, bowl == nil, !isHeld else { isClingy = false; return false }

        switch state {
        case .idle, .sit, .walk, .loaf, .groom, .rub, .love, .curious, .happy: break
        default: isClingy = false; return false
        }

        let cursor = debugCursor ?? NSEvent.mouseLocation
        let screen = currentScreen
        let dx = cursor.x - position.x
        // Needs the cursor on his screen and reasonably nearby, not miles overhead.
        guard screen.frame.contains(cursor), abs(dx) < 150,
              cursor.y - groundY < 620 else {
            isClingy = false
            return false
        }

        isClingy = true
        facingRight = dx >= 0
        if clingyAffectionCd > 0 { clingyAffectionCd -= dt }

        if abs(dx) > 52 {
            // clingy trot to catch up — a touch faster than an idle amble
            walkTarget = nil
            errand = nil
            let step = baseSpeed * 2.0 * CGFloat(settings.speed) * CGFloat(dt)
            position.x = min(max(position.x + (facingRight ? step : -step),
                                 walkableRange.lo), walkableRange.hi)
            position.y = supportY
            if state != .walk { enter(.walk, for: 30) }
            return true
        }

        // Alongside the cursor now — settle and fuss over it.
        if state == .walk { enter(.sit, for: 1.0) }
        if clingyAffectionCd <= 0,
           state == .idle || state == .sit || state == .loaf || state == .groom {
            enter([.rub, .love, .rub].randomElement()!, for: .random(in: 1.6...2.6))
            clingyAffectionCd = .random(in: 2.5...4.5)
            if Bool.random() { say("\u{2665}", for: 1.4) }
        }
        return true
    }

    /// Steers his intentions according to the companion mode. Only nudges him when
    /// he's between actions (idle/sit) so it never interrupts an animation.
    private func applyMode(_ dt: TimeInterval) {
        // A mouse hunt overrides every mode until it's over.
        if mouse != nil { pursueToy(dt); return }
        guard walkTarget == nil else { return }
        let restful: Set<PetState> = [.idle, .sit, .loaf, .groom]

        switch mode {
        case .roam:
            break                                   // the default idle roster handles it
        case .rest:
            // Settle down and stay; no wandering, no antics.
            if state == .walk { enter(.idle, for: 1.0) }
            else if restful.contains(state), stateElapsed > 3, state != .loaf {
                enter([.loaf, .sit].randomElement()!, for: .random(in: 8...20))
            }
        case .followCursor:
            guard restful.contains(state) || state == .walk else { return }
            followPoint(NSEvent.mouseLocation, gap: 60, sitWhenClose: true)
        case .followWindow:
            guard restful.contains(state) || state == .walk else { return }
            if let target = frontWindowPerch() { followWindow(target) }
        }
    }

    /// Walks toward an on-screen point, sitting once close enough.
    private func followPoint(_ point: CGPoint, gap: CGFloat, sitWhenClose: Bool) {
        let screen = currentScreen
        guard screen.frame.contains(point) else {
            if state == .walk { enter(.idle, for: 1) }
            return
        }
        let target = clampToWalkable(point.x, on: screen)
        if abs(target - position.x) > gap {
            facingRight = target > position.x
            walkTarget = target
            errand = .cursor
            errandElapsed = 0
            enter(.walk, for: 30)
        } else if sitWhenClose, state == .walk {
            enter(.sit, for: 2)
        }
    }

    /// The frontmost ordinary window's top-left region, as a place to sit under
    /// (or perch on, when climbing is enabled).
    private func frontWindowPerch() -> (x: CGFloat, surface: Surface?)? {
        surfaces.refreshIfStale()
        guard let front = surfaces.frontmostSurface() else { return nil }
        let x = min(max(front.minX + 30, front.minX), front.maxX - 30)
        return (x, settings.perchOnWindows ? front : nil)
    }

    private func followWindow(_ target: (x: CGFloat, surface: Surface?)) {
        let screen = currentScreen
        let destX = clampToWalkable(target.x, on: screen)
        // Already there? Sit tight.
        if abs(destX - position.x) < 50, (target.surface == nil) == (perch == nil) { return }

        if let surface = target.surface, settings.perchOnWindows {
            // Jump up onto the window if he can, otherwise just move under it.
            if abs(surface.y - position.y) > 40, surface.y > position.y,
               surface.y < position.y + 280 {
                velocity = CGVector(dx: 0, dy: sqrt(2 * gravity * (surface.y - position.y + 30)))
                perch = nil
                enter(.fall, for: 6)
                return
            }
        }
        facingRight = destX > position.x
        walkTarget = destX
        errand = .summons
        errandElapsed = 0
        enter(.walk, for: 30)
    }

    private func tickIdle() {
        // A lasting sulk: he sits cross and glares now and then until he's petted.
        if angryMood {
            angryPromptCd -= 1.0 / 30.0
            if angryPromptCd <= 0 {
                angryPromptCd = .random(in: 4...8)
                enter(.angry, for: 2.2)
                if Bool.random() { say(["hmph", "grr"].randomElement()!, for: 2) }
            }
            return
        }
        // In rest mode the idle antics are suppressed; applyMode keeps him settled.
        if mode == .rest { return }
        guard stateElapsed > stateDuration else { return }
        // Weighted roster. The last few are the rare ones you'll only catch now
        // and then — the whole point of leaving him on screen.
        // Common actions first, then a long tail of rarer antics you'll only catch
        // occasionally — the whole point of leaving him on screen.
        switch Int.random(in: 0..<100) {
        case 0..<26:  startWalk()
        case 26..<32: if !tryJumpToWindow() { startWalk() }
        case 32..<37: if !chaseCursor() { startWalk() }
        case 37..<48: enter(.sit, for: .random(in: 4...9))
        case 48..<57: enter(.groom, for: .random(in: 3...6))
        case 57..<64: enter(.loaf, for: .random(in: 6...14))
        case 64..<69: enter(.sniff, for: .random(in: 3...5))
        default:      startRareAntic()
        }
    }

    /// The uncommon flourishes. Zoomies, a stretch, a flop, belly-up, an arch —
    /// each fairly unlikely on any given idle tick.
    private func startRareAntic() {
        guard settings.anticsEnabled else {
            enter([.sit, .groom, .loaf].randomElement()!, for: .random(in: 4...9))
            return
        }
        enum Antic: CaseIterable {
            case stretch, yawn, scratch, wiggle, zoomies, flop, rollover
            case arch, beg, blep, chatter, rub, knead, play, bellyplay
        }
        switch Antic.allCases.randomElement()! {
        case .stretch:  enter(.stretch, for: clipDuration(.stretch))
        case .yawn:     enter(.yawn, for: clipDuration(.yawn))
        case .scratch:  enter(.scratch, for: .random(in: 2...3.5))
        case .wiggle:   enter(.wiggle, for: 1.6)
        case .zoomies:  startZoomies()
        case .flop:     enter(.flop, for: .random(in: 5...12))
        case .rollover: enter(.rollover, for: .random(in: 2.5...4))
        case .arch:     enter(.arch, for: .random(in: 2...3))
        case .beg:      enter(.beg, for: .random(in: 3...5))
        case .blep:     enter(.blep, for: .random(in: 2...4))
        case .chatter:  enter(.chatter, for: .random(in: 3...5))
        case .rub:      enter(.rub, for: .random(in: 2.5...4))
        case .knead:    enter(.knead, for: .random(in: 3...5))
        case .play:     enter(.play, for: .random(in: 2.5...4))
        case .bellyplay: enter(.bellyplay, for: .random(in: 3...5))
        }
    }

    private func startZoomies() {
        runLaps = Int.random(in: 2...4)
        facingRight = Bool.random()
        enter(.run, for: 9)
    }

    private func tickResting() {
        guard stateElapsed > stateDuration else { return }
        // Grooming settles back into a sit; sitting eventually gets bored.
        enter(state == .groom ? .sit : .idle, for: .random(in: 2...5))
    }

    private func tickWalk(_ dt: TimeInterval) {
        // An errand moves him at a steady trot regardless of the speed setting, so
        // dinner never takes an age.
        let onErrand = walkTarget != nil
        let multiplier = onErrand ? max(1.4, CGFloat(settings.speed)) : CGFloat(settings.speed)
        let step = baseSpeed * multiplier * CGFloat(dt)
        position.x += facingRight ? step : -step
        position.y = supportY

        // A mouse hunt drives him faster than the fleeing toy and lets the pounce,
        // not arrival, end the walk.
        if errand == .mouse, let target = walkTarget {
            let hunt = baseSpeed * catHuntMul * CGFloat(dt)
            position.x += position.x < target ? hunt : -hunt
            position.x = min(max(position.x, walkableRange.lo), walkableRange.hi)
            position.y = supportY
            errandElapsed += dt
            if errandElapsed > 12 { cancelErrand(); enter(.idle, for: 1) }
            return
        }

        if let target = walkTarget {
            errandElapsed += dt
            if abs(position.x - target) <= max(4, step) {
                position.x = target
                arrive()
            } else if errandElapsed > 15 {
                // Safety net: something moved the goalposts (a display change, a
                // throw). Give up rather than trudge on forever.
                cancelErrand()
                enter(.idle, for: 1.5)
            }
            return          // no edge-turning while heading somewhere specific
        }

        // On a window ledge he simply turns at the corners rather than stepping
        // into thin air; he only falls when the window itself goes away.
        if perch != nil {
            let range = walkableRange
            if facingRight, position.x > range.hi {
                position.x = range.hi
                facingRight = false
            } else if !facingRight, position.x < range.lo {
                position.x = range.lo
                facingRight = true
            }
        } else {
            let f = currentScreen.visibleFrame
            let margin = min(edgeMargin, f.width / 2 - 1)
            if facingRight, position.x > f.maxX - margin {
                if let next = neighbour(goingRight: true) {
                    position.x = next.visibleFrame.minX + margin
                    position.y = next.visibleFrame.minY
                } else {
                    position.x = f.maxX - margin
                    facingRight = false
                }
            } else if !facingRight, position.x < f.minX + margin {
                if let next = neighbour(goingRight: false) {
                    position.x = next.visibleFrame.maxX - margin
                    position.y = next.visibleFrame.minY
                } else {
                    position.x = f.minX + margin
                    facingRight = true
                }
            }
        }

        if stateElapsed > stateDuration { enter(.idle, for: .random(in: 1.5...4)) }
    }

    /// What happens once he reaches whatever he set off towards.
    private func arrive() {
        let finished = errand
        walkTarget = nil
        errand = nil
        errandElapsed = 0
        switch finished {
        case .meal:    enter(.eat, for: 3.4)
        case .cursor:
            if mouse != nil { enter(.idle, for: 0.2) }               // keep after the toy
            else if mode == .followCursor { enter(.sit, for: 2) }
            else { enter(.curious, for: .random(in: 2...3.5)) }      // "what's this?"
        case .summons: enter(.sit, for: 8)
        case .mouse:   enter(.idle, for: 0.2)     // the pounce path owns the ending
        case nil:      enter(.idle, for: 1.5)
        }
    }

    private func cancelErrand() {
        walkTarget = nil
        errand = nil
        errandElapsed = 0
    }

    /// Cats investigate. Every so often he notices the pointer and trots over.
    /// Returns false if the cursor isn't somewhere worth walking to.
    private func chaseCursor() -> Bool {
        let mouse = NSEvent.mouseLocation
        let screen = currentScreen
        guard screen.frame.contains(mouse) else { return false }
        let range = walkableRange
        let target = min(max(mouse.x, range.lo), range.hi)
        guard abs(target - position.x) > 70 else { return false }

        facingRight = target > position.x
        walkTarget = target
        errand = .cursor
        errandElapsed = 0
        enter(.walk, for: 30)
        return true
    }

    /// Zoomies. Sprints, bounces off the ends of whatever he's standing on, and
    /// burns out after a few laps.
    private func tickRun(_ dt: TimeInterval) {
        let step = baseSpeed * 3.1 * CGFloat(settings.speed) * CGFloat(dt)
        position.x += facingRight ? step : -step
        position.y = supportY

        let range = walkableRange
        if facingRight, position.x > range.hi {
            position.x = range.hi
            facingRight = false
            runLaps -= 1
        } else if !facingRight, position.x < range.lo {
            position.x = range.lo
            facingRight = true
            runLaps -= 1
        }

        if runLaps <= 0 || stateElapsed > 9 {
            enter(.idle, for: .random(in: 1.5...3))
        }
    }

    // MARK: - Toys

    /// Places a toy where the user dropped it, snapped down onto the surface
    /// beneath the point (a window top or the floor). The cat sets off to reach it.
    func placeToy(at point: CGPoint, kind: String) {
        wake()
        isHeld = false
        cancelMeal()
        angryMood = false
        toyKind = kind
        surfaces.refreshIfStale()

        let x = clampToWalkable(point.x, on: currentScreen)
        // the surface it will fall onto: the highest one at or below the drop point
        let below = surfaces.supports(at: x, groundY: groundY, screen: currentScreen)
            .filter { $0.y <= point.y + 4 }
            .max { $0.y < $1.y }
        let surface = below ?? Surface(minX: currentScreen.visibleFrame.minX,
                                       maxX: currentScreen.visibleFrame.maxX,
                                       y: groundY, isGround: true)
        toySurface = surface.isGround ? nil : surface
        toyLandY = surface.y
        // it starts falling from where you dropped it and drops onto that surface
        let startY = max(point.y, surface.y)
        mouse = CGPoint(x: x, y: startY)
        toyFalling = startY > surface.y + 1
        toyVelY = 0
        toyFacingRight = x >= position.x
        mouseRunning = false
        toyReached = false
        toyTryTime = 0
        // reachable from the floor, or a ledge within a leap's height of it
        toyReachable = surface.isGround || (surface.y - groundY < maxJump + 40)
        catHuntMul = .random(in: 2.8...3.8)
        enter(.idle, for: 0.3)
        say(toyReachable ? "!" : "hmm?", for: 1.2)
    }

    /// Convenience for the menu — drops the selected toy on the floor near him.
    func dropMouse() {
        let f = currentScreen.visibleFrame
        let side: CGFloat = position.x > f.midX ? -1 : 1
        placeToy(at: CGPoint(x: position.x + side * 130, y: groundY), kind: settings.selectedToy)
    }

    func removeMouse() {
        mouse = nil
        toySurface = nil
        mouseRunning = false
        reachingToy = false
    }

    var hasToy: Bool { mouse != nil }

    /// The toy's physics: it falls under gravity (same as the cat) onto whatever is
    /// beneath where you dropped it, and re-drops to the floor if that window goes.
    private func updateMouse(_ dt: TimeInterval) {
        guard var m = mouse else { return }

        if toyFalling {
            toyVelY -= gravity * CGFloat(dt)
            m.y += toyVelY * CGFloat(dt)
            if m.y <= toyLandY {
                m.y = toyLandY
                toyFalling = false
                toyVelY = 0
                mouseRunning = toyKind == "mouse"
            }
            mouse = m
            return
        }

        // if the window the toy was resting on has gone, let it fall to the floor
        if let ledge = toySurface, !surfaces.stillExists(ledge, at: m.x) {
            toySurface = nil
            toyLandY = groundY
            toyFalling = m.y > groundY + 1
            toyVelY = 0
            toyReachable = true
        }
    }

    /// The cat pursues the placed toy: walk to it, leap up to a ledge, pounce and
    /// play when he reaches it — or, if he just can't get to it, tire and sulk.
    private func pursueToy(_ dt: TimeInterval) {
        guard let t = mouse, !toyReached else { return }
        guard state == .idle || state == .walk || state == .sit else { return }

        let dist = t.x - position.x
        let heightGap = t.y - position.y
        facingRight = dist >= 0

        // While it's still dropping he just trots to be underneath it and waits;
        // reaching and pouncing wait until it has settled.
        if toyFalling {
            if state != .walk { enter(.walk, for: 30) }
            walkTarget = nil; errand = nil
            let step = baseSpeed * catHuntMul * CGFloat(dt)
            if abs(dist) > 30 {
                position.x = min(max(position.x + (dist > 0 ? step : -step),
                                     walkableRange.lo), walkableRange.hi)
                position.y = supportY
            }
            return
        }

        // Alongside and on the same level — pounce on it.
        if abs(dist) < 46, abs(heightGap) < 26 {
            if pounceCooldown <= 0 {
                enter(.pounce, for: clipDuration(.pounce))
                pounceCooldown = 1.0
            }
            return
        }

        if heightGap > 40 {                              // the toy is up high
            if toyReachable, abs(dist) < 70, heightGap < maxJump + 30 {
                reachingToy = true
                leap(toHeight: heightGap + 30)
                return
            }
            if !toyReachable {                           // beneath it, but out of reach
                toyTryTime += dt
                if abs(dist) < 60, pounceCooldown <= 0, state != .jump {
                    leap(toHeight: min(maxJump, 150))    // a hopeful hop that falls short
                    pounceCooldown = 1.5
                }
                if toyTryTime > 9 { frustrate(); return }
            }
        } else if heightGap < -40, perch != nil {
            startFalling(dx: dist > 0 ? 120 : -120)      // hop down after a toy below
            return
        }

        // Walk straight to it — driven here directly so it can't fight the ordinary
        // wander/errand walking (tickWalk is skipped while pursuing, below).
        if state != .walk { enter(.walk, for: 30) }
        walkTarget = nil
        errand = nil
        let step = baseSpeed * catHuntMul * CGFloat(dt)
        position.x = min(max(position.x + (dist > 0 ? step : -step),
                             walkableRange.lo), walkableRange.hi)
        position.y = supportY
    }

    /// He gives up on an unreachable toy and stays cross until he's petted.
    private func frustrate() {
        removeMouse()
        angryMood = true
        angryPromptCd = .random(in: 3...6)
        angryTimeLeft = .random(in: 20...35)        // sulks a while, then lets it go
        enter(.angry, for: 2.6)
        say(["hmph", "grr", "\u{2639}", "can't reach!"].randomElement()!, for: 3)
    }

    /// He gets over the sulk by himself when the cooldown runs out.
    private func calmDown() {
        angryMood = false
        enter(.stretch, for: clipDuration(.stretch))   // a shake-it-off stretch
        say(["hmf", "…", "fine"].randomElement()!, for: 2)
    }

    /// Resolves a pounce aimed at the toy.
    private func pounceResolve() {
        guard let t = mouse else { enter(.idle, for: 1); return }
        if abs(t.x - position.x) < 46, abs(t.y - position.y) < 28 {
            toyReached = true
            enter(.play, for: .random(in: 1.8...2.8))
            say(["got it!", "\u{2665}", "mine!", "gotcha"].randomElement()!, for: 1.6)
        } else {
            enter(.idle, for: 0.4)                       // missed; keep after it
        }
    }

    private func tickPounce(_ dt: TimeInterval) {
        let step = baseSpeed * 2.4 * CGFloat(dt)
        position.x += facingRight ? step : -step
        position.x = min(max(position.x, walkableRange.lo), walkableRange.hi)
        if stateElapsed > clipDuration(.pounce) {
            if mouse != nil { pounceResolve() } else { enter(.idle, for: .random(in: 0.6...1.2)) }
        }
    }

    private func tickEat() {
        guard stateElapsed > stateDuration else { return }
        bowlFull = false
        bowlLingering = 1.8
        enter(.happy)
        say("\u{2665}", for: 1.6)
    }

    /// How long the cursor has hovered right over him while he sleeps.
    private var disturbTime: TimeInterval = 0

    private func tickSleep(_ dt: TimeInterval) {
        // A sleeping cat sleeps through your work — distant activity doesn't wake
        // him. But hover the cursor over him for a moment and he stirs, groggy.
        let cursor = debugCursor ?? NSEvent.mouseLocation
        let overHim = abs(cursor.x - position.x) < 95
            && cursor.y >= groundY - 24 && cursor.y - groundY < 190
        disturbTime = overHim ? disturbTime + dt : 0
        if disturbTime > 2.0 { wakeGroggy() }
    }

    private func tickFall(_ dt: TimeInterval) {
        let previousY = position.y
        fallPeakY = max(fallPeakY, position.y)
        velocity.dy -= gravity * CGFloat(dt)
        position.x += velocity.dx * CGFloat(dt)
        position.y += velocity.dy * CGFloat(dt)

        // Keep him over somewhere he can actually land.
        let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.visibleFrame) }
        position.x = min(max(position.x, bounds.minX + 8), bounds.maxX - 8)

        guard velocity.dy <= 0 else { return }      // still on the way up

        // Test the whole span travelled this frame, not just the end point, so a
        // fast fall can't tunnel straight through a narrow ledge.
        if let landed = landing(at: position.x, from: previousY, to: position.y) {
            position.y = landed.y
            perch = landed.isGround ? nil : landed
            touchDown()
        } else if position.y < groundY {
            position.y = groundY
            perch = nil
            touchDown()
        }
    }

    /// Decides how hard the landing was. A short hop is shrugged off; a long drop
    /// gets a squash, and a really long one leaves him sitting seeing stars.
    private func touchDown() {
        let drop = max(0, fallPeakY - position.y)
        if abs(velocity.dx) > 20 { facingRight = velocity.dx >= 0 }
        velocity = .zero
        fallPeakY = position.y
        reachingToy = false

        if dragJerks >= 5 {
            dragJerks = 0
            enter(.angry, for: 2.2)
            say(["hmph", "hey!", "\u{2639}"].randomElement()!, for: 2.2)
            return
        }
        if drop > 520 {
            pendingDizzy = true
            enter(.land, for: clipDuration(.land))
            say("...", for: 2.2)
        } else if drop > 190 {
            enter(.land, for: clipDuration(.land))
        } else {
            enter(.idle, for: .random(in: 1...2.5))
        }
    }

    // MARK: - Transitions

    /// Where an errand is meant to end, so `enter` can tell a genuine arrival from
    /// an interruption.
    private func arrivalState(for errand: Errand) -> PetState {
        switch errand {
        case .meal:             return .eat
        case .mouse:            return .pounce
        case .cursor, .summons: return .sit
        }
    }

    /// True while dinner is either being walked to or eaten.
    private var isDining: Bool { errand == .meal || state == .eat }

    private func enter(_ next: PetState, for duration: TimeInterval = 2.5) {
        guard state != next || next == .idle else { return }

        // Leaving sleep by any path clears the sleep flags.
        if state == .sleep { manualSleep = false; sleepy = false }

        // Anything that isn't part of the current errand abandons it. Without this
        // a stale target lingers and fires the next time he happens to walk.
        if let current = errand, next != .walk, next != arrivalState(for: current) {
            cancelErrand()
            if current == .meal {
                bowl = nil
                bowlLingering = 0
            }
        }
        state = next
        stateElapsed = 0
        stateDuration = duration
        frameIndex = 0
        animElapsed = 0
        onStateChange?(next)
    }

    private func startWalk() {
        facingRight = Bool.random()
        enter(.walk, for: .random(in: 2.5...7))
    }

    // MARK: - Interaction

    func beginDrag() {
        speech = nil
        isHeld = false
        dragJerks = 0
        lastDragPoint = nil
        cancelMeal()
        removeMouse()
        enter(.drag)
    }

    /// System idle time, sampled at most once a second. The underlying IORegistry
    /// lookup is far too heavy to run on every one of the 30 frames per second.
    private var idleSample: TimeInterval = 0
    private var idleSampledAt: CFAbsoluteTime = 0

    func cachedIdleSeconds() -> TimeInterval {
        let now = CFAbsoluteTimeGetCurrent()
        if now - idleSampledAt > 0.75 {
            idleSample = idleSeconds()
            idleSampledAt = now
        }
        return idleSample
    }

    // MARK: - Feeding

    /// Puts a bowl down within reach and sends him over to it.
    func feed() {
        guard state != .drag, bowl == nil else { return }
        wake()
        isHeld = false

        let range = walkableRange
        let reach = min(CGFloat(130), max(0, (range.hi - range.lo) * 0.4))
        let noseGap = CGFloat(lib.frameWidth) * CGFloat(settings.scale) * 0.30

        // Prefer putting it ahead of him, but flip if that would run off the end of
        // whatever he's standing on — the screen floor or a window ledge.
        var direction: CGFloat = facingRight ? 1 : -1
        let ahead = position.x + direction * reach
        if ahead > range.hi || ahead < range.lo { direction = -direction }
        let standX = min(max(position.x + direction * reach, range.lo), range.hi)

        // The bowl sits on the same surface, never past its edge.
        bowl = CGPoint(x: min(max(standX + direction * noseGap, range.lo), range.hi),
                       y: supportY)
        bowlKind = lib.bowlKinds.randomElement() ?? "kibble"
        bowlFull = true
        bowlLingering = 0
        facingRight = standX >= position.x
        walkTarget = standX
        errand = .meal
        errandElapsed = 0
        enter(.walk, for: 30)       // arrival ends it, not the clock
    }

    private func cancelMeal() {
        bowl = nil
        bowlLingering = 0
        cancelErrand()
    }

    // MARK: - Holding still

    func hold() {
        // Opening the task list shouldn't drag him off his dinner. `walkTarget`
        // covers the walk over; `isDining` covers the eating itself.
        guard state != .drag, state != .fall, walkTarget == nil, !isDining else { return }
        isHeld = true
        enter(.sit, for: .infinity)
    }

    func release() {
        guard isHeld else { return }
        isHeld = false
        enter(.idle, for: .random(in: 1...2.5))
    }

    private var lastDragPoint: CGPoint?

    func dragTo(_ point: CGPoint) {
        guard state == .drag else { return }
        if let last = lastDragPoint, hypot(point.x - last.x, point.y - last.y) > 55 {
            dragJerks += 1
        }
        lastDragPoint = point
        let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        position = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                           y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// Where the bubble and popover should point, relative to his feet.
    func endDrag(throwVelocity: CGVector) {
        guard state == .drag else { return }
        // Always fall: the landing code decides whether that's the floor or the
        // window he was dropped over.
        perch = nil
        velocity = CGVector(dx: max(-420, min(420, throwVelocity.dx)), dy: 0)
        fallPeakY = position.y
        enter(.fall, for: 6)
    }

    private var recentPets = 0
    private var lastPetAt: CFAbsoluteTime = 0

    /// A click on the cat that wasn't a drag. Repeated affection warms him up:
    /// a wave, then hearts, then a full purr.
    func pet() {
        if angryMood {                              // a pet calms him instantly
            angryMood = false
            angryTimeLeft = 0
            enter(.love, for: 1.8)
            say("\u{2665}", for: 1.8)
            recentPets = 1
            lastPetAt = CFAbsoluteTimeGetCurrent()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        recentPets = (now - lastPetAt < 4) ? recentPets + 1 : 1
        lastPetAt = now

        guard !isDining else {
            say("\u{2665}", for: 1.4)
            return
        }
        if recentPets >= 4 {
            enter(.purr, for: 2.4)
            say("purrrr", for: 2.4)
        } else if recentPets >= 2 {
            enter(.love, for: 1.8)
        } else {
            enter(.happy)
            say(["mrrp", "mrow", "\u{2665}"].randomElement()!, for: 1.6)
        }
    }

    /// Yanking him around quickly makes him cross.
    private var dragJerks = 0

    /// The happy animation plus a message, triggered by something other than a click.
    ///
    /// Clearing your last task posts both "a task was completed" and "everything is
    /// done" at once. The first sends him off to a bowl; this must not cancel that,
    /// or he never eats — the meal ends in the same happy hop anyway.
    func celebrate(_ text: String) {
        if !isDining { enter(.happy) }
        say(text, for: 3)
    }

    func say(_ text: String, for duration: TimeInterval = 4) {
        if text != speech { speechStartedAt = CFAbsoluteTimeGetCurrent() }
        speech = text
        speechRemaining = duration
    }

    /// Set when the user asked him to sleep (menu / Sleep Now), so the idle-based
    /// wake in tickSleep leaves him be until he's actually disturbed.
    private var manualSleep = false

    func forceSleep() {
        manualSleep = true
        enter(.sleep, for: .infinity)
    }

    func wake() {
        sleepy = false
        guard state == .sleep else { return }
        // Nobody gets up without stretching first.
        enter(.stretch, for: clipDuration(.stretch))
    }

    /// Woken by being pestered: a groggy yawn rather than a bright stretch. He's
    /// slower and grumpier about it, and at night he may just doze straight off
    /// again once you leave him alone.
    private func wakeGroggy() {
        disturbTime = 0
        sleepy = false          // this yawn ends in sitting up, not going back under
        manualSleep = false
        enter(.yawn, for: clipDuration(.yawn))
        say(["mrf", "...", "hnn"].randomElement()!, for: 2.5)
    }

    func sitNow() { enter(.sit, for: .random(in: 6...12)) }

    private var stargazedThisNight = false

    /// A rare, special night moment. On the stroke of midnight a black cat can't
    /// help but look up — or, once in a while any other night hour, a shooting
    /// star catches his eye. At most once a night, and never mid-task.
    func considerSpecial(hour: Int, atKeyboard: Bool) {
        if hour == 12 { stargazedThisNight = false }        // reset the nightly lock by day
        guard atKeyboard, state == .idle || state == .sit, !stargazedThisNight else { return }
        let isNight = hour >= 20 || hour <= 4
        guard isNight else { return }

        let atMidnight = (hour == 0)
        guard atMidnight || Int.random(in: 0..<40) == 0 else { return }   // rare outside midnight
        stargazedThisNight = true
        wake()
        enter(.stargaze, for: clipDuration(.stargaze) + 2.0)
        say(["make a wish", "\u{2727}", "\u{2606}"].randomElement()!, for: 4)
    }

    /// Time-of-day moment. Called about once a minute; fires at most once per hour
    /// slot and only when he's idle so it never interrupts anything.
    func considerTimeOfDay(hour: Int, atKeyboard: Bool) {
        guard atKeyboard, state == .idle || state == .sit else { return }
        guard hour != lastGreetedHour else { return }

        let line: String?
        switch hour {
        case 6, 7, 8:    line = ["good morning", "morning \u{2600}", "breakfast?"].randomElement()
        case 12, 13:     line = ["lunch time", "hungry yet?"].randomElement()
        case 0, 1, 2, 3: line = ["it's late", "sleep soon?", "still up?"].randomElement()
        case 22, 23:     line = ["getting late", "long day"].randomElement()
        default:         line = nil
        }
        guard let line else { return }
        lastGreetedHour = hour
        wake()
        enter(.sit, for: 5)
        say(line, for: 6)
    }

    /// Called by the controller when the sleep-after-idle threshold is crossed.
    func considerSleeping() {
        guard state != .drag, state != .fall, state != .sleep,
              state != .yawn, mouse == nil, bowl == nil, !isHeld else { return }
        // Time of day sets how easily he nods off: sleepy at night, stubborn by
        // day. Even the daytime threshold is finite, so being ignored long enough
        // still puts him under.
        let threshold = TimeInterval(settings.sleepMinutes * 60) * sleepinessMultiplier()
        guard cachedIdleSeconds() >= threshold else { return }
        sleepy = true
        enter(.yawn, for: clipDuration(.yawn))
    }

    /// How the current hour scales the nap threshold. <1 = drops off sooner.
    private var cachedHour = -1
    private var hourSampledAt: CFAbsoluteTime = 0
    private func sleepinessMultiplier() -> Double {
        let now = CFAbsoluteTimeGetCurrent()
        if cachedHour < 0 || now - hourSampledAt > 30 {
            cachedHour = Calendar.current.component(.hour, from: Date())
            hourSampledAt = now
        }
        switch cachedHour {
        case 23, 0, 1, 2, 3, 4:  return 0.30    // deep night — sleepy easily
        case 21, 22, 5:          return 0.55    // late evening / early morning
        case 9, 10, 11, 14, 15, 16: return 1.7  // working hours — hard to sleep
        default:                 return 1.0
        }
    }

    /// Testing hook: places a toy either on the floor (reachable) or very high
    /// (unreachable, to drive frustration). Optionally pets him after a delay.
    func debugPlaceToy(reachable: Bool) {
        if reachable {
            placeToy(at: CGPoint(x: position.x + 160, y: groundY), kind: "ball")
        } else {
            placeToy(at: CGPoint(x: position.x, y: groundY + 1400), kind: "feather")
        }
    }
    func debugPetNow() { pet() }
    /// Drops a toy from high in mid-air; logs its falling y each tick.
    func debugDropToyHigh() { placeToy(at: CGPoint(x: position.x + 60, y: groundY + 600), kind: "ball") }
    var debugToyY: Int { Int(mouse?.y ?? -1) }
    var debugToyFalling: Bool { toyFalling }

    /// Testing hook: puts him to sleep, then parks the synthetic cursor over him
    /// so the disturbance-wake can be verified without a real hand on the mouse.
    func debugSleepDisturb() {
        forceSleep()
        debugCursor = CGPoint(x: position.x, y: groundY + 40)
    }

    /// Testing hook: drops him just short of a screen edge and walks him into it,
    /// so the turn-around geometry can be checked without waiting for him to
    /// wander there on his own.
    func debugPatrolEdge(rightward: Bool) {
        let f = currentScreen.visibleFrame
        cancelMeal()
        isHeld = false
        perch = nil
        position.x = rightward ? f.maxX - edgeMargin - 150 : f.minX + edgeMargin + 150
        position.y = f.minY
        facingRight = rightward
        enter(.walk, for: 60)
    }

    /// Testing hook: drops the mouse up on a window ledge so the vertical chase
    /// (cat jumps up, hunts on the ledge) can be verified without waiting for the
    /// mouse to corner itself there by chance.
    func debugMouseOnLedge() -> String {
        settings.perchOnWindows = true
        surfaces.refresh()
        let reachable = surfaces.surfaces
            .filter { $0.y > groundY + 30 && $0.y < groundY + 360 && $0.width > 120 }
            .min { ($0.y - groundY) < ($1.y - groundY) }
        guard let ledge = reachable else {
            let lowest = surfaces.surfaces.map { Int($0.y - groundY) }.min() ?? -1
            return "no reachable low ledge (lowest window top is \(lowest)px up; a leap reaches ~400)"
        }
        // put the cat under the ledge and a toy up on it
        position = CGPoint(x: (ledge.minX + ledge.maxX) / 2, y: groundY)
        perch = nil
        placeToy(at: CGPoint(x: position.x, y: ledge.y), kind: "mouse")
        return "ledge top=\(Int(ledge.y)) floor=\(Int(groundY)) gap=\(Int(ledge.y - groundY)) reachable=\(toyReachable)"
    }

    /// Testing hook: parks a synthetic cursor right beside him and reports whether
    /// he goes clingy (rub/love) within a couple of seconds.
    func debugClingy() {
        settings.clingyEnabled = true
        settings.companionMode = "roam"
        debugCursor = CGPoint(x: position.x + 20, y: position.y + 60)
    }

    /// Testing hook: pets him repeatedly to walk the love/purr escalation, then
    /// feeds four times to show the food rotates.
    func debugEmotions() {
        var delay = 0.4
        for _ in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.pet() }
            delay += 0.6
        }
        for _ in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.cancelMeal()
                self.bowlKind = self.lib.bowlKinds.randomElement() ?? "kibble"
                NSLog("food -> \(self.bowlKind)")
            }
            delay += 0.5
        }
    }

    /// Testing hook: cycles through every one-shot animation so each can be seen
    /// and timed. Prints nothing; watch --trace output.
    func debugCycleAnimations() {
        let seq: [(PetState, TimeInterval)] = [
            (.stretch, 1.4), (.yawn, 1.6), (.scratch, 2.4), (.loaf, 2.4),
            (.wiggle, 1.6), (.run, 3.0), (.dizzy, 2.6),
        ]
        var delay = 0.4
        for (st, dur) in seq {
            let capturedState = st, capturedDur = dur
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.isHeld = false
                self?.cancelMeal()
                if capturedState == .run { self?.runLaps = 3; self?.facingRight = true }
                self?.forceState(capturedState, for: capturedDur)
            }
            delay += dur + 0.6
        }
    }

    /// Testing back door into the private state machine.
    func forceState(_ next: PetState, for duration: TimeInterval) {
        enter(next, for: duration)
    }

    /// Testing hook: turns perching on, drops him over the widest window on screen,
    /// and reports what it found. Dragging him onto a window is the main way up —
    /// most title bars sit far higher than he can jump.
    func debugDropOntoWindow() -> String {
        settings.perchOnWindows = true
        surfaces.refresh()
        guard let target = surfaces.surfaces.max(by: { $0.width < $1.width }) else {
            return "no window ledges found"
        }
        cancelMeal()
        isHeld = false
        position.x = (target.minX + target.maxX) / 2
        position.y = target.y + 120
        startFalling(dx: 0)
        return "ledges=\(surfaces.surfaces.count) target x=\(Int(target.minX))...\(Int(target.maxX)) "
            + "top=\(Int(target.y)) droppedFrom=\(Int(position.y))"
    }

    /// Brings him to the cursor — used by the menu and by break reminders.
    ///
    /// He walks if the cursor is on the screen he's already standing on. Across
    /// displays there's no walkable path, so he steps over directly.
    func comeHere() {
        wake()
        isHeld = false
        cancelMeal()

        let mouse = NSEvent.mouseLocation
        let destination = NSScreen.screens.first { $0.frame.contains(mouse) } ?? currentScreen

        // Called down from a window ledge — he comes to you on the floor.
        if perch != nil {
            perch = nil
            position.y = groundY
        }

        if destination == currentScreen {
            let target = clampToWalkable(mouse.x, on: destination)
            if abs(target - position.x) > 30 {
                facingRight = target > position.x
                walkTarget = target
                errand = .summons
                errandElapsed = 0
                enter(.walk, for: 30)
                return
            }
            enter(.sit, for: 8)
            return
        }

        position = CGPoint(x: clampToWalkable(mouse.x, on: destination),
                           y: destination.visibleFrame.minY)
        facingRight = mouse.x >= position.x
        enter(.sit, for: 8)
    }

    var currentFrame: SpriteFrame {
        let clip = lib.clip(state)
        return clip.frames[min(frameIndex, clip.frames.count - 1)]
    }
}

/// Seconds since the last keyboard or mouse event, straight from the HID system.
/// Needs no accessibility permission, unlike the event-tap based approaches.
func idleSeconds() -> TimeInterval {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                       IOServiceMatching("IOHIDSystem"),
                                       &iterator) == KERN_SUCCESS else { return 0 }
    defer { IOObjectRelease(iterator) }

    let entry = IOIteratorNext(iterator)
    guard entry != 0 else { return 0 }
    defer { IOObjectRelease(entry) }

    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = properties?.takeRetainedValue() as? [String: Any],
          let nanos = dict["HIDIdleTime"] as? Int64
    else { return 0 }
    return TimeInterval(nanos) / 1_000_000_000
}
