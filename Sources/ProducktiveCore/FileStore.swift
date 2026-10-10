import Foundation
import Darwin

public struct FileRevision: Sendable {
    public let url: URL
    public let bytes: Data
    public let document: MarkdownDocument
    public init(url: URL) throws {
        self.url = url.resolvingSymlinksInPath()
        bytes = try Data(contentsOf: self.url)
        guard let text = String(data: bytes, encoding: .utf8) else { throw ProducktiveError("Deadline file must be UTF-8.") }
        document = try MarkdownDocument(text)
    }
}

public enum FileStore {
    /// Coordinates cooperating editors, rechecks original bytes, keeps a backup, and atomically renames.
    @discardableResult public static func apply(_ edit: MarkdownDocument.Edit, to revision: FileRevision,
                                               beforeCommit: (() throws -> Void)? = nil) throws -> FileRevision {
        let result = try revision.document.editing(edit)
        try replace(url: revision.url, expected: revision.bytes, new: Data(result.text.utf8), beforeCommit: beforeCommit)
        return try FileRevision(url: revision.url)
    }
    public static func replace(url: URL, expected: Data?, new: Data, beforeCommit: (() throws -> Void)? = nil) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                let manager = FileManager.default
                func check() throws {
                    let exists = manager.fileExists(atPath: coordinatedURL.path)
                    if let expected {
                        guard exists, try Data(contentsOf: coordinatedURL) == expected else { throw ProducktiveError("File changed in another editor. Reload before trying again.") }
                    } else if exists { throw ProducktiveError("File appeared in another editor. Reload before trying again.") }
                }
                try check()
                let temporary = coordinatedURL.deletingLastPathComponent().appendingPathComponent(".producktive-\(UUID().uuidString).tmp")
                defer { try? manager.removeItem(at: temporary) }
                try new.write(to: temporary, options: .withoutOverwriting)
                let permissions = (try? manager.attributesOfItem(atPath: coordinatedURL.path)[.posixPermissions]) ?? 0o600
                try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
                let fd = open(temporary.path, O_RDONLY)
                if fd >= 0 { _ = fsync(fd); close(fd) }
                if let expected {
                    let backup = coordinatedURL.appendingPathExtension("backup-\(UUID().uuidString)")
                    try expected.write(to: backup, options: .withoutOverwriting)
                    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                }
                try beforeCommit?()
                try check()
                guard rename(temporary.path, coordinatedURL.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                let directoryFD = open(coordinatedURL.deletingLastPathComponent().path, O_RDONLY)
                if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
            } catch { operationError = error }
        }
        if let error = operationError ?? coordinationError { throw error }
    }
    public static func bootstrap(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let manager = FileManager.default
        let directory = Config.directory(home: home)
        let configURL = directory.appendingPathComponent("config.yaml")
        let deadlineURL = directory.appendingPathComponent("deadlines.md")
        guard !manager.fileExists(atPath: configURL.path), !manager.fileExists(atPath: deadlineURL.path) else { return }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let text = "---\nversion: 1\ntimezone: \"America/Los_Angeles\"\ncountdown_decimals: 1\nactive: []\narchived: []\n---\n\n# Deadline notes\n"
        _ = try MarkdownDocument(text)
        try replace(url: deadlineURL, expected: nil, new: Data(text.utf8))
    }
    public static func chooseDeadlineFile(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        _ = try FileRevision(url: url)
        let directory = Config.directory(home: home)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let configURL = directory.appendingPathComponent("config.yaml")
        let expected = try? Data(contentsOf: configURL)
        let original = expected.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let output = try MarkdownDocument.settingDeadlinePath(url.resolvingSymlinksInPath().path, in: original)
        _ = try MarkdownDocument.validateYAML(output)
        try replace(url: configURL, expected: expected, new: Data(output.utf8))
    }
}
