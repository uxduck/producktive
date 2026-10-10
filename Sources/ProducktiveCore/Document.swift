import Foundation
import Yams

/// Retains the source text. The syntax tree locates edits; YAML is never re-encoded wholesale.
public struct MarkdownDocument: @unchecked Sendable {
    public let text: String
    public let snapshot: Snapshot
    private let lines: [String]
    private let yamlStart: Int
    private let yamlEnd: Int
    private let root: Node

    public init(_ text: String) throws {
        guard text.utf8.count <= 5_000_000 else { throw ProducktiveError("Deadline file exceeds 5 MB.") }
        let lines = text.components(separatedBy: "\n")
        func delimiter(_ line: String) -> Bool { line.hasPrefix("---") && line.dropFirst(3).allSatisfy(\.isWhitespace) }
        guard lines.first.map(delimiter) == true,
              let end = lines.dropFirst().firstIndex(where: delimiter) else {
            throw ProducktiveError("The Markdown file must begin with YAML frontmatter between --- lines.")
        }
        let yaml = lines[1..<end].joined(separator: "\n")
        let root = try Self.validateYAML(yaml)
        self.text = text; self.lines = lines; self.yamlStart = 1; self.yamlEnd = end; self.root = root
        snapshot = try Snapshot(data: YAMLDecoder().decode(DeadlineData.self, from: yaml))
    }
    @discardableResult public static func validateYAML(_ yaml: String) throws -> Node {
        guard let root = try Yams.compose(yaml: yaml), root.mapping != nil else { throw ProducktiveError("Expected a YAML mapping.") }
        func validate(_ node: Node, depth: Int) throws {
            guard depth < 40 else { throw ProducktiveError("YAML nesting is too deep.") }
            if case .alias = node { throw ProducktiveError("YAML aliases are unsupported; use explicit records.") }
            if let mapping = node.mapping {
                var keys = Set<String>()
                for (key, value) in mapping {
                    guard let name = key.string, name != "<<", keys.insert(name).inserted else { throw ProducktiveError("Duplicate or unsupported YAML mapping key.") }
                    try validate(value, depth: depth + 1)
                }
            }
            if let sequence = node.sequence { for child in sequence { try validate(child, depth: depth + 1) } }
        }
        try validate(root, depth: 0)
        return root
    }
    public enum Edit: Sendable {
        case archive(id: String, status: String, reason: String)
        case restore(id: String)
        case reschedule(id: String, at: String, endsAt: String?)
        case goal(eventID: String, goalID: String, current: Double?, status: String)
        case addEvent(Event)
        case addGoal(eventID: String, goal: Goal)
    }
    public func editing(_ edit: Edit) throws -> MarkdownDocument {
        var output = lines
        switch edit {
        case let .archive(id, status, reason):
            guard ["completed", "archived"].contains(status), !reason.isEmpty else { throw ProducktiveError("Archive requires completed/archived status and a reason.") }
            let (record, range) = try record(id: id, section: "active")
            var block = Array(lines[range])
            try setField("status", value: Self.quote(status), node: record, base: range.lowerBound, lines: &block)
            try setField("archive_reason", value: Self.quote(reason), node: record, base: range.lowerBound, lines: &block)
            output.removeSubrange(range)
            let active = try list("active")
            if active.count == 1 {
                let line = try keyLine("active")
                output[line] = try emptyListLine(output[line])
            }
            // Reparse so positions remain correct even when archived precedes active.
            let intermediate = try MarkdownDocument(output.joined(separator: "\n"))
            output = try intermediate.appending(block: block, to: "archived")
        case let .restore(id):
            let (node, range) = try record(id: id, section: "archived")
            let block = try restoredBlock(node: node, range: range)
            output.removeSubrange(range)
            if try list("archived").count == 1 {
                let line = try keyLine("archived")
                output[line] = try emptyListLine(output[line])
            }
            let intermediate = try MarkdownDocument(output.joined(separator: "\n"))
            output = try intermediate.appending(block: block, to: "active")
        case let .reschedule(id, at, endsAt):
            let (node, range) = try record(id: id, section: "active")
            var block = Array(lines[range])
            try setField("at", value: Self.quote(at), node: node, base: range.lowerBound, lines: &block)
            // nil preserves the original interval length when there is an end time.
            var end = endsAt
            if end == nil, let resolved = snapshot.active.first(where: { $0.id == id }), let oldEnd = resolved.endDate {
                let newDate = try Timestamp.resolve(at, in: resolved.zone)
                let formatter = ISO8601DateFormatter()
                end = formatter.string(from: newDate.addingTimeInterval(oldEnd.timeIntervalSince(resolved.date)))
            }
            if let end { try setField("ends_at", value: Self.quote(end), node: node, base: range.lowerBound, lines: &block) }
            output.replaceSubrange(range, with: block)
        case let .goal(eventID, goalID, current, status):
            let (node, _) = try record(id: eventID, section: "active")
            guard let goal = node["goals"]?.sequence?.first(where: { $0["id"]?.string == goalID }) else { throw ProducktiveError("Goal not found: \(goalID)") }
            var block = output
            let base = 0
            // Update existing fields first; absent fields insert at the mapping's end.
            try setField("current", value: current.map(String.init(describing:)) ?? "null", node: goal, base: base, lines: &block)
            // Reparse between edits to account for insertion.
            let partial = try MarkdownDocument(block.joined(separator: "\n"))
            let (eventNode, _) = try partial.record(id: eventID, section: "active")
            let goalNode = eventNode["goals"]!.sequence!.first { $0["id"]?.string == goalID }!
            try partial.setField("status", value: Self.quote(status), node: goalNode, base: 0, lines: &block)
            output = block
        case let .addEvent(event):
            guard event.status == nil, event.archive_reason == nil else { throw ProducktiveError("New events belong in active without archive metadata.") }
            let encoded = try YAMLEncoder().encode(event).trimmingCharacters(in: .newlines)
            let block = Self.sequenceBlock(encoded, indent: 2)
            output = try appending(block: block, to: "active")
        case let .addGoal(eventID, goal):
            let (node, range) = try record(id: eventID, section: "active")
            let encoded = try YAMLEncoder().encode(goal).trimmingCharacters(in: .newlines)
            let indent = (node.mark?.column ?? 5) - 1
            let block = Self.sequenceBlock(encoded, indent: indent + 2)
            if let goals = node["goals"] {
                guard let sequence = goals.sequence else { throw ProducktiveError("goals must be a list.") }
                if sequence.isEmpty {
                    guard let key = node.mapping?.first(where: { $0.0.string == "goals" })?.0, let line = key.mark?.line else { throw ProducktiveError("Cannot locate goals.") }
                    let index = yamlStart + line - 1
                    output[index] = try nonemptyListLine(output[index])
                    output.insert(contentsOf: block, at: index + 1)
                } else {
                    try requireBlock(goals)
                    output.insert(contentsOf: block, at: try contentEnd(goals))
                }
            } else {
                output.insert(contentsOf: [String(repeating: " ", count: indent) + "goals:"] + block, at: range.upperBound)
            }
        }
        return try MarkdownDocument(output.joined(separator: "\n"))
    }
    private func restoredBlock(node: Node, range: Range<Int>) throws -> [String] {
        let fields = Set(["status", "archive_reason"])
        var removedLines = Set<Int>()
        var comments: [Int: String] = [:]
        let indent = String(repeating: " ", count: (node.mark?.column ?? 1) - 1)
        for (key, value) in node.mapping ?? [:] where fields.contains(key.string ?? "") {
            guard let keyMark = key.mark, let valueMark = value.mark,
                  value.scalar != nil, keyMark.line == valueMark.line else {
                throw ProducktiveError("Archive metadata must use single-line scalars before restoring.")
            }
            let index = yamlStart + keyMark.line - 1
            let suffix = String(String.UnicodeScalarView(lines[index].unicodeScalars.dropFirst(valueMark.column - 1)))
            let length = try Self.scalarLength(suffix)
            let trailing = String(String.UnicodeScalarView(suffix.unicodeScalars.dropFirst(length))).trimmingCharacters(in: .whitespacesAndNewlines)
            if trailing.hasPrefix("#") { comments[index] = indent + trailing + (lines[index].hasSuffix("\r") ? "\r" : "") }
            removedLines.insert(index)
        }
        let firstField = node.mapping?.compactMap { key, _ -> Int? in
            guard !fields.contains(key.string ?? ""), let mark = key.mark else { return nil }
            return yamlStart + mark.line - 1
        }.min()
        let sequenceIndent = String(lines[range.lowerBound].prefix { $0 == " " })
        return range.compactMap { index in
            if removedLines.contains(index) { return comments[index] }
            if removedLines.contains(range.lowerBound), index == firstField {
                return sequenceIndent + "- " + lines[index].drop(while: { $0 == " " })
            }
            return lines[index]
        }
    }
    private static func sequenceBlock(_ encoded: String, indent: Int) -> [String] {
        encoded.components(separatedBy: "\n").enumerated().map { index, line in
            String(repeating: " ", count: indent) + (index == 0 ? "- " : "  ") + line
        }
    }
    public static func quote(_ string: String) -> String {
        // JSON string literals are valid YAML double-quoted scalars.
        let data = try! JSONEncoder().encode(string)
        return String(data: data, encoding: .utf8)!
    }
    private func keyLine(_ key: String) throws -> Int {
        guard let node = root.mapping?.first(where: { $0.0.string == key })?.0, let line = node.mark?.line else { throw ProducktiveError("Missing list: \(key)") }
        return yamlStart + line - 1
    }
    private func list(_ section: String) throws -> Node.Sequence {
        guard let sequence = root[section]?.sequence else { throw ProducktiveError("\(section) must be a list (use [] when empty).") }
        return sequence
    }
    private func requireBlock(_ node: Node) throws {
        // Yams 6.2.2 loses collection style at the end event; inspect original syntax.
        let first = node.mark.flatMap { mark -> Unicode.Scalar? in
            let index = yamlStart + mark.line - 1
            guard lines.indices.contains(index) else { return nil }
            return Array(lines[index].unicodeScalars).dropFirst(mark.column - 1).first
        }
        if let sequence = node.sequence, !sequence.isEmpty, first == "[" { throw ProducktiveError("Use block-style YAML lists before editing.") }
        if node.mapping != nil, first == "{" { throw ProducktiveError("Use block-style YAML records before editing.") }
    }
    private func record(id: String, section: String) throws -> (Node, Range<Int>) {
        try requireBlock(root[section]!)
        let sequence = try list(section)
        guard let node = sequence.first(where: { $0["id"]?.string == id }), let mark = node.mark else { throw ProducktiveError("Active event not found: \(id)") }
        try requireBlock(node)
        let start = yamlStart + mark.line - 1
        guard lines[start].trimmingCharacters(in: .whitespaces).hasPrefix("- ") else { throw ProducktiveError("Record must begin with '- key: value'.") }
        return (node, start..<(try contentEnd(node)))
    }
    /// Find the last source line occupied by this node, keeping multiline unknown fields intact.
    private func contentEnd(_ node: Node) throws -> Int {
        var marks: [Mark] = []
        func visit(_ n: Node) {
            if let mark = n.mark { marks.append(mark) }
            if let map = n.mapping { for (key, value) in map { visit(key); visit(value) } }
            if let seq = n.sequence { for child in seq { visit(child) } }
        }
        visit(node)
        guard let last = marks.max(by: { $0.line < $1.line }) else { throw ProducktiveError("Cannot locate YAML record.") }
        var end = yamlStart + last.line
        let indent = (node.mark?.column ?? 1) - 1
        // Include subsequent multiline content and record-indented comments, stopping at peers.
        while end < yamlEnd {
            let line = lines[end]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let spaces = line.prefix { $0 == " " }.count
            if trimmed.isEmpty {
                let next = ((end + 1)..<yamlEnd).first { !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                guard let next, lines[next].prefix(while: { $0 == " " }).count >= indent else { break }
                end += 1
                continue
            }
            if spaces < indent || (spaces == indent && !trimmed.hasPrefix("#")) { break }
            end += 1
        }
        return end
    }
    private func setField(_ field: String, value: String, node: Node, base: Int, lines output: inout [String]) throws {
        try requireBlock(node)
        if let pair = node.mapping?.first(where: { $0.0.string == field }), let keyMark = pair.0.mark, let valueMark = pair.1.mark {
            guard pair.1.scalar != nil, keyMark.line == valueMark.line else { throw ProducktiveError("\(field) must be a single-line scalar before editing.") }
            let index = yamlStart + keyMark.line - 1 - base
            var scalars = Array(output[index].unicodeScalars)
            let start = valueMark.column - 1
            guard start < scalars.count else { throw ProducktiveError("Cannot locate \(field).") }
            let original = String(String.UnicodeScalarView(scalars[start...]))
            let length = try Self.scalarLength(original)
            scalars.replaceSubrange(start..<(start + length), with: value.unicodeScalars)
            output[index] = String(String.UnicodeScalarView(scalars))
        } else {
            let indent = (node.mark?.column ?? 1) - 1
            let insertion = try contentEnd(node) - base
            output.insert(String(repeating: " ", count: indent) + field + ": " + value, at: min(insertion, output.count))
        }
    }
    static func scalarLength(_ text: String) throws -> Int {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        let chars = Array(text.unicodeScalars)
        if chars.first == "\"" || chars.first == "'" {
            let quote = chars[0]
            var index = 1
            while index < chars.count {
                if quote == "\"", chars[index] == "\\" { index += 2; continue }
                if chars[index] == quote {
                    if quote == "'", index + 1 < chars.count, chars[index + 1] == quote { index += 2; continue }
                    return index + 1
                }
                index += 1
            }
            throw ProducktiveError("Cannot edit multiline quoted scalar.")
        }
        guard !["|", ">", "&", "*", "!"].contains(String(chars[0])) else { throw ProducktiveError("Use simple single-line scalars before editing.") }
        let comment = chars.indices.first { chars[$0] == "#" && ($0 == 0 || chars[$0 - 1] == " ") } ?? chars.count
        var end = comment
        while end > 0 && (chars[end - 1] == " " || chars[end - 1] == "\r") { end -= 1 }
        return end
    }
    public static func settingDeadlinePath(_ path: String, in text: String) throws -> String {
        let field = "deadlines_file: " + quote(path)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return field + "\n" }
        let root = try validateYAML(text)
        let opening = root.mark.flatMap { mark in
            text.components(separatedBy: "\n")[mark.line - 1].unicodeScalars.dropFirst(mark.column - 1).first
        }
        guard opening != "{" else { throw ProducktiveError("Use a block-style config mapping before choosing a file.") }
        var lines = text.components(separatedBy: "\n")
        if let pair = root.mapping?.first(where: { $0.0.string == "deadlines_file" }), let mark = pair.1.mark, let keyMark = pair.0.mark {
            guard pair.1.scalar != nil, mark.line == keyMark.line else { throw ProducktiveError("deadlines_file must be a single-line scalar.") }
            let index = mark.line - 1
            var scalars = Array(lines[index].unicodeScalars)
            let start = mark.column - 1
            let suffix = String(String.UnicodeScalarView(scalars.dropFirst(start)))
            let length = try scalarLength(suffix)
            scalars.replaceSubrange(start..<(start + length), with: quote(path).unicodeScalars)
            lines[index] = String(String.UnicodeScalarView(scalars))
        } else { lines.insert(field, at: 0) }
        return lines.joined(separator: "\n")
    }
    private func emptyListLine(_ line: String) throws -> String { try listLine(line, replacement: " []") }
    private func nonemptyListLine(_ line: String) throws -> String { try listLine(line, replacement: "") }
    private func listLine(_ line: String, replacement: String) throws -> String {
        guard let colon = line.firstIndex(of: ":") else { throw ProducktiveError("Cannot locate list header.") }
        let suffix = line[line.index(after: colon)...]
        let comment = suffix.firstIndex(of: "#").map { " " + suffix[$0...] } ?? ""
        return String(line[...colon]) + replacement + comment + (line.hasSuffix("\r") ? "\r" : "")
    }
    private func appending(block: [String], to section: String) throws -> [String] {
        let sequence = try list(section)
        var result = lines
        if sequence.isEmpty {
            let header = try keyLine(section)
            result[header] = try nonemptyListLine(result[header])
            result.insert(contentsOf: block, at: header + 1)
        } else {
            try requireBlock(root[section]!)
            guard let last = sequence.last else { return result }
            result.insert(contentsOf: block, at: try contentEnd(last))
        }
        return result
    }
}
