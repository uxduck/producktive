import Foundation
import ProducktiveCore

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
let usage = """
Usage: producktive-cli COMMAND [ARGUMENTS]

Uses the file selected in Producktive, or ~/.producktive/deadlines.md on first use.
No file argument is needed. Use --file PATH for a one-command override.

Commands:
  path                              Print the selected deadline file path
  show                              Print the full Markdown document and notes
  list                              List active and archived deadlines
  validate                          Validate the deadline document
  add-event JSON_EVENT               Add a deadline
  add-goal EVENT_ID JSON_GOAL         Add a goal to a deadline
  reschedule ID TIMESTAMP [END]      Change a deadline's date
  goal EVENT_ID GOAL_ID CURRENT_OR_null STATUS
  complete ID REASON                 Complete a deadline
  archive ID REASON                  Archive a deadline
  configure PATH                    Select a file for the app and future commands
  install-skills --resources PATH codex|claude|cursor ...

Run producktive-cli COMMAND --help for command usage.
"""
let commandUsage = [
    "path": "path [--file PATH]", "show": "show [--file PATH]",
    "list": "list [--file PATH]", "validate": "validate [--file PATH]",
    "archive": "archive [--file PATH] ID REASON", "complete": "complete [--file PATH] ID REASON",
    "reschedule": "reschedule [--file PATH] ID TIMESTAMP [END_TIMESTAMP]",
    "goal": "goal [--file PATH] EVENT_ID GOAL_ID CURRENT_OR_null STATUS",
    "add-event": "add-event [--file PATH] JSON_EVENT", "add-goal": "add-goal [--file PATH] EVENT_ID JSON_GOAL",
    "configure": "configure /absolute/path/deadlines.md",
    "install-skills": "install-skills --resources PATH [--home PATH] codex|claude|cursor ..."
]
do {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { print(usage); exit(0) }
    args.removeFirst()
    if command == "--help" || command == "-h" || command == "help" { print(usage); exit(0) }
    guard let detail = commandUsage[command] else { fail("Unknown command: \(command). Run producktive-cli --help.") }
    if args.contains("--help") || args.contains("-h") {
        print("Usage: producktive-cli \(detail)")
        if command != "configure" && command != "install-skills" {
            print("\nUses the app's selected file unless --file PATH is supplied.")
        }
        exit(0)
    }
    if command == "install-skills" {
        var home = FileManager.default.homeDirectoryForCurrentUser
        if let index = args.firstIndex(of: "--home"), args.indices.contains(index + 1) {
            home = URL(fileURLWithPath: args[index + 1]); args.removeSubrange(index...(index + 1))
        }
        guard let index = args.firstIndex(of: "--resources"), args.indices.contains(index + 1) else { fail("install-skills requires --resources PATH and agent names: codex claude cursor") }
        let resources = URL(fileURLWithPath: args[index + 1]); args.removeSubrange(index...(index + 1))
        let agents = try Set(args.map { name -> Agent in
            guard let agent = Agent(rawValue: name) else { throw ProducktiveError("Unknown agent: \(name)") }; return agent
        })
        print(try SkillInstaller.install(agents: agents, resources: resources, home: home).joined(separator: "\n"))
        exit(0)
    }
    if command == "configure" {
        guard args.count == 1 else { fail("Usage: configure /absolute/path/deadlines.md") }
        try FileStore.chooseDeadlineFile(try Config(deadlines_file: args[0]).deadlinesURL())
        print("Configured selected deadline file."); exit(0)
    }
    var override: String?
    if let flag = args.firstIndex(of: "--file") {
        guard args.filter({ $0 == "--file" }).count == 1, args.indices.contains(flag + 1), !args[flag + 1].hasPrefix("--") else { fail("--file requires one absolute path.") }
        override = args[flag + 1]
        args.removeSubrange(flag...(flag + 1))
    }
    let file = try FileStore.deadlineURL(override: override)
    if command == "path" {
        guard args.isEmpty else { fail("Usage: \(detail)") }
        print(file.path); exit(0)
    }
    guard FileManager.default.fileExists(atPath: file.path) else {
        fail("Deadline file not found: \(file.path). Select an existing file with producktive-cli configure PATH or Choose file… in the app.")
    }
    let revision = try FileRevision(url: file)
    let snapshot = revision.document.snapshot
    switch command {
    case "show":
        guard args.isEmpty else { fail("Usage: \(detail)") }
        FileHandle.standardOutput.write(revision.bytes)
    case "validate":
        guard args.isEmpty else { fail("Usage: validate [--file PATH]") }
        print("Valid version 1 document: \(snapshot.active.count) active, \(snapshot.archived.count) archived.")
    case "list":
        guard args.isEmpty else { fail("Usage: list [--file PATH]") }
        let engine = CountdownEngine()
        for event in snapshot.active { print("\(event.id)\t\(event.event.title)\t\(engine.text(for: event.date))\(event.date <= Date() ? " overdue" : "")\t\(Timestamp.display(event))") }
        for event in snapshot.archived { print("\(event.id)\t\(event.event.title)\t\(event.event.status ?? "archived")\t\(event.event.at)") }
    case "archive", "complete":
        guard args.count == 2 else { fail("Usage: \(command) [--file PATH] ID REASON") }
        try FileStore.apply(.archive(id: args[0], status: command == "complete" ? "completed" : "archived", reason: args[1]), to: revision)
        print("Moved event and its goals to archived.")
    case "reschedule":
        guard (2...3).contains(args.count) else { fail("Usage: reschedule [--file PATH] ID TIMESTAMP [END_TIMESTAMP]") }
        try FileStore.apply(.reschedule(id: args[0], at: args[1], endsAt: args.count == 3 ? args[2] : nil), to: revision)
        print("Rescheduled event; ID preserved.")
    case "goal":
        guard args.count == 4, args[2] == "null" || Double(args[2]) != nil else { fail("Usage: goal [--file PATH] EVENT_ID GOAL_ID CURRENT_OR_null STATUS") }
        try FileStore.apply(.goal(eventID: args[0], goalID: args[1], current: Double(args[2]), status: args[3]), to: revision)
        print("Updated goal.")
    case "add-event":
        guard args.count == 1 else { fail("Usage: add-event [--file PATH] JSON_EVENT") }
        let event = try JSONDecoder().decode(Event.self, from: Data(args[0].utf8))
        try FileStore.apply(.addEvent(event), to: revision)
        print("Added event.")
    case "add-goal":
        guard args.count == 2 else { fail("Usage: add-goal [--file PATH] EVENT_ID JSON_GOAL") }
        let goal = try JSONDecoder().decode(Goal.self, from: Data(args[1].utf8))
        try FileStore.apply(.addGoal(eventID: args[0], goal: goal), to: revision)
        print("Added goal.")
    default: fail("Unknown command: \(command)")
    }
} catch { fail(error.localizedDescription) }
