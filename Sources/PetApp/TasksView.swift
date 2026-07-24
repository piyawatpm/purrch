import SwiftUI

struct TasksView: View {
    @ObservedObject private var store = TaskStore.shared
    @State private var mode: Mode = .today
    @State private var draft = ""
    @State private var historyDay = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

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
                    if !open.isEmpty {
                        Section {
                            ForEach(open) { row($0) }
                        } header: {
                            Text("\(open.count) to do").font(.caption)
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

    // MARK: - Pieces

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

            Text(item.title)
                .strikethrough(item.isDone, color: .secondary)
                .foregroundStyle(item.isDone ? .secondary : .primary)

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
            Button(item.isDone ? "Mark as not done" : "Mark as done") { store.toggle(item) }
            Divider()
            Button("Delete", role: .destructive) { store.remove(item) }
        }
    }

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
