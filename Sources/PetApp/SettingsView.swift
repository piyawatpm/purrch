import AppKit
import SwiftUI

/// The settings window. A tabbed layout — Look / Behaviour / Company / System —
/// with a live preview of the cat on the Look tab so palette and collar choices
/// are visible as they're made. Every control writes straight to `Settings`,
/// which the running pet observes.
struct SettingsView: View {
    let onBreakChange: () -> Void

    var body: some View {
        TabView {
            LookTab()
                .tabItem { Label("Look", systemImage: "paintpalette") }
            BehaviourTab(onBreakChange: onBreakChange)
                .tabItem { Label("Behaviour", systemImage: "sparkles") }
            CompanyTab()
                .tabItem { Label("Company", systemImage: "cursorarrow.rays") }
            SystemTab()
                .tabItem { Label("System", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 580)
    }
}

// MARK: - Look

private struct LookTab: View {
    private let settings = Settings.shared

    @State private var scale = Settings.shared.scale
    @State private var eyeColor = Color(hex: Settings.shared.eyeColorHex)
    @State private var earColor = Color(hex: Settings.shared.innerEarColorHex)
    @State private var collarStyle = Settings.shared.collarStyle
    @State private var collarColor = Color(hex: Settings.shared.collarColorHex)
    @State private var bellColor = Color(hex: Settings.shared.bellColorHex)

    var body: some View {
        Form {
            Section {
                CatPreview()
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
            }

            Section("Size") {
                Picker("Size", selection: $scale) {
                    Text("Small").tag(2); Text("Medium").tag(3)
                    Text("Large").tag(4); Text("Huge").tag(5)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: scale) { _, v in settings.scale = v }
            }

            Section("Colours") {
                ColorPicker("Eyes", selection: $eyeColor, supportsOpacity: false)
                    .onChange(of: eyeColor) { _, v in settings.eyeColorHex = v.hexString }
                ColorPicker("Inner ears", selection: $earColor, supportsOpacity: false)
                    .onChange(of: earColor) { _, v in settings.innerEarColorHex = v.hexString }
            }

            Section("Collar") {
                Picker("Style", selection: $collarStyle) {
                    Text("None").tag("none"); Text("Band").tag("band")
                    Text("Bell").tag("bell"); Text("Bow tie").tag("bowtie")
                    Text("Bandana").tag("bandana")
                }
                .onChange(of: collarStyle) { _, v in settings.collarStyle = v }

                if collarStyle != "none" {
                    ColorPicker("Collar colour", selection: $collarColor, supportsOpacity: false)
                        .onChange(of: collarColor) { _, v in settings.collarColorHex = v.hexString }
                }
                if collarStyle == "bell" || collarStyle == "bowtie" {
                    ColorPicker("Bell colour", selection: $bellColor, supportsOpacity: false)
                        .onChange(of: bellColor) { _, v in settings.bellColorHex = v.hexString }
                }
            }

            Section {
                Button("Reset colours to default") {
                    settings.resetColors()
                    eyeColor = Color(hex: settings.eyeColorHex)
                    earColor = Color(hex: settings.innerEarColorHex)
                    collarColor = Color(hex: settings.collarColorHex)
                    bellColor = Color(hex: settings.bellColorHex)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behaviour

private struct BehaviourTab: View {
    let onBreakChange: () -> Void
    private let settings = Settings.shared

    @State private var speed = Settings.shared.speed
    @State private var jumpHeight = Settings.shared.jumpHeight
    @State private var antics = Settings.shared.anticsEnabled
    @State private var clingy = Settings.shared.clingyEnabled
    @State private var greetings = Settings.shared.greetingsEnabled
    @State private var napMinutes = Settings.shared.sleepMinutes
    @State private var breakMinutes = Settings.shared.breakMinutes
    @State private var sound = Settings.shared.soundEnabled
    @State private var volume = Settings.shared.volume

    var body: some View {
        Form {
            Section("Movement") {
                HStack {
                    Text("Speed")
                    Slider(value: $speed, in: 0.3...2.4)
                        .onChange(of: speed) { _, v in settings.speed = v }
                    Text(speedLabel).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                HStack {
                    Text("Jump height")
                    Slider(value: $jumpHeight, in: 0.5...2.0)
                        .onChange(of: jumpHeight) { _, v in settings.jumpHeight = v }
                    Text(jumpLabel).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Section {
                Toggle(isOn: $antics) {
                    Text("Playful antics")
                    Text("Zoomies, flops, stretches, and other occasional flourishes.")
                }
                .onChange(of: antics) { _, v in settings.anticsEnabled = v }

                Toggle(isOn: $clingy) {
                    Text("Clingy")
                    Text("Fusses over your cursor when it comes near (Free Roam only).")
                }
                .onChange(of: clingy) { _, v in settings.clingyEnabled = v }

                Toggle(isOn: $greetings) {
                    Text("Time-of-day hellos")
                    Text("A quiet greeting at morning, lunch, and late night.")
                }
                .onChange(of: greetings) { _, v in settings.greetingsEnabled = v }
            }

            Section("Rest & reminders") {
                Picker("Nap after", selection: $napMinutes) {
                    Text("1 minute").tag(1); Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15); Text("30 minutes").tag(30)
                }
                .onChange(of: napMinutes) { _, v in settings.sleepMinutes = v }

                Picker("Break reminders", selection: $breakMinutes) {
                    Text("Off").tag(0); Text("Every 20 min").tag(20)
                    Text("Every 30 min").tag(30); Text("Every 60 min").tag(60)
                }
                .onChange(of: breakMinutes) { _, v in
                    settings.breakMinutes = v
                    onBreakChange()
                }
            }

            Section("Sound") {
                Toggle("Sound", isOn: $sound)
                    .onChange(of: sound) { _, v in settings.soundEnabled = v }
                HStack {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1)
                        .onChange(of: volume) { _, v in settings.volume = v }
                    Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(volume * 100))%").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .disabled(!sound)
                .opacity(sound ? 1 : 0.45)
            }
        }
        .formStyle(.grouped)
    }

    private var jumpLabel: String {
        switch jumpHeight {
        case ..<0.8: return "low"
        case ..<1.3: return "normal"
        case ..<1.7: return "high"
        default:     return "super"
        }
    }

    private var speedLabel: String {
        switch speed {
        case ..<0.7: return "slow"
        case ..<1.3: return "normal"
        case ..<1.9: return "brisk"
        default:     return "zoomies"
        }
    }
}

// MARK: - Company

private struct CompanyTab: View {
    private let settings = Settings.shared

    @State private var name = Settings.shared.name
    @State private var mode = Settings.shared.companionMode
    @State private var perch = Settings.shared.perchOnWindows

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onChange(of: name) { _, v in settings.name = v }
            } header: {
                Text("His name")
            } footer: {
                Text("Shown in the menu bar and the About window.")
            }

            Section {
                Picker("Mode", selection: $mode) {
                    Text("Free roam").tag("roam")
                    Text("Follow cursor").tag("followCursor")
                    Text("Follow active window").tag("followWindow")
                    Text("Rest in place").tag("rest")
                }
                .pickerStyle(.inline)
                .onChange(of: mode) { _, v in settings.companionMode = v }
            } header: {
                Text("Mode")
            } footer: {
                Text(modeBlurb)
            }

            Section {
                Toggle(isOn: $perch) {
                    Text("Climb on windows")
                    Text("He perches on window title bars, not just the desktop floor.")
                }
                .onChange(of: perch) { _, v in settings.perchOnWindows = v }
            }
        }
        .formStyle(.grouped)
    }

    private var modeBlurb: String {
        switch mode {
        case "followCursor": return "He trots after your pointer and sits nearby."
        case "followWindow": return "He moves to whatever window you're working in, and climbs onto it if \u{201C}climb on windows\u{201D} is on."
        case "rest":         return "He settles down and stays put — no wandering or zoomies."
        default:             return "He wanders, explores, and does his own thing."
        }
    }
}

// MARK: - System

private struct SystemTab: View {
    private let settings = Settings.shared

    @State private var launchAtLogin = Settings.shared.launchAtLogin
    @State private var hideFromCapture = Settings.shared.hideFromCapture
    @State private var quickAdd = Settings.shared.quickAddEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        settings.launchAtLogin = v
                        launchAtLogin = settings.launchAtLogin   // reflect what the system allowed
                    }

                Toggle(isOn: $hideFromCapture) {
                    Text("Hide from screen recording")
                    Text("Keeps him out of screenshots and screen shares.")
                }
                .onChange(of: hideFromCapture) { _, v in settings.hideFromCapture = v }
            }

            Section {
                Toggle(isOn: $quickAdd) {
                    HStack(spacing: 6) {
                        Text("Quick-add shortcut")
                        Text(GlobalHotKey.quickAddDescription)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text("Bring up today's task list from any app.")
                }
                .onChange(of: quickAdd) { _, v in settings.quickAddEnabled = v }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Colour bridging

extension Color {
    init(hex: String) {
        let rgb = RGB(hex: hex) ?? RGB(hex: Settings.DefaultColor.eye)!
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255,
                  blue: Double(rgb.b) / 255, opacity: 1)
    }

    /// Round-trips through sRGB so the stored hex is stable whatever colour space
    /// the picker hands back.
    var hexString: String {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return Settings.DefaultColor.eye }
        return RGB(UInt8((srgb.redComponent * 255).rounded()),
                   UInt8((srgb.greenComponent * 255).rounded()),
                   UInt8((srgb.blueComponent * 255).rounded())).hex
    }
}
