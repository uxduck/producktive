import Foundation
import Yams

public struct ProducktiveError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Goal: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var target: Double
    public var unit: String
    public var current: Double?
    public var status: String
}

public struct Event: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var at: String
    public var ends_at: String?
    public var timezone: String?
    public var source: String?
    public var goals: [Goal]?
    public var status: String?
    public var archive_reason: String?
}

public struct DeadlineData: Codable, Sendable {
    public var version: Int
    public var timezone: String
    public var countdown_decimals: Int
    public var active: [Event]
    public var archived: [Event]
}

public struct ResolvedEvent: Identifiable, Sendable {
    public var id: String { event.id }
    public let event: Event
    public let date: Date
    public let endDate: Date?
    public let zone: TimeZone
}

public struct Snapshot: Sendable {
    public let data: DeadlineData
    public let active: [ResolvedEvent]
    public let archived: [ResolvedEvent]

    public init(data: DeadlineData) throws {
        guard data.version == 1, data.countdown_decimals == 1 else {
            throw ProducktiveError("Expected version: 1 and countdown_decimals: 1.")
        }
        _ = try Timestamp.zone(data.timezone)
        var ids = Set<String>()
        func unique(_ id: String) throws {
            guard !id.isEmpty, ids.insert(id).inserted else { throw ProducktiveError("Empty or duplicate ID: \(id)") }
        }
        func resolve(_ event: Event, archived: Bool) throws -> ResolvedEvent {
            try unique(event.id)
            guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProducktiveError("Empty event title: \(event.id)") }
            if archived, event.status?.isEmpty != false || event.archive_reason == nil {
                throw ProducktiveError("Archived event \(event.id) needs status and archive_reason.")
            }
            let zone = try Timestamp.zone(event.timezone ?? data.timezone)
            let date = try Timestamp.resolve(event.at, in: zone)
            let end = try event.ends_at.map { try Timestamp.resolve($0, in: zone) }
            if let end, end <= date { throw ProducktiveError("ends_at must follow at: \(event.id)") }
            for goal in event.goals ?? [] {
                try unique(goal.id)
                guard !goal.title.isEmpty, !goal.unit.isEmpty, goal.target.isFinite, goal.target >= 0,
                      goal.current.map({ $0.isFinite && $0 >= 0 }) ?? true,
                      ["active", "achieved", "paused", "abandoned"].contains(goal.status) else {
                    throw ProducktiveError("Invalid goal: \(goal.id)")
                }
            }
            return ResolvedEvent(event: event, date: date, endDate: end, zone: zone)
        }
        self.data = data
        self.active = try data.active.map { try resolve($0, archived: false) }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        self.archived = try data.archived.map { try resolve($0, archived: true) }.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }
}

public enum Timestamp {
    public static func zone(_ name: String) throws -> TimeZone {
        guard (TimeZone.knownTimeZoneIdentifiers.contains(name) || ["UTC", "GMT"].contains(name)), let zone = TimeZone(identifier: name) else { throw ProducktiveError("Unknown IANA timezone: \(name)") }
        return zone
    }
    public static func resolve(_ input: String, in zone: TimeZone) throws -> Date {
        // Explicit offsets identify an instant and do not have DST ambiguity.
        if input.hasSuffix("Z") || input.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            let suffix = input.hasSuffix("Z") ? "Z" : String(input.suffix(6))
            let civil = String(input.dropLast(suffix.count))
            guard civil.contains("T") else { throw ProducktiveError("Offset timestamps must include a time: \(input)") }
            _ = try civilComponents(civil)
            if suffix != "Z" {
                guard let hours = Int(suffix.dropFirst().prefix(2)), let minutes = Int(suffix.suffix(2)), hours < 24, minutes < 60 else { throw ProducktiveError("Invalid UTC offset: \(input)") }
            }
            let formatter = ISO8601DateFormatter()
            let canonical = civil.count == 16 ? civil + ":00" + suffix : input
            guard let date = formatter.date(from: canonical) else { throw ProducktiveError("Invalid ISO timestamp: \(input)") }
            return date
        }
        let components = try civilComponents(input)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let naive = utc.date(from: components)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = naive.addingTimeInterval(-172800)
        let first = calendar.nextDate(after: start, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first)
        let last = calendar.nextDate(after: start, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last)
        guard let first, let last, calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: first) == components else { throw ProducktiveError("Nonexistent local time (DST): \(input) in \(zone.identifier)") }
        guard first == last else { throw ProducktiveError("Ambiguous local time (DST): \(input). Supply an explicit UTC offset.") }
        return first
    }
    private static func civilComponents(_ input: String) throws -> DateComponents {
        guard input.range(of: #"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?)?$"#, options: .regularExpression) != nil else { throw ProducktiveError("Use a quoted YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS timestamp: \(input)") }
        let numbers = input.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        let components = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers.count > 3 ? numbers[3] : 0, minute: numbers.count > 4 ? numbers[4] : 0, second: numbers.count > 5 ? numbers[5] : 0)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let naive = utc.date(from: components), utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: naive) == components else { throw ProducktiveError("Invalid date: \(input)") }
        return components
    }
    public static func display(_ event: ResolvedEvent, localZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d, yyyy · h:mm a z"
        formatter.timeZone = localZone
        let local = formatter.string(from: event.date)
        if localZone.identifier == event.zone.identifier { return local }
        formatter.timeZone = event.zone
        return local + "\n" + formatter.string(from: event.date) + " (original)"
    }
}

public struct Config: Codable, Sendable {
    public var deadlines_file: String?
    public init(deadlines_file: String? = nil) { self.deadlines_file = deadlines_file }
    public static func directory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL { home.appendingPathComponent(".producktive") }
    public func deadlinesURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        var path = deadlines_file ?? directoryPath(home: home)
        if path == "~" { path = home.path }
        else if path.hasPrefix("~/") { path = home.path + String(path.dropFirst()) }
        guard path.hasPrefix("/") else { throw ProducktiveError("deadlines_file must be an absolute path or start with ~/.") }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }
    private func directoryPath(home: URL) -> String { Self.directory(home: home).appendingPathComponent("deadlines.md").path }
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Config {
        let url = directory(home: home).appendingPathComponent("config.yaml")
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        let text = try String(contentsOf: url, encoding: .utf8)
        try MarkdownDocument.validateYAML(text)
        return try YAMLDecoder().decode(Config.self, from: text)
    }
}
