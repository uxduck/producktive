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

October 10 launch visibility fix (local version 0.1.1): the previous app process
was running, but manual launches only exposed the menu bar item. Manual startup
now opens a standalone deadline window; a reopen Apple event restores that same
window. Closing it keeps the app running. Panel visibility is tracked across both
the window and menu bar panel for countdown scheduling. Packaging can overwrite
dependency licenses copied read-only by an earlier build.

The universal fix was built, signed with the same Developer ID, installed in
`~/Applications/Producktive.app`, and restarted against the existing vault config.
The deadline CLI validated seven active and three archived records. The core
suite passed all 17 tests. Live launch/reopen and menu bar interaction still need
an unlocked Mac; UI automation reported that the screen was locked. This local
fix has not been notarized or published as a new release.

The updated native panel was rendered and visually inspected with the fictional
example in an isolated temporary data home. Titles, individual countdowns,
dates, goals, progress, archived disclosure, and footer controls were readable.
The panel now explicitly paints the native window background, including in
offscreen exports. The isolated app exited cleanly after the render check.

Three ten-second-spaced samples of the final installed process reported 0.0%
CPU, 34 MB memory, zero idle wakeups, and unchanged CPU time of 0.22 seconds.
The standalone deadline window was retained during this locked-screen sample.

Dropdown settings now support a menu bar title limit of 1–80 characters, including
the ellipsis, persisted in native app preferences. Live UI checks on the unlocked
Mac verified 5- and 10-character limits, immediate label preview updates, retained
full titles/countdowns, and a 10-character preference after quitting and relaunching.
The deadline list shrinks when settings expand so footer controls stay visible.
The existing 17 core tests and the signed universal build passed. The local app
was updated with this setting; notarization remains pending for the draft release.
