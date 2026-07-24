import SwiftUI

/// The actions the control panel can perform, injected by the controller so the
/// view stays free of app plumbing.
struct PetControlActions {
    var comeHere: () -> Void
    var feed: () -> Void
    var dropMouse: () -> Void
    var sit: () -> Void
    var sleep: () -> Void
    var hide: () -> Void
    var openTasks: () -> Void
    var openSettings: () -> Void
    var openAbout: () -> Void
    var close: () -> Void
}

/// The panel that appears when you right-click the cat — a small, organised
/// control centre: what he should do right now, how he behaves, and links to the
/// full windows. Replaces the old right-click menu.
struct PetControlPanel: View {
    let actions: PetControlActions

    private let settings = Settings.shared
    @State private var name = Settings.shared.name
    @State private var mode = Settings.shared.companionMode
    @State private var climb = Settings.shared.perchOnWindows
    @State private var clingy = Settings.shared.clingyEnabled
    @State private var sound = Settings.shared.soundEnabled
    @State private var openTaskCount = TaskStore.shared.openCount

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            actionsSection
            Divider()
            modeSection
            Divider()
            togglesSection
            Divider()
            footer
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            CatPreview()
                .frame(width: 52, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(modeLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Quick actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Do")
            HStack(spacing: 8) {
                actionButton("Come here", "hand.wave") { actions.comeHere(); actions.close() }
                actionButton("Feed", "fork.knife") { actions.feed(); actions.close() }
                actionButton("Toy mouse", "cursorarrow.motionlines") { actions.dropMouse(); actions.close() }
            }
            HStack(spacing: 8) {
                actionButton("Sit", "figure.seated.side") { actions.sit(); actions.close() }
                actionButton("Sleep", "moon.zzz") { actions.sleep(); actions.close() }
                actionButton("Hide", "eye.slash") { actions.hide(); actions.close() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func actionButton(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Mode")
            Picker("", selection: $mode) {
                Text("Roam").tag("roam")
                Text("Cursor").tag("followCursor")
                Text("Window").tag("followWindow")
                Text("Rest").tag("rest")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, v in settings.companionMode = v }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        VStack(spacing: 2) {
            compactToggle("Climb on windows", "macwindow", $climb) { settings.perchOnWindows = $0 }
            compactToggle("Clingy to cursor", "cursorarrow.rays", $clingy) { settings.clingyEnabled = $0 }
            compactToggle("Sound", "speaker.wave.2", $sound) { settings.soundEnabled = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func compactToggle(_ title: String, _ symbol: String,
                               _ binding: Binding<Bool>, _ apply: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: binding) {
            Label(title, systemImage: symbol).font(.system(size: 12))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .onChange(of: binding.wrappedValue) { _, v in apply(v) }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            footerButton(openTaskCount > 0 ? "Tasks (\(openTaskCount))" : "Tasks", "checklist") {
                actions.openTasks(); actions.close()
            }
            Divider().frame(height: 24)
            footerButton("Settings", "gearshape") { actions.openSettings(); actions.close() }
            Divider().frame(height: 24)
            footerButton("About", "info.circle") { actions.openAbout(); actions.close() }
        }
        .padding(.vertical, 4)
    }

    private func footerButton(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(title).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.6)
    }

    private var modeLabel: String {
        switch mode {
        case "followCursor": return "Following your cursor"
        case "followWindow": return "Following your window"
        case "rest":         return "Resting"
        default:             return "Free to roam"
        }
    }
}
