import Foundation

enum TaskBucket: String, Codable, CaseIterable, Identifiable {
    case today
    case thisWeek
    case someday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This week"
        case .someday: return "Someday"
        }
    }
}

struct TodoTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var bucket: TaskBucket
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        bucket: TaskBucket,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.bucket = bucket
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }
}

struct TodoMeta: Codable, Equatable {
    var lastOpenedDayISO: String?

    static func isoDayString(for date: Date) -> String {
        // yyyy-MM-dd in current calendar/locale-agnostic
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}


