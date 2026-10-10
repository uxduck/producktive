import AppKit
import Combine
import Sparkle
import SwiftUI

/// One updater shared by the menu bar panel and the standalone deadline window.
@MainActor final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = false {
        didSet {
            if controller?.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller?.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }
    @Published var automaticallyInstalls = false {
        didSet {
            if controller?.updater.automaticallyDownloadsUpdates != automaticallyInstalls {
                controller?.updater.automaticallyDownloadsUpdates = automaticallyInstalls
            }
        }
    }
    @Published private(set) var unavailableReason: String?
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        // swift run, CI, and preview builds have no release key and stay offline.
        guard !CommandLine.arguments.contains("--preview-panel"),
              Bundle.main.bundleURL.pathExtension == "app",
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            unavailableReason = "Updates are available in release builds."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyInstalls)
        do {
            try controller.updater.start()
        } catch {
            unavailableReason = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

struct UpdateSettings: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = updater.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                Toggle("Install updates automatically", isOn: $updater.automaticallyInstalls)
                    .disabled(!updater.automaticallyChecks)
                Text("Checks daily. Automatic updates install when you quit.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
