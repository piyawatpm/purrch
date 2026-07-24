import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// Start of the day the task was added.
    var createdOn: Date
    /// Exact moment it was ticked off; nil while it's still open.
    var completedAt: Date?

    var isDone: Bool { completedAt != nil }
}

/// Tasks, stored as a flat list in Application Support.
///
/// There is deliberately no per-day bucketing: an open task simply stays open, so
/// it shows up on today's list every day until it's done. "Carrying forward" is
/// therefore the default behaviour rather than a nightly migration that could be
/// missed if the Mac was asleep at midnight.
final class TaskStore: ObservableObject {
    static let shared = TaskStore()
    static let allDoneToday = Notification.Name("PetAllTasksDoneToday")
    static let didChange = Notification.Name("PetTasksDidChange")
    /// Posted when an open task is ticked off — this is what earns him a meal.
    static let taskCompleted = Notification.Name("PetTaskCompleted")

    @Published private(set) var items: [TodoItem] = []

    private let fileURL: URL
    private let calendar = Calendar.current

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DeskPet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tasks.json")
        load()
    }

    // MARK: - Views onto the list

    /// Everything still open (whenever it was added) plus whatever was finished today.
    var today: [TodoItem] {
        let open = items.filter { !$0.isDone }
            .sorted { $0.createdOn < $1.createdOn }
        return open + doneToday
    }

    var doneToday: [TodoItem] {
        items.filter { item in
            guard let done = item.completedAt else { return false }
            return calendar.isDateInToday(done)
        }
        .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    var openCount: Int { items.filter { !$0.isDone }.count }

    /// How many days an open task has been rolling over. 0 means it was added today.
    func carriedDays(_ item: TodoItem) -> Int {
        let start = calendar.startOfDay(for: item.createdOn)
        let today = calendar.startOfDay(for: Date())
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    func completed(on day: Date) -> [TodoItem] {
        items.filter { item in
            guard let done = item.completedAt else { return false }
            return calendar.isDate(done, inSameDayAs: day)
        }
        .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    func added(on day: Date) -> [TodoItem] {
        items.filter { calendar.isDate($0.createdOn, inSameDayAs: day) }
            .sorted { $0.createdOn < $1.createdOn }
    }

    /// Consecutive days ending today on which something was finished. A day with
    /// nothing done yet doesn't break the run until it's over, so the streak
    /// survives right up to midnight.
    var streak: Int {
        var days = Set<Date>()
        for item in items {
            if let done = item.completedAt { days.insert(calendar.startOfDay(for: done)) }
        }
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Days that have any activity, newest first — drives the history picker.
    func activeDays(limit: Int = 60) -> [Date] {
        var days = Set<Date>()
        for item in items {
            days.insert(calendar.startOfDay(for: item.createdOn))
            if let done = item.completedAt { days.insert(calendar.startOfDay(for: done)) }
        }
        return days.sorted(by: >).prefix(limit).map { $0 }
    }

    // MARK: - Mutation

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(title: trimmed,
                              createdOn: calendar.startOfDay(for: Date()),
                              completedAt: nil))
        save()
    }

    func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let wasOpen = !items[index].isDone
        items[index].completedAt = items[index].isDone ? nil : Date()
        save()

        if wasOpen {
            NotificationCenter.default.post(name: TaskStore.taskCompleted, object: nil)
        }
        // Finishing the last open task is worth a small celebration on top.
        if wasOpen, openCount == 0, !doneToday.isEmpty {
            NotificationCenter.default.post(name: TaskStore.allDoneToday, object: nil)
        }
    }

    func remove(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func rename(_ item: TodoItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].title = trimmed
        save()
    }

    /// Drops finished tasks older than the retention window so the file can't grow forever.
    func pruneHistory(olderThanDays days: Int = 365) {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        let before = items.count
        items.removeAll { item in
            guard let done = item.completedAt else { return false }
            return done < cutoff
        }
        if items.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([TodoItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        // Atomic so a crash mid-write can't leave a truncated file behind.
        try? data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: TaskStore.didChange, object: nil)
    }
}
