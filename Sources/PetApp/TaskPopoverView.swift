import SwiftUI

/// The compact list that appears when you click the cat. Deliberately small — add
/// a thing, tick a thing, get out. The full window is one click away.
struct TaskPopoverView: View {
    let onOpenFullList: () -> Void

    @ObservedObject private var store = TaskStore.shared
    @State private var draft = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            let open = store.today.filter { !$0.isDone }
            let done = store.doneToday

            if open.isEmpty && done.isEmpty {
                VStack(spacing: 4) {
                    Text("Nothing on the list").font(.system(size: 12, weight: .medium))
                    Text("Add one below — it stays until it's done.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else if open.count + done.count <= 7 {
                // Short lists size to their content, so the popover isn't mostly
                // empty space when there are only a couple of things on it.
                list(open: open, done: done)
            } else {
                ScrollView { list(open: open, done: done) }
                    .frame(height: 218)
            }

            Divider()
            addField
        }
        .frame(width: 288)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today").font(.system(size: 13, weight: .semibold))
            Spacer()
            let streak = store.streak
            if streak > 1 {
                Text("\(streak) day streak")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Button(action: onOpenFullList) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open the full list")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func list(open: [TodoItem], done: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(open) { row($0) }
            if !done.isEmpty {
                Text("Done today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, open.isEmpty ? 2 : 8)
                    .padding(.bottom, 2).padding(.horizontal, 12)
                ForEach(done) { row($0) }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: TodoItem) -> some View {
        let carried = store.carriedDays(item)
        return HStack(spacing: 8) {
            Button { store.toggle(item) } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 12))
                .strikethrough(item.isDone, color: .secondary)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if !item.isDone, carried > 0 {
                Text(carried == 1 ? "1d" : "\(carried)d")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Delete", role: .destructive) { store.remove(item) }
        }
    }

    private var addField: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("Add a task", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($addFieldFocused)
                .onSubmit {
                    store.add(draft)
                    draft = ""
                    addFieldFocused = true      // keep going without reaching for the mouse
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .onAppear { addFieldFocused = true }
    }
}
