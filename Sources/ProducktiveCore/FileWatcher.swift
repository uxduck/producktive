import Foundation
import Darwin

/// Watches files and their containing directories so atomic editor saves are observed.
public final class FileWatcher {
    private let queue = DispatchQueue(label: "com.uxduck.producktive.files", qos: .utility)
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var generation = 0
    private let callback: () -> Void
    public init(callback: @escaping () -> Void) { self.callback = callback }
    public func watch(_ urls: [URL]) {
        queue.async { [weak self] in self?.attach(urls) }
    }
    private func attach(_ urls: [URL]) {
        generation += 1
        let current = generation
        pending?.cancel()
        sources.forEach { $0.cancel() }; sources = []
        var paths = Set<String>()
        for url in urls {
            paths.insert(url.path)
            var directory = url.deletingLastPathComponent()
            // Include its parent to observe replacement/deletion of the directory itself.
            paths.insert(directory.path)
            paths.insert(directory.deletingLastPathComponent().path)
            while !FileManager.default.fileExists(atPath: directory.path), directory.path != "/" {
                directory = directory.deletingLastPathComponent(); paths.insert(directory.path)
            }
        }
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke], queue: queue)
            source.setEventHandler { [weak self] in
                guard let self, self.generation == current else { return }
                self.pending?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.generation == current else { return }
                    self.attach(urls)
                    DispatchQueue.main.async(execute: self.callback)
                }
                self.pending = work
                self.queue.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
            source.setCancelHandler { close(fd) }
            source.resume(); sources.append(source)
        }
    }
    deinit { pending?.cancel(); sources.forEach { $0.cancel() } }
}
