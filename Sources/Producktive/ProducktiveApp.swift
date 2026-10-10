import SwiftUI
import AppKit
import ProducktiveCore

@main struct ProducktiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        MenuBarExtra { DeadlinePanel(model: appDelegate.model) } label: { DeadlineMenuLabel(model: appDelegate.model) }
            .menuBarExtraStyle(.window)
    }

}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch, !CommandLine.arguments.contains("--preview-panel") {
            model.showDeadlineWindow()
        }
        // Handle explicit launches even when the menu bar item is hidden or crowded.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(reopen(_:withReplyEvent:)), forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEReopenApplication))
    }

    @objc private func reopen(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        model.showDeadlineWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct DeadlineMenuLabel: View {
    @ObservedObject var model: AppModel
    var body: some View { Text(model.label) }
}

struct DeadlinePanel: View {
    @ObservedObject var model: AppModel
    @State private var agents = Set<Agent>()
    @State private var showAgents = false
    @State private var visibilityID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                Text("Producktive").font(.headline)
                Spacer()
                Button { model.showDeadlineWindow() } label: { Image(systemName: "arrow.up.right.square") }.help("Open deadline window")
                Button { model.reload(force: true) } label: { Image(systemName: "arrow.clockwise") }.help("Reload deadlines")
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 4) {
                    Label(model.snapshot == nil ? "Unable to load deadlines" : "Stale data · last valid snapshot", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Text(error).font(.caption).textSelection(.enabled)
                }.foregroundStyle(.red).padding(10).background(.red.opacity(0.08)).cornerRadius(8)
            }
            if let snapshot = model.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        section("Overdue", events: snapshot.active.filter { $0.date <= model.now }, archived: false)
                        section("Upcoming", events: snapshot.active.filter { $0.date > model.now }, archived: false)
                        if snapshot.active.isEmpty { Text("No active deadlines. Add one in your deadline file or with your agent.").foregroundStyle(.secondary).padding(.vertical, 8) }
                        DisclosureGroup("Archived (\(snapshot.archived.count))") {
                            ForEach(snapshot.archived) { event in EventRow(event: event, archived: true, model: model) }
                        }
                    }.padding(.trailing, 6)
                }.frame(height: min(480, max(140, CGFloat(snapshot.active.count) * 170 + 50)))
            } else if model.error == nil { ProgressView("Loading deadlines…") }
            Divider()
            HStack {
                Button("Open file") { model.openFile() }.disabled(model.fileURL == nil)
                Button("Choose file…") { model.chooseFile() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            Toggle("Launch at login", isOn: $model.launchAtLogin).onChange(of: model.launchAtLogin) { _ in model.toggleLogin() }
            DisclosureGroup("Install agent skill", isExpanded: $showAgents) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Agent.allCases) { agent in
                        Toggle(agent.title, isOn: Binding(get: { agents.contains(agent) }, set: { value in if value { agents.insert(agent) } else { agents.remove(agent) } }))
                    }
                    Button("Install selected") { model.installSkills(agents) }.disabled(agents.isEmpty)
                    if let message = model.skillMessage { Text(message).font(.caption).textSelection(.enabled) }
                }.padding(.top, 6)
            }
        }
        .padding(16).frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(PanelVisibility { visible in
            model.setPanelVisible(visible, id: visibilityID)
        })
        .onDisappear { model.setPanelVisible(false, id: visibilityID) }
    }
    @ViewBuilder private func section(_ name: String, events: [ResolvedEvent], archived: Bool) -> some View {
        if !events.isEmpty {
            Text(name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(events) { EventRow(event: $0, archived: archived, model: model) }
        }
    }
}

struct EventRow: View {
    let event: ResolvedEvent
    let archived: Bool
    @ObservedObject var model: AppModel
    @State private var reschedule = false
    @State private var at = ""
    @State private var end = ""
    @State private var archive = false
    @State private var reason = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(event.event.title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !archived {
                    Text(model.engine.text(for: event.date) + (event.date <= model.now ? " overdue" : ""))
                        .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(event.date <= model.now ? .red : .primary)
                }
            }
            Text(Timestamp.display(event)).font(.caption).foregroundStyle(.secondary)
            if let source = event.event.source, let url = URL(string: source), ["https", "http"].contains(url.scheme ?? "") {
                Link("Source", destination: url).font(.caption)
            }
            ForEach(event.event.goals ?? []) { goal in GoalRow(goal: goal, eventID: event.id, archived: archived, model: model) }
            if archived {
                Text("\(event.event.status ?? "archived") · \(event.event.archive_reason ?? "")").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Mark complete") { model.edit(.archive(id: event.id, status: "completed", reason: "Marked complete in Producktive.")) }
                    Button("Archive…") { reason = ""; archive.toggle() }
                    Button("Reschedule…") { at = event.event.at; end = event.event.ends_at ?? ""; reschedule.toggle() }
                }.font(.caption).disabled(model.error != nil)
                if archive {
                    TextField("Archive reason", text: $reason)
                    HStack {
                        Button("Archive event") { model.edit(.archive(id: event.id, status: "archived", reason: reason)); archive = false }.disabled(model.error != nil || reason.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { archive = false }
                    }
                }
                if reschedule {
                    Text("Event timezone: \(event.zone.identifier)").font(.caption)
                    TextField("YYYY-MM-DDTHH:MM:SS", text: $at)
                    TextField("End timestamp (optional)", text: $end)
                    HStack {
                        Button("Save time") { model.edit(.reschedule(id: event.id, at: at, endsAt: end.isEmpty ? nil : end)); reschedule = false }.disabled(model.error != nil)
                        Button("Cancel") { reschedule = false }
                    }
                }
            }
        }.padding(10).background(.primary.opacity(0.035)).cornerRadius(8)
    }
}

struct GoalRow: View {
    let goal: Goal
    let eventID: String
    let archived: Bool
    @ObservedObject var model: AppModel
    @State private var editing = false
    @State private var current = ""
    @State private var status = "active"
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(goal.title).font(.caption.weight(.medium))
            HStack {
                Text("\(goal.current.map(number) ?? "?") / \(number(goal.target)) \(goal.unit) · \(goal.status)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !archived { Button("Edit") { current = goal.current.map { String($0) } ?? ""; status = goal.status; editing.toggle() }.font(.caption).disabled(model.error != nil) }
            }
            if let current = goal.current, goal.target > 0 { ProgressView(value: min(current / goal.target, 1)).tint(goal.status == "achieved" ? .green : .orange) }
            if editing {
                TextField("Current value (blank = unknown)", text: $current)
                Picker("Status", selection: $status) { ForEach(["active", "achieved", "paused", "abandoned"], id: \.self) { Text($0) } }
                HStack {
                    Button("Save goal") { model.edit(.goal(eventID: eventID, goalID: goal.id, current: Double(current), status: status)); editing = false }.disabled(model.error != nil || (!current.isEmpty && Double(current) == nil))
                    Button("Cancel") { editing = false }
                }
            }
        }.padding(.leading, 8)
    }
}

/// Observes window focus/closure without polling or relying on retained views disappearing.
struct PanelVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(changed: changed) }
    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.windowChanged = { [weak coordinator = context.coordinator] window in coordinator?.watch(window) }
        return view
    }
    func updateNSView(_ view: TrackingView, context: Context) {}
    final class TrackingView: NSView {
        var windowChanged: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); windowChanged?(window) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    final class Coordinator {
        let changed: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        init(changed: @escaping (Bool) -> Void) { self.changed = changed }
        func watch(_ window: NSWindow?) {
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            changed(window?.isKeyWindow == true && window?.isVisible == true)
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] notification in
                    self?.changed(notification.name == NSWindow.didBecomeKeyNotification && window?.isVisible == true)
                })
            }
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
