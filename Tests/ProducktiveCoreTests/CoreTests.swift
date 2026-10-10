import XCTest
@testable import ProducktiveCore

final class CoreTests: XCTestCase {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let fixture = """
    ---
    version: 1
    timezone: "America/Los_Angeles"
    countdown_decimals: 1
    extra_setting: "keep me" # untouched
    active:
      - id: "first"
        title: "Café 🦆 review" # title comment
        at: "2027-04-15T10:00:00" # time comment
        ends_at: "2027-04-15T11:00:00"
        extra: |
          unknown multiline text
          keep this too
        goals:
          - id: "feedback"
            title: "Collect feedback"
            target: 20
            unit: "responses"
            current: null # progress comment
            status: "active"
            extra_goal: "retain"
      - id: "second"
        title: "Launch"
        at: "2027-04-23"
    # archive section comment
    archived: [] # archive header comment
    ---

    # Notes
    Keep [[Project notes]] and 🦆 intact.
    """
    func date(_ string: String) throws -> Date { try Timestamp.resolve(string, in: zone) }
    func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("producktive-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    func testPacificDateDefaultsAndExplicitOffset() throws {
        XCTAssertEqual(try date("2027-04-23"), try date("2027-04-23T07:00:00Z"))
        XCTAssertEqual(try date("2026-11-01T01:30:00-07:00"), try date("2026-11-01T08:30:00Z"))
        XCTAssertThrowsError(try Timestamp.zone("Mars/Olympus"))
        XCTAssertThrowsError(try date("2026-02-30"))
        XCTAssertThrowsError(try date("2026-02-30T10:00:00Z"))
        XCTAssertThrowsError(try date("2026-02-29T10:00:00+05:30"))
        XCTAssertThrowsError(try date("2026-01-01T10:00:00+24:00"))
        XCTAssertEqual(try date("2026-11-01T01:30-07:00"), try date("2026-11-01T08:30:00Z"))
        XCTAssertEqual(try Timestamp.zone("UTC").secondsFromGMT(), 0)
        XCTAssertThrowsError(try date("2026-13-01"))
        XCTAssertThrowsError(try date("2026-01-01T25:00:00"))
    }
    func testDSTGapAndRepeatedTime() throws {
        XCTAssertThrowsError(try date("2026-03-08T02:30:00"))
        XCTAssertThrowsError(try date("2026-11-01T01:30:00"))
        let before = try date("2026-03-08")
        let after = try date("2026-03-09")
        XCTAssertEqual(after.timeIntervalSince(before), 23 * 3600)
        let engine = CountdownEngine(clock: { before })
        XCTAssertEqual(engine.text(for: after), "1.0 days")
        XCTAssertEqual(try date("2026-11-02").timeIntervalSince(date("2026-11-01")), 25 * 3600)
    }
    func testSelectionArrivalRoundingAndTravel() throws {
        let snapshot = try MarkdownDocument(fixture).snapshot
        let selected = snapshot.active[0]
        var now = selected.date.addingTimeInterval(-1)
        let engine = CountdownEngine(clock: { now })
        XCTAssertEqual(engine.selected(in: snapshot.active)?.id, "first")
        XCTAssertEqual(engine.text(for: selected.date), "0.0 days")
        XCTAssertFalse(engine.label(for: selected).contains("overdue"))
        XCTAssertEqual(engine.nextWakeup(events: snapshot.active, dropdownOpen: false), selected.date)
        now = selected.date
        XCTAssertTrue(engine.label(for: selected).contains("overdue"))
        now = snapshot.active[1].date.addingTimeInterval(1000)
        XCTAssertEqual(engine.selected(in: snapshot.active)?.id, "first")
        let travel = Timestamp.display(selected, localZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertTrue(travel.contains("(original)"))
        XCTAssertTrue(travel.contains("PDT"))
        XCTAssertEqual(selected.date, try date(selected.event.at))
        XCTAssertTrue(engine.label(for: selected, stale: true).hasPrefix("⚠︎"))
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        now = deadline.addingTimeInterval(-1.05 * 86400 - 1)
        XCTAssertEqual(engine.text(for: deadline), "1.1 days")
        let next = try XCTUnwrap(engine.nextWakeup(events: [ResolvedEvent(event: selected.event, date: deadline, endDate: nil, zone: zone)], dropdownOpen: false))
        XCTAssertEqual(next.timeIntervalSince(now), 1.01, accuracy: 0.02)
        now = next
        XCTAssertEqual(engine.text(for: deadline), "1.0 days")
    }
    func testOpenDropdownSchedulesEveryRowAndEmptyLists() throws {
        let snapshot = try MarkdownDocument(fixture).snapshot
        let now = snapshot.active[0].date.addingTimeInterval(-86400)
        let engine = CountdownEngine(clock: { now })
        XCTAssertLessThanOrEqual(try XCTUnwrap(engine.nextWakeup(events: snapshot.active, dropdownOpen: true)), try XCTUnwrap(engine.nextWakeup(events: snapshot.active, dropdownOpen: false)))
        XCTAssertNil(engine.selected(in: [])); XCTAssertNil(engine.nextWakeup(events: [], dropdownOpen: true))
        XCTAssertEqual(engine.label(for: nil), "Producktive · No deadlines")
        var records = snapshot.data
        records.active[1].at = records.active[0].at
        records.active[1].id = "aaa"
        XCTAssertEqual(try Snapshot(data: records).active[0].id, "aaa")
    }
    func testArchivePreservesGoalsNotesUnknownFieldsAndComments() throws {
        let original = try MarkdownDocument(fixture)
        let archived = try original.editing(.archive(id: "first", status: "completed", reason: "Review held."))
        XCTAssertEqual(archived.snapshot.active.map(\.id), ["second"])
        XCTAssertEqual(archived.snapshot.archived[0].event.goals, original.snapshot.active[0].event.goals)
        XCTAssertEqual(archived.snapshot.archived[0].event.status, "completed")
        for marker in ["# title comment", "# time comment", "# progress comment", "# archive section comment", "# archive header comment", "extra_setting: \"keep me\" # untouched", "extra_goal: \"retain\"", "unknown multiline text\n      keep this too", "Keep [[Project notes]] and 🦆 intact."] {
            XCTAssertTrue(archived.text.contains(marker), marker)
        }
        let empty = try archived.editing(.archive(id: "second", status: "archived", reason: "No longer needed."))
        XCTAssertTrue(empty.text.contains("active: []"))
        XCTAssertTrue(empty.snapshot.active.isEmpty)
        XCTAssertEqual(empty.snapshot.archived.count, 2)
    }
    func testRestorePreservesRecordAndSupportsRearchiving() throws {
        let original = try MarkdownDocument(fixture)
        let archived = try original.editing(.archive(id: "first", status: "completed", reason: "Accidental click."))
        let restored = try archived.editing(.restore(id: "first"))
        XCTAssertEqual(restored.snapshot.active.map(\.id), ["first", "second"])
        XCTAssertTrue(restored.snapshot.archived.isEmpty)
        XCTAssertEqual(restored.snapshot.active[0].event, original.snapshot.active[0].event)
        XCTAssertEqual(restored.snapshot.active[0].date, original.snapshot.active[0].date)
        for marker in ["# title comment", "# time comment", "# progress comment", "# archive section comment", "# archive header comment", "extra_setting: \"keep me\" # untouched", "extra_goal: \"retain\"", "unknown multiline text\n      keep this too", "Keep [[Project notes]] and 🦆 intact."] {
            XCTAssertTrue(restored.text.contains(marker), marker)
        }
        XCTAssertThrowsError(try restored.editing(.restore(id: "first")))
        let archivedAgain = try restored.editing(.archive(id: "first", status: "archived", reason: "Later."))
        XCTAssertEqual(archivedAgain.snapshot.archived[0].event.goals, original.snapshot.active[0].event.goals)
    }
    func testRestoreIntoEmptyActivePreservesArchiveMetadataComments() throws {
        let text = """
        ---
        version: 1
        timezone: America/Los_Angeles
        countdown_decimals: 1
        archived:
          - status: completed # status comment
            archive_reason: "Accidental # click" # reason comment
            id: restored
            title: Restored deadline
            at: "2020-01-01"
        active: [] # active header
        ---
        Notes remain.
        """
        let restored = try MarkdownDocument(text).editing(.restore(id: "restored"))
        XCTAssertTrue(restored.snapshot.archived.isEmpty)
        XCTAssertEqual(restored.snapshot.active.map(\.id), ["restored"])
        XCTAssertNil(restored.snapshot.active[0].event.status)
        XCTAssertNil(restored.snapshot.active[0].event.archive_reason)
        for marker in ["# status comment", "# reason comment", "# active header", "Notes remain."] {
            XCTAssertTrue(restored.text.contains(marker), marker)
        }
        let engine = CountdownEngine(clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        XCTAssertTrue(engine.label(for: restored.snapshot.active[0]).contains("overdue"))
        XCTAssertNoThrow(try restored.editing(.reschedule(id: "restored", at: "2027-01-01", endsAt: nil)))
        let multiline = text.replacingOccurrences(of: "archive_reason: \"Accidental # click\" # reason comment", with: "archive_reason: |\n      Accidental click")
        XCTAssertThrowsError(try MarkdownDocument(multiline).editing(.restore(id: "restored")))
    }
    func testReschedulingAndGoalEdits() throws {
        let original = try MarkdownDocument(fixture)
        let updated = try original.editing(.reschedule(id: "first", at: "2027-05-01T10:00:00", endsAt: nil))
        XCTAssertEqual(updated.snapshot.active.map(\.id), ["second", "first"])
        let event = updated.snapshot.active[1]
        XCTAssertEqual(try XCTUnwrap(event.endDate).timeIntervalSince(event.date), 3600)
        XCTAssertTrue(updated.text.contains("# time comment"))
        let goal = try updated.editing(.goal(eventID: "first", goalID: "feedback", current: 12, status: "active"))
        XCTAssertEqual(goal.snapshot.active[1].event.goals?[0].current, 12)
        XCTAssertTrue(goal.text.contains("# progress comment"))
        XCTAssertTrue(goal.text.contains("extra_goal: \"retain\""))
        XCTAssertThrowsError(try goal.editing(.goal(eventID: "first", goalID: "feedback", current: -1, status: "active")))
    }
    func testAddEventAndGoalPreservesUnrelatedData() throws {
        let original = try MarkdownDocument(fixture)
        let event = try JSONDecoder().decode(Event.self, from: Data(#"{"id":"new","title":"New event","at":"2027-05-02"}"#.utf8))
        let goal = try JSONDecoder().decode(Goal.self, from: Data(#"{"id":"new-goal","title":"New goal","target":10,"unit":"notes","status":"active"}"#.utf8))
        let added = try original.editing(.addEvent(event)).editing(.addGoal(eventID: "new", goal: goal))
        XCTAssertEqual(added.snapshot.active.count, 3)
        XCTAssertEqual(added.snapshot.active.last?.event.goals?.first?.id, "new-goal")
        XCTAssertTrue(added.text.contains("# title comment"))
        XCTAssertThrowsError(try added.editing(.addEvent(event)))
        let existing = try original.editing(.addGoal(eventID: "first", goal: goal))
        XCTAssertEqual(existing.snapshot.active[0].event.goals?.count, 2)
    }
    func testMalformedAndDuplicateData() throws {
        XCTAssertThrowsError(try MarkdownDocument("No frontmatter"))
        XCTAssertThrowsError(try MarkdownDocument(fixture.replacingOccurrences(of: "id: \"second\"", with: "id: \"first\"")))
        XCTAssertThrowsError(try MarkdownDocument(fixture.replacingOccurrences(of: "id: \"feedback\"", with: "id: \"first\"")))
        XCTAssertThrowsError(try MarkdownDocument(fixture.replacingOccurrences(of: "2027-04-15T11:00:00", with: "2027-04-15T09:00:00")))
        XCTAssertThrowsError(try MarkdownDocument(fixture.replacingOccurrences(of: "version: 1", with: "version: 1\nversion: 2")))
        XCTAssertThrowsError(try MarkdownDocument(fixture.replacingOccurrences(of: "America/Los_Angeles", with: "Unknown/Zone")))
        XCTAssertThrowsError(try MarkdownDocument(fixture.replacingOccurrences(of: "countdown_decimals: 1", with: "countdown_decimals: 2")))
    }
    func testFileStoreBackupAndConcurrentEdits() throws {
        let directory = try temporary()
        let url = directory.appendingPathComponent("deadlines.md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        let original = try FileRevision(url: url)
        let revised = try FileStore.apply(.archive(id: "first", status: "completed", reason: "Done"), to: original)
        XCTAssertEqual(revised.document.snapshot.active.count, 1)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.path.contains("backup-") })
        XCTAssertEqual(try Data(contentsOf: backup), original.bytes)
        XCTAssertThrowsError(try FileStore.apply(.reschedule(id: "second", at: "2027-06-01", endsAt: nil), to: original))
        let outsideEdit = revised.document.text + "\nEdited elsewhere\n"
        XCTAssertThrowsError(try FileStore.apply(.reschedule(id: "second", at: "2027-06-01", endsAt: nil), to: revised, beforeCommit: {
            try outsideEdit.write(to: url, atomically: true, encoding: .utf8)
        }))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), outsideEdit)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try FileStore.apply(.archive(id: "second", status: "archived", reason: "Done"), to: revised))
    }
    func testConfigOverrideResolutionAndPreservation() throws {
        let home = try temporary()
        let directory = Config.directory(home: home)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = home.appendingPathComponent("custom.md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        let config = directory.appendingPathComponent("config.yaml")
        try "# config comment\nother_setting: yes\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(try Config.read(home: home).deadlinesURL(home: home).path, directory.appendingPathComponent("deadlines.md").path)
        try FileStore.chooseDeadlineFile(url, home: home)
        XCTAssertEqual(try Config.read(home: home).deadlinesURL(home: home), url)
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8).contains("other_setting: yes"))
        XCTAssertEqual(try Config(deadlines_file: "~/custom.md").deadlinesURL(home: home), url)
        XCTAssertThrowsError(try Config(deadlines_file: "relative.md").deadlinesURL(home: home))
    }
    func testSkillInstallAndConflictPreflight() throws {
        let home = try temporary(), resources = try temporary()
        let skill = resources.appendingPathComponent("skills/producktive")
        let bin = resources.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "---\nname: producktive\ndescription: Example\n---\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "binary fixture".write(to: bin.appendingPathComponent("producktive-cli"), atomically: true, encoding: .utf8)
        let messages = try SkillInstaller.install(agents: [.codex, .claude, .cursor], resources: resources, home: home)
        XCTAssertEqual(messages.count, 4)
        for agent in Agent.allCases { XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(agent.directory).appendingPathComponent("producktive/SKILL.md").path)) }
        XCTAssertNoThrow(try SkillInstaller.install(agents: [.codex], resources: resources, home: home))
        let different = try temporary()
        let destination = different.appendingPathComponent(".cursor/skills/producktive")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "User skill".write(to: destination.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try SkillInstaller.install(agents: [.codex, .cursor], resources: resources, home: different))
        XCTAssertFalse(FileManager.default.fileExists(atPath: different.appendingPathComponent(".agents/skills/producktive").path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("SKILL.md"), encoding: .utf8), "User skill")
    }
    func testIndentedDelimiterInsideUnknownLiteralIsPreserved() throws {
        let literal = "literal_note: |\n  ---\n  Keep [[Notes]] here\n"
        let source = fixture.replacingOccurrences(of: "extra_setting:", with: literal + "extra_setting:")
        let original = try MarkdownDocument(source)
        let changed = try original.editing(.archive(id: "first", status: "completed", reason: "Done"))
        XCTAssertTrue(changed.text.contains(literal))
        XCTAssertEqual(changed.snapshot.active.count, 1)
    }
    func testArchivePreservesBlankLinesInTrailingUnknownBlock() throws {
        let extra = "    trailing_note: |\n      First paragraph\n\n      Second paragraph\n"
        let source = fixture.replacingOccurrences(of: "  - id: \"second\"", with: extra + "  - id: \"second\"")
        let original = try MarkdownDocument(source)
        let changed = try original.editing(.archive(id: "first", status: "archived", reason: "No longer needed"))
        XCTAssertTrue(changed.text.contains(extra))
        XCTAssertEqual(changed.snapshot.archived[0].event.goals, original.snapshot.active[0].event.goals)
        XCTAssertTrue(changed.text.hasSuffix("Keep [[Project notes]] and 🦆 intact."))
    }
    func testFlowRecordEditsAreRefused() throws {
        let flow = "---\nversion: 1\ntimezone: America/Los_Angeles\ncountdown_decimals: 1\nactive: [{id: a, title: A, at: \"2027-01-01\"}]\narchived: []\n---\nNotes\n"
        let document = try MarkdownDocument(flow)
        XCTAssertThrowsError(try document.editing(.archive(id: "a", status: "completed", reason: "Done")))
        XCTAssertThrowsError(try document.editing(.reschedule(id: "a", at: "2027-02-01", endsAt: nil)))
    }
    func testFirstRunAndConfigQuotedPathComments() throws {
        let home = try temporary()
        try FileStore.bootstrap(home: home)
        let url = try Config().deadlinesURL(home: home)
        XCTAssertTrue(try FileRevision(url: url).document.snapshot.active.isEmpty)
        try (fixture + "\nPersonal notes\n").write(to: url, atomically: true, encoding: .utf8)
        try FileStore.bootstrap(home: home)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("Personal notes"))
        let config = "# first comment\ndeadlines_file: \"/tmp/old # file.md\" # path comment\nother: keep\n"
        let changed = try MarkdownDocument.settingDeadlinePath("/tmp/new # name.md", in: config)
        XCTAssertTrue(changed.contains("# path comment"))
        XCTAssertTrue(changed.contains("other: keep"))
        XCTAssertFalse(changed.contains("old # file.md"))
        XCTAssertThrowsError(try MarkdownDocument.settingDeadlinePath("/tmp/new.md", in: "{deadlines_file: '/tmp/old.md', other: keep}"))
    }
    func testWatcherRecoversAfterDeletionAndDirectoryReplacement() throws {
        let parent = try temporary()
        let directory = parent.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("deadlines.md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        let removed = expectation(description: "deletion observed"), recreated = expectation(description: "recreation observed")
        var sawDeletion = false
        let watcher = FileWatcher {
            let exists = FileManager.default.fileExists(atPath: url.path)
            if !exists && !sawDeletion { sawDeletion = true; removed.fulfill() }
            else if exists && sawDeletion { recreated.fulfill() }
        }
        watcher.watch([url])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { try? FileManager.default.removeItem(at: directory) }
        wait(for: [removed], timeout: 4)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        wait(for: [recreated], timeout: 4)
        withExtendedLifetime(watcher) {}
    }
    func testWatcherObservesAtomicReplacementAndReattaches() throws {
        let directory = try temporary(), url = directory.appendingPathComponent("deadlines.md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        let first = expectation(description: "first atomic save"), second = expectation(description: "second atomic save")
        var count = 0
        let watcher = FileWatcher {
            count += 1
            if count == 1 { first.fulfill() }
            if count == 2 { second.fulfill() }
        }
        watcher.watch([url])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { try? (self.fixture + "\nFirst\n").write(to: url, atomically: true, encoding: .utf8) }
        wait(for: [first], timeout: 4)
        try (fixture + "\nSecond\n").write(to: url, atomically: true, encoding: .utf8)
        wait(for: [second], timeout: 4)
        withExtendedLifetime(watcher) {}
    }
}
