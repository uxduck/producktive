import Foundation

public enum Agent: String, CaseIterable, Identifiable {
    case codex, claude, cursor
    public var id: String { rawValue }
    public var title: String { switch self { case .codex: return "Codex"; case .claude: return "Claude Code"; case .cursor: return "Cursor" } }
    public var directory: String { switch self { case .codex: return ".agents/skills"; case .claude: return ".claude/skills"; case .cursor: return ".cursor/skills" } }
}

public enum SkillInstaller {
    private static let marker = "Producktive managed skill v1\n"
    public static func install(agents: Set<Agent>, resources: URL,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [String] {
        guard !agents.isEmpty else { throw ProducktiveError("Select at least one agent.") }
        let manager = FileManager.default
        let source = resources.appendingPathComponent("skills/producktive")
        let executable = resources.appendingPathComponent("bin/producktive-cli")
        guard manager.fileExists(atPath: source.appendingPathComponent("SKILL.md").path), manager.fileExists(atPath: executable.path) else { throw ProducktiveError("Skill or CLI resource missing. Install from the application bundle or release package.") }
        let destinations = Agent.allCases.filter(agents.contains).map { home.appendingPathComponent($0.directory).appendingPathComponent("producktive") }
        for destination in destinations where manager.fileExists(atPath: destination.path) {
            let managed = try? String(contentsOf: destination.appendingPathComponent(".producktive-managed"), encoding: .utf8)
            guard managed == marker else { throw ProducktiveError("Existing skill left untouched: \(destination.path). Move it aside explicitly before installing.") }
        }
        let binaryDirectory = Config.directory(home: home).appendingPathComponent("bin")
        try manager.createDirectory(at: binaryDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let binary = binaryDirectory.appendingPathComponent("producktive-cli")
        let binaryBytes = try Data(contentsOf: executable)
        try binaryBytes.write(to: binary, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        for destination in destinations {
            let parent = destination.deletingLastPathComponent()
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            let staging = parent.appendingPathComponent(".producktive-install-\(UUID().uuidString)")
            defer { try? manager.removeItem(at: staging) }
            try manager.copyItem(at: source, to: staging)
            try marker.write(to: staging.appendingPathComponent(".producktive-managed"), atomically: true, encoding: .utf8)
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: staging)
            } else { try manager.moveItem(at: staging, to: destination) }
        }
        return destinations.map { "Installed: \($0.path)" } + ["CLI: \(binary.path)"]
    }
}
