import SwiftUI

struct TasksView: View {
    @ObservedObject private var store = TaskStore.shared
    @State private var mode: Mode = .today
    @State private var draft = ""
    @State private var historyDay = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

    // Inline rename
    @State private var editingID: UUID?
    @State private var editingText = ""
    @FocusState private var titleFocused: Bool

    // Group name prompt (shared by "new group" and "rename group")
    private enum GroupPrompt { case newFor(TodoItem), rename(String) }
    @State private var groupPrompt: GroupPrompt?
    @State private var groupPromptText = ""
    @State private var showGroupPrompt = false

    private enum Mode: String, CaseIterable { case today = "Today", history = "History" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Divider()

            switch mode {
            case .today:   todayPane
            case .history: historyPane
            }
        }
        .frame(minWidth: 420, minHeight: 460)
        .alert(promptTitle, isPresented: $showGroupPrompt) {
            TextField("Group name", text: $groupPromptText)
            Button(promptButton) { applyGroupPrompt() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give the group a short name — tasks filed under it are shown together.")
        }
    }

    // MARK: - Today

    private var todayPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
                TextField("What needs doing today?", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        store.add(draft)
                        draft = ""
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            let open = store.today.filter { !$0.isDone }
            let done = store.doneToday

            if open.isEmpty && done.isEmpty {
                empty("Nothing on the list.", "Add something above and it stays until it's done.")
            } else {
                List {
                    ForEach(sections(open)) { section in
                        Section {
                            ForEach(section.items) { row($0) }
                        } header: {
                            groupHeader(section.name, count: section.items.count)
                        }
                    }
                    if !done.isEmpty {
                        Section {
                            ForEach(done) { row($0) }
                        } header: {
                            Text("Done today").font(.caption)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // Ungrouped tasks first, then each named group alphabetically.
    private struct GroupSection: Identifiable {
        let name: String?
        let items: [TodoItem]
        var id: String { name ?? "\u{1}ungrouped" }
    }

    private func sections(_ open: [TodoItem]) -> [GroupSection] {
        var result: [GroupSection] = []
        let ungrouped = open.filter { ($0.group ?? "").isEmpty }
        if !ungrouped.isEmpty { result.append(GroupSection(name: nil, items: ungrouped)) }
        for name in store.groupNames {
            let items = open.filter { $0.group == name }
            if !items.isEmpty { result.append(GroupSection(name: name, items: items)) }
        }
        return result
    }

    private func groupHeader(_ name: String?, count: Int) -> some View {
        HStack(spacing: 6) {
            if let name {
                Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(name).font(.caption).fontWeight(.semibold)
            } else {
                Text("To do").font(.caption)
            }
            Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            if let name {
                Menu {
                    Button("Rename group…") { promptRename(name) }
                    Button("Ungroup these") { store.deleteGroup(name) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    // MARK: - History

    private var historyPane: some View {
        VStack(spacing: 0) {
            HStack {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                VStack(spacing: 1) {
                    Text(dayLabel(historyDay)).font(.system(size: 13, weight: .semibold))
                    Text(historyDay, format: .dateTime.day().month(.wide).year())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(Calendar.current.isDateInToday(historyDay))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            let finished = store.completed(on: historyDay)
            let added = store.added(on: historyDay)
            let carriedOut = added.filter { !$0.isDone }

            if finished.isEmpty && added.isEmpty {
                empty("Nothing recorded.", "No tasks were added or finished that day.")
            } else {
                List {
                    Section {
                        if finished.isEmpty {
                            Text("Nothing finished").foregroundStyle(.tertiary).font(.system(size: 12))
                        } else {
                            ForEach(finished) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green.opacity(0.8))
                                    Text(item.title)
                                    Spacer()
                                    if let at = item.completedAt {
                                        Text(at, format: .dateTime.hour().minute())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Finished — \(finished.count)").font(.caption)
                    }

                    if !carriedOut.isEmpty {
                        Section {
                            ForEach(carriedOut) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .foregroundStyle(.orange.opacity(0.8))
                                    Text(item.title)
                                    Spacer()
                                }
                            }
                        } header: {
                            Text("Added that day, still open").font(.caption)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Row

    private func row(_ item: TodoItem) -> some View {
        let carried = store.carriedDays(item)
        return HStack(spacing: 9) {
            Button {
                store.toggle(item)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            if editingID == item.id {
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit { commitEdit(item) }
                    .onExitCommand { editingID = nil }
            } else {
                Text(item.title)
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .onTapGesture(count: 2) { startEdit(item) }
                    .help("Double-click to rename")
            }

            Spacer()

            if !item.isDone, carried > 0 {
                Text(carried == 1 ? "yesterday" : "\(carried)d")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                    .help("Carried over from \(carried) day\(carried == 1 ? "" : "s") ago")
            }
        }
        .contextMenu {
            Button("Rename") { startEdit(item) }
            moveMenu(item)
            Divider()
            Button(item.isDone ? "Mark as not done" : "Mark as done") { store.toggle(item) }
            Button("Delete", role: .destructive) { store.remove(item) }
        }
    }

    @ViewBuilder private func moveMenu(_ item: TodoItem) -> some View {
        Menu("Move to group") {
            if item.group != nil {
                Button("None") { store.setGroup(item, to: nil) }
                Divider()
            }
            ForEach(store.groupNames.filter { $0 != item.group }, id: \.self) { name in
                Button(name) { store.setGroup(item, to: name) }
            }
            Button("New group…") { promptNew(item) }
        }
    }

    // MARK: - Editing / group prompts

    private func startEdit(_ item: TodoItem) {
        editingText = item.title
        editingID = item.id
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitEdit(_ item: TodoItem) {
        store.rename(item, to: editingText)
        editingID = nil
    }

    private func promptNew(_ item: TodoItem) {
        groupPrompt = .newFor(item); groupPromptText = ""; showGroupPrompt = true
    }

    private func promptRename(_ name: String) {
        groupPrompt = .rename(name); groupPromptText = name; showGroupPrompt = true
    }

    private func applyGroupPrompt() {
        switch groupPrompt {
        case .newFor(let item): store.setGroup(item, to: groupPromptText)
        case .rename(let old):  store.renameGroup(old, to: groupPromptText)
        case .none: break
        }
        groupPrompt = nil
    }

    private var promptTitle: String {
        if case .rename = groupPrompt { return "Rename group" }
        return "New group"
    }
    private var promptButton: String {
        if case .rename = groupPrompt { return "Rename" }
        return "Create"
    }

    // MARK: - Pieces

    private func empty(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(subtitle).font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func shiftDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: historyDay) else { return }
        if next <= Date() { historyDay = next }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}
