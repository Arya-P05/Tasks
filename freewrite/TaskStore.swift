import Foundation
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {
    enum CarryoverDecision {
        case carryOver
        case clearTodayToThisWeek
        case cancel
    }

    @Published private(set) var tasks: [TodoTask] = []
    @Published private(set) var completed: [TodoTask] = []
    @Published var selectedBucket: TaskBucket = .today

    // UI state
    @Published var shouldShowCarryoverPrompt: Bool = false

    private let fileManager = FileManager.default
    private let maxCompletedToKeep = 200

    private var meta: TodoMeta = .init()

    // For “Undo” of last completion
    private var lastCompleted: TodoTask?

    init() {
        loadAll()
        evaluateDailyPrompt()
    }

    // MARK: - Public API

    func tasks(in bucket: TaskBucket) -> [TodoTask] {
        tasks
            .filter { !$0.isCompleted && $0.bucket == bucket }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func completedTasksSorted() -> [TodoTask] {
        completed.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }

    func addTask(title: String, bucket: TaskBucket) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        tasks.append(TodoTask(title: trimmed, bucket: bucket))
        persist()
    }

    func updateTaskTitle(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].title = trimmed
        persist()
    }

    func moveTask(id: UUID, to bucket: TaskBucket) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].bucket = bucket
        persist()
    }

    func completeTask(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var t = tasks[idx]
        guard !t.isCompleted else { return }

        t.completedAt = Date()
        tasks.remove(at: idx)

        lastCompleted = t
        completed.insert(t, at: 0)
        if completed.count > maxCompletedToKeep {
            completed = Array(completed.prefix(maxCompletedToKeep))
        }
        persist()
    }

    func canUndoComplete() -> Bool {
        lastCompleted != nil
    }

    func undoLastComplete() {
        guard let t = lastCompleted else { return }
        lastCompleted = nil

        // Remove from completed if present
        if let cIdx = completed.firstIndex(where: { $0.id == t.id }) {
            completed.remove(at: cIdx)
        }

        var restored = t
        restored.completedAt = nil
        tasks.append(restored)
        persist()
    }

    func applyCarryoverDecision(_ decision: CarryoverDecision) {
        switch decision {
        case .carryOver:
            // Keep Today tasks as-is
            break
        case .clearTodayToThisWeek:
            for idx in tasks.indices {
                if tasks[idx].bucket == .today {
                    tasks[idx].bucket = .thisWeek
                }
            }
        case .cancel:
            // Do nothing
            break
        }

        stampOpenedToday()
        shouldShowCarryoverPrompt = false
        persist()
    }

    func refreshDailyPrompt() {
        evaluateDailyPrompt()
    }

    // MARK: - Daily prompt logic

    private func evaluateDailyPrompt() {
        let todayISO = TodoMeta.isoDayString(for: Date())
        let lastISO = meta.lastOpenedDayISO

        guard lastISO != todayISO else {
            shouldShowCarryoverPrompt = false
            return
        }

        // New day. Only prompt if there’s anything in Today to decide about.
        let hasTodayTasks = tasks.contains { !$0.isCompleted && $0.bucket == .today }
        if hasTodayTasks {
            shouldShowCarryoverPrompt = true
        } else {
            // Nothing to carry over; silently stamp.
            stampOpenedToday()
            shouldShowCarryoverPrompt = false
            persist()
        }
    }

    private func stampOpenedToday() {
        meta.lastOpenedDayISO = TodoMeta.isoDayString(for: Date())
    }

    // MARK: - Persistence

    private func baseDirectory() -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("FreewriteTodo", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func urlTasks() -> URL { baseDirectory().appendingPathComponent("tasks.json") }
    private func urlCompleted() -> URL { baseDirectory().appendingPathComponent("completed.json") }
    private func urlMeta() -> URL { baseDirectory().appendingPathComponent("meta.json") }

    private func loadAll() {
        tasks = load([TodoTask].self, from: urlTasks()) ?? []
        completed = load([TodoTask].self, from: urlCompleted()) ?? []
        meta = load(TodoMeta.self, from: urlMeta()) ?? TodoMeta()
    }

    private func persist() {
        save(tasks, to: urlTasks())
        save(completed, to: urlCompleted())
        save(meta, to: urlMeta())
    }

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder().decode(T.self, from: data)
        } catch {
            // If decode fails, treat as empty rather than crashing.
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Intentionally silent for v1 minimalism
        }
    }
}


