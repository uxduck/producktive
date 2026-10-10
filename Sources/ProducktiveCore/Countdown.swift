import Foundation

public struct CountdownEngine {
    public var clock: () -> Date
    public init(clock: @escaping () -> Date = Date.init) { self.clock = clock }
    public func selected(in events: [ResolvedEvent]) -> ResolvedEvent? {
        events.min { ($0.date, $0.id) < ($1.date, $1.id) }
    }
    public func text(for date: Date) -> String {
        let days = abs(date.timeIntervalSince(clock())) / 86400
        return String(format: "%.1f days", locale: Locale(identifier: "en_US_POSIX"), days)
    }
    public func label(for event: ResolvedEvent?, stale: Bool = false, titleCharacterLimit: Int = 24) -> String {
        let prefix = stale ? "⚠︎ " : ""
        guard let event else { return prefix + "Producktive · No deadlines" }
        let limit = max(1, titleCharacterLimit)
        let title = event.event.title.count > limit ? String(event.event.title.prefix(limit - 1)) + "…" : event.event.title
        return prefix + title + " · " + text(for: event.date) + (event.date <= clock() ? " overdue" : "")
    }
    // A single wakeup at a tenth-day rounding boundary or exact arrival.
    public func nextWakeup(events: [ResolvedEvent], dropdownOpen: Bool) -> Date? {
        let now = clock()
        let visible = dropdownOpen ? events : selected(in: events).map { [$0] } ?? []
        return visible.flatMap { event -> [Date] in
            let delta = event.date.timeIntervalSince(now)
            let step = 8640.0
            let magnitude = abs(delta)
            let rounded = floor(magnitude / step + 0.5)
            let boundary = delta > 0 ? magnitude - max(0, (rounded - 0.5) * step) : (rounded + 0.5) * step - magnitude
            var dates = [now.addingTimeInterval(max(0.05, boundary + 0.01))]
            if delta > 0 { dates.append(event.date) }
            return dates
        }.min()
    }
}
