import AppKit
import SwiftUI
import ServiceManagement
import ProducktiveCore

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var error: String?
    @Published private(set) var fileURL: URL?
    @Published private(set) var now = Date()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var dropdownOpen = false
    @Published var skillMessage: String?
    @Published var showDockIcon = true {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            applyDockVisibility()
        }
    }
    @Published var titleCharacterLimit: Int = 24 {
        didSet {
            let clamped = min(80, max(1, titleCharacterLimit))
            if titleCharacterLimit != clamped { titleCharacterLimit = clamped }
            UserDefaults.standard.set(titleCharacterLimit, forKey: "menuBarTitleCharacterLimit")
        }
    }
    private var revision: FileRevision?
    private var snapshotURL: URL?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var previewWindow: NSWindow?
    private var deadlineWindow: NSWindow?
    private var visiblePanels = Set<UUID>()
    private var didExportPreview = false
    private var loadingGeneration = 0
    private let home: URL
    private lazy var watcher = FileWatcher { [weak self] in self?.reload() }
    private let workQueue = DispatchQueue(label: "com.uxduck.producktive.store", qos: .userInitiated)
    var engine: CountdownEngine { CountdownEngine(clock: { self.now }) }
    var label: String { engine.label(for: engine.selected(in: snapshot?.active ?? []), stale: error != nil, titleCharacterLimit: titleCharacterLimit) }

    init() {
        if let savedDockVisibility = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool {
            showDockIcon = savedDockVisibility
        }
        if let savedLimit = UserDefaults.standard.object(forKey: "menuBarTitleCharacterLimit") as? Int {
            titleCharacterLimit = min(80, max(1, savedLimit))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--data-home"), CommandLine.arguments.indices.contains(index + 1) {
            home = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        } else { home = FileManager.default.homeDirectoryForCurrentUser }

        let notifications: [Notification.Name] = [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
        for name in notifications {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshTime() }
            })
        }
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshTime(); self?.reload() }
        })
        reload(bootstrap: true)
        if CommandLine.arguments.contains("--preview-panel") {
            DispatchQueue.main.async { [weak self] in self?.showPreview() }
        }
    }
    func applyDockVisibility() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
    func showDeadlineWindow() {
        if deadlineWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: DeadlinePanel(model: self)))
            window.title = "Producktive"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 440, height: 660))
            window.center()
            deadlineWindow = window
        }
        deadlineWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func setPanelVisible(_ visible: Bool, id: UUID) {
        if visible { visiblePanels.insert(id) } else { visiblePanels.remove(id) }
        let open = !visiblePanels.isEmpty
        if dropdownOpen != open { dropdownOpen = open; refreshTime() }
    }
    private func showPreview() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: DeadlinePanel(model: self)))
        window.title = "Producktive Preview"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 440, height: 740))
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        exportPreviewIfRequested()
    }
    private func exportPreviewIfRequested() {
        guard !didExportPreview, snapshot != nil, previewWindow != nil,
              CommandLine.arguments.contains("--data-home"),
              let index = CommandLine.arguments.firstIndex(of: "--export-panel"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        didExportPreview = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let view = self?.previewWindow?.contentView else { return }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let bytes = bitmap.representation(using: .png, properties: [:]) {
                try? bytes.write(to: output, options: .atomic)
            }
        }
    }
    func reload(force: Bool = false, bootstrap: Bool = false) {
        loadingGeneration += 1
        let generation = loadingGeneration
        let oldBytes = revision?.bytes
        let oldURL = snapshotURL
        let home = self.home
        let configURL = Config.directory(home: home).appendingPathComponent("config.yaml")
        workQueue.async { [weak self] in
            var selectedURL: URL?
            do {
                if bootstrap { try FileStore.bootstrap(home: home) }
                let url = try Config.read(home: home).deadlinesURL(home: home)
                selectedURL = url
                let bytes = try Data(contentsOf: url)
                if !force, url == oldURL, bytes == oldBytes {
                    DispatchQueue.main.async {
                        guard let self, self.loadingGeneration == generation else { return }
                        let recovering = self.error != nil
                        self.error = nil; self.fileURL = url
                        self.watcher.watch([configURL, url])
                        if recovering { self.refreshTime() }
                    }
                    return
                }
                let latest = try FileRevision(url: url)
                DispatchQueue.main.async {
                    guard let self, self.loadingGeneration == generation else { return }
                    self.revision = latest; self.snapshotURL = url; self.fileURL = url
                    self.snapshot = latest.document.snapshot; self.error = nil
                    self.watcher.watch([configURL, url]); self.refreshTime()
                    self.exportPreviewIfRequested()
                }
            } catch {
                let failure = error.localizedDescription
                let failedURL = selectedURL
                DispatchQueue.main.async {
                    guard let self, self.loadingGeneration == generation else { return }
                    self.error = failure; self.fileURL = failedURL ?? self.fileURL
                    self.watcher.watch([configURL] + [failedURL ?? self.fileURL].compactMap { $0 })
                    self.refreshTime()
                }
            }
        }
    }
    func refreshTime() {
        now = Date()
        timer?.invalidate(); timer = nil
        if let next = engine.nextWakeup(events: snapshot?.active ?? [], dropdownOpen: dropdownOpen) {
            let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refreshTime() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    func edit(_ edit: MarkdownDocument.Edit) {
        guard error == nil, let revision, revision.url == fileURL else { return }
        workQueue.async { [weak self] in
            do {
                _ = try FileStore.apply(edit, to: revision)
                DispatchQueue.main.async { self?.reload(force: true) }
            } catch {
                let failure = error.localizedDescription
                DispatchQueue.main.async { self?.error = failure }
            }
        }
    }
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = "Choose a Markdown file with Producktive YAML frontmatter."
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try FileStore.chooseDeadlineFile(url, home: home); reload(force: true) }
        catch { self.error = error.localizedDescription }
    }
    func openFile() {
        if let fileURL { NSWorkspace.shared.open(fileURL) }
    }
    func toggleLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { self.error = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    func installSkills(_ agents: Set<Agent>) {
        guard let resources = Bundle.main.resourceURL else { return }
        do { skillMessage = try SkillInstaller.install(agents: agents, resources: resources, home: home).joined(separator: "\n") }
        catch { skillMessage = error.localizedDescription }
    }
}
