import Foundation
import ServiceManagement

/// UserDefaults-backed preferences. Every setter posts `Settings.didChange`, which
/// the controller and menu bar observe, so nothing has to poll.
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("PetSettingsDidChange")

    private enum K {
        static let name = "petName"
        static let scale = "spriteScale"
        static let speed = "walkSpeed"
        static let sound = "soundEnabled"
        static let volume = "soundVolume"
        static let breakMinutes = "breakReminderMinutes"
        static let sleepMinutes = "sleepAfterIdleMinutes"
        static let hidden = "petHidden"
        static let onboarded = "hasOnboarded"
        static let hideFromCapture = "hideFromScreenCapture"
        static let eyeColor = "eyeColorHex"
        static let innerEarColor = "innerEarColorHex"
        static let quickAdd = "quickAddHotKeyEnabled"
        static let perch = "perchOnWindows"
        static let companionMode = "companionMode"
        static let antics = "anticsEnabled"
        static let greetings = "greetingsEnabled"
        static let clingy = "clingyEnabled"
        static let collarStyle = "collarStyle"
        static let collarColor = "collarColorHex"
        static let bellColor = "bellColorHex"
        static let selectedToy = "selectedToy"
        static let jumpHeight = "jumpHeight"
    }

    /// Shipped defaults. The sprite PNGs carry placeholder key colours that the app
    /// remaps at load, so these are the values actually seen on screen.
    enum DefaultColor {
        static let eye = "#DEC64E"        // amber, matching the photos
        static let innerEar = "#3E2F31"   // dark warm grey; a black cat's ears aren't pink
        static let collar = "#2E2840"     // the band's own subtle key colour
        static let bell = "#CEB058"       // gold
    }

    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            K.name: "Momo",
            K.scale: 3,
            K.speed: 1.0,
            K.sound: true,
            K.volume: 0.6,
            K.breakMinutes: 0,          // 0 = reminders off
            K.sleepMinutes: 5,
            K.hidden: false,
            K.onboarded: false,
            K.hideFromCapture: false,
            K.eyeColor: DefaultColor.eye,
            K.innerEarColor: DefaultColor.innerEar,
            K.quickAdd: true,
            K.perch: false,
            K.companionMode: "roam",
            K.antics: true,
            K.greetings: true,
            K.clingy: true,
            K.collarStyle: "bell",
            K.collarColor: DefaultColor.collar,
            K.bellColor: DefaultColor.bell,
            K.selectedToy: "mouse",
            K.jumpHeight: 1.0,
        ])
    }

    private func changed() {
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    var name: String {
        get { (d.string(forKey: K.name) ?? "Momo").trimmingCharacters(in: .whitespaces) }
        set { d.set(newValue.isEmpty ? "Momo" : newValue, forKey: K.name); changed() }
    }

    /// Points per sprite pixel. Kept integral so the pixel art never resamples.
    var scale: Int {
        get { min(5, max(2, d.integer(forKey: K.scale))) }
        set { d.set(newValue, forKey: K.scale); changed() }
    }

    var speed: Double {
        get { min(2.5, max(0.3, d.double(forKey: K.speed))) }
        set { d.set(newValue, forKey: K.speed); changed() }
    }

    var soundEnabled: Bool {
        get { d.bool(forKey: K.sound) }
        set { d.set(newValue, forKey: K.sound); changed() }
    }

    /// Master volume, 0...1, applied on top of each cue's own balance.
    var volume: Double {
        get { min(1.0, max(0.0, d.double(forKey: K.volume))) }
        set { d.set(newValue, forKey: K.volume); changed() }
    }

    var breakMinutes: Int {
        get { d.integer(forKey: K.breakMinutes) }
        set { d.set(newValue, forKey: K.breakMinutes); changed() }
    }

    var sleepMinutes: Int {
        get { max(1, d.integer(forKey: K.sleepMinutes)) }
        set { d.set(newValue, forKey: K.sleepMinutes); changed() }
    }

    var hidden: Bool {
        get { d.bool(forKey: K.hidden) }
        set { d.set(newValue, forKey: K.hidden); changed() }
    }

    var hasOnboarded: Bool {
        get { d.bool(forKey: K.onboarded) }
        set { d.set(newValue, forKey: K.onboarded) }
    }

    var hideFromCapture: Bool {
        get { d.bool(forKey: K.hideFromCapture) }
        set { d.set(newValue, forKey: K.hideFromCapture); changed() }
    }

    /// Posted on its own so the hot key can be registered or torn down without
    /// touching anything else.
    static let quickAddChanged = Notification.Name("PetQuickAddChanged")

    var quickAddEnabled: Bool {
        get { d.bool(forKey: K.quickAdd) }
        set {
            d.set(newValue, forKey: K.quickAdd)
            NotificationCenter.default.post(name: Settings.quickAddChanged, object: nil)
            changed()
        }
    }

    /// Lets him stand and walk on the top edges of other apps' windows.
    var perchOnWindows: Bool {
        get { d.bool(forKey: K.perch) }
        set { d.set(newValue, forKey: K.perch); changed() }
    }

    /// roam | followCursor | followWindow | rest
    var companionMode: String {
        get { d.string(forKey: K.companionMode) ?? "roam" }
        set { d.set(newValue, forKey: K.companionMode); changed() }
    }

    /// The occasional flourishes — zoomies, flops, stretches. Off keeps him calm.
    var anticsEnabled: Bool {
        get { d.bool(forKey: K.antics) }
        set { d.set(newValue, forKey: K.antics); changed() }
    }

    var greetingsEnabled: Bool {
        get { d.bool(forKey: K.greetings) }
        set { d.set(newValue, forKey: K.greetings); changed() }
    }

    /// Fusses over the cursor when it comes near. Roam mode only.
    var clingyEnabled: Bool {
        get { d.bool(forKey: K.clingy) }
        set { d.set(newValue, forKey: K.clingy); changed() }
    }

    // MARK: - Colours

    /// Posted separately from `didChange` so the sprite sheets are only rebuilt
    /// when a colour actually moved.
    static let paletteChanged = Notification.Name("PetPaletteChanged")

    var eyeColorHex: String {
        get { d.string(forKey: K.eyeColor) ?? DefaultColor.eye }
        set {
            d.set(newValue, forKey: K.eyeColor)
            NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
            changed()
        }
    }

    var innerEarColorHex: String {
        get { d.string(forKey: K.innerEarColor) ?? DefaultColor.innerEar }
        set {
            d.set(newValue, forKey: K.innerEarColor)
            NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
            changed()
        }
    }

    /// mouse | ball | feather — the toy dropped by the toy control.
    var selectedToy: String {
        get { d.string(forKey: K.selectedToy) ?? "mouse" }
        set { d.set(newValue, forKey: K.selectedToy); changed() }
    }

    /// How high he can leap, 0.5...2.0 (1.0 = default).
    var jumpHeight: Double {
        get { let v = d.double(forKey: K.jumpHeight); return v == 0 ? 1.0 : min(2.0, max(0.5, v)) }
        set { d.set(newValue, forKey: K.jumpHeight); changed() }
    }

    /// none | band | bell | bowtie | bandana — swaps the sprite sheets.
    var collarStyle: String {
        get { d.string(forKey: K.collarStyle) ?? "bell" }
        set {
            d.set(newValue, forKey: K.collarStyle)
            NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
            changed()
        }
    }

    var collarColorHex: String {
        get { d.string(forKey: K.collarColor) ?? DefaultColor.collar }
        set {
            d.set(newValue, forKey: K.collarColor)
            NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
            changed()
        }
    }

    var bellColorHex: String {
        get { d.string(forKey: K.bellColor) ?? DefaultColor.bell }
        set {
            d.set(newValue, forKey: K.bellColor)
            NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
            changed()
        }
    }

    func resetColors() {
        d.set(DefaultColor.eye, forKey: K.eyeColor)
        d.set(DefaultColor.innerEar, forKey: K.innerEarColor)
        d.set(DefaultColor.collar, forKey: K.collarColor)
        d.set(DefaultColor.bell, forKey: K.bellColor)
        NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
        changed()
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("launch at login failed: \(error.localizedDescription)")
            }
            changed()
        }
    }
}
