# Validation record

Initial implementation validated on a real Apple silicon Mac, October 9–10, 2026.

The final core suite passed 17 tests with no failures. It covers local Pacific and offset timestamps, midnight defaults,
invalid dates/zones, DST gaps and repeated times, 23/25-hour DST days, arrival,
rounding boundaries, multiple overdue deadlines, ties, empty and archived lists,
travel display, duplicate IDs and keys, invalid intervals, safe archive/reschedule
and goal writes, notes/comments/unknown fields, concurrent writes, recoverable
backups, config overrides, first-run setup, skill conflicts and managed upgrades,
atomic file replacement, deletion and directory recreation, and refused flow edits.

The personal vault file was parsed locally: seven active and three archived
records. It was not copied into the repository, tests, examples, or CI.

Native UI checks used an isolated home with fictional data. Verified all-row
countdowns, full titles, date/time, linked goals, progress editor (8 → 12), moving
an event to Archived while retaining its goal at 12/20 with status active, and
persistent stale-data text with disabled mutation controls after a malformed edit.
Restoring valid data recovers automatically through the file watcher.

A developer preview uses the same native panel without requiring menu-bar UI
automation. To capture a fictional screenshot, prepare a disposable data home and
launch with `--data-home /absolute/test/home --preview-panel --export-panel
/absolute/output.png`. Export requires the isolated-home flag and never runs on a
normal application launch.

One timer schedules the next displayed tenth-day rounding boundary or exact
arrival. Window visibility chooses the relevant rows. Wake/clock/timezone
notifications refresh the display. Unchanged file bytes skip parsing and sorting.
No per-event timer, per-second polling, analytics, or background network service is
used. `scripts/measure-idle.sh PID` records CPU, memory, idle wakeups, and CPU time
for three samples ten seconds apart.

The installed universal release was measured on Apple silicon, macOS 27.0.1,
with the panel closed and seven active/three archived records. Samples taken ten
seconds apart reported 0.0% CPU, 19 MB memory, three threads, zero idle wakeups,
and unchanged cumulative CPU time of 0.20 seconds. This is a short idle sample;
an extended idle soak remains a manual check.

Actual logout/login, forced system sleep/wake, and testing on an Intel Mac and
macOS 13 remain manual checks. The universal executable was inspected for both
arm64 and x86_64 slices with minimum macOS 13.0. Login registration reported enabled
on this Mac; a new login session was not forced during implementation.

The release is signed with Developer ID Application: DUCKTYPE LIMITED
(DXY3Q8PYGP), hardened runtime enabled, with Apple's secure timestamp. Apple
accepted notarization, and the ticket was stapled before repackaging the archive.
Stapler validation succeeded; Gatekeeper assessment returned accepted with source
`Notarized Developer ID`. This initial release is a prerelease while the manual
checks above remain outstanding. The installed app and managed agent CLI were
updated to this build.
