---
name: producktive
description: Manage local Producktive deadlines and their linked goals. Use to add, reschedule, complete, or archive events, update manual progress, or inspect upcoming and overdue deadlines.
---

Use `~/.producktive/bin/producktive-cli` for validated, comment-preserving edits.
Commands automatically use the file selected in the app; do not ask the user for
its path or manually resolve the config. On first use, the app or CLI creates a
default document with two labelled fictional examples if no file or config exists.
Treat these as sample data, not the user's commitments; replace or remove them
when the user asks. Use `show` to read both active and
archived records and the Markdown notes before making changes. Use `path` only
when you need the resolved file location. Run `validate` before and after a change.
Use `--file /absolute/path/deadlines.md` only when the user requests a different
file for that command; `configure PATH` changes the app's selection persistently.
A missing or invalid selected file is an error; never fall back to another file.
Arguments containing spaces, JSON, or timestamps must be passed as literal
quoted arguments, without shell
interpolation of user text.

Commands:

- `list`, `show`, `path`, or `validate`
- `add-event '{"id":"fictional-review-2027-04-15","title":"Prototype review","at":"2027-04-15T10:00:00"}'`
- `add-goal EVENT_ID '{"id":"fictional-review-notes","title":"Write review notes","target":10,"unit":"notes","current":null,"status":"active"}'`
- `reschedule EVENT_ID '2027-04-16T10:00:00' ['2027-04-16T11:00:00']`
- `goal EVENT_ID GOAL_ID CURRENT_OR_null active|achieved|paused|abandoned`
- `complete EVENT_ID 'Explicit reason'` or `archive EVENT_ID 'Explicit reason'`

Completing or archiving moves the entire event, including goals, to `archived`.
It never implies that a goal was achieved. Rescheduling preserves stable IDs and,
when an end is omitted, preserves the original interval duration. Do not recreate
an event just to change its time. IDs must be unique across all events and goals.

Version 1 frontmatter requires `version: 1`, `timezone: "America/Los_Angeles"`,
`countdown_decimals: 1`, `active: [...]`, and `archived: [...]`. Events require
`id`, `title`, and a quoted `at`; optional fields include `ends_at`, `timezone`,
`source`, and `goals`. Goals require stable `id`, `title`, numeric `target`, `unit`,
optional numeric/null `current`, and `status`. Archived events require `status`
and `archive_reason`. Use `[]` for empty lists and block-style records for edits.

Use Pacific time by default; date-only input means midnight Pacific. Verify an
actual calendar time before replacing that default. Reject unknown IANA zones,
invalid dates, DST gaps/repeated local times, duplicate IDs, and reversed intervals.
Explicit UTC offsets can disambiguate repeated times. Countdown days are seconds
remaining divided by 86,400; overdue events stay active until explicitly resolved.

Preserve date uncertainty. Ask for the missing date or record the uncertainty in
notes; do not invent meetings, attendance, progress values, or achieved status.
Never commit a user's deadline file or config to a public repository.

If the CLI is unavailable, resolve `~/.producktive/config.yaml` first: its
`deadlines_file` overrides `~/.producktive/deadlines.md`; expand `~` and require
an absolute path. Read the full document before making changes.
If the CLI is unavailable or a change needs direct editing, preserve the Markdown
body, wiki-links, YAML comments, unknown fields, unrelated records, and IDs. Re-read
before committing, compare with the original bytes, keep a recoverable backup,
validate the candidate, then replace atomically. Stop and reload on a conflict.
Do not decode and re-encode the whole document. The CLI refuses unsupported flow
records, aliases, and multiline values for fields it edits instead of risking loss.
