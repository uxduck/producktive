# Producktive

Deadline stress amplification tool to make you pro duck tive.

Put your deadlines in the Mac menu bar and watch the days disappear, one decimal
place at a time. Each deadline has goals, so you can see what needs doing as well
as how little time you've got left. Miss one and it stays there until you complete
or archive it.

Everything lives in a local Markdown file. Works on macOS 13 or later, on Apple
silicon and Intel.

## Install

Download the universal app from [Releases](https://github.com/UXDuck/producktive/releases),
unzip it, and move **Producktive.app** into Applications. Open it and choose your
Markdown deadline file.

Close the window and the countdown keeps running in the menu bar, without a Dock
icon. Open the app again to bring the window back. Enable **Launch at login** to
start it quietly in the menu bar when you log in.

On first launch, the app creates an empty `~/.producktive/deadlines.md` if you don't
already have a config or default file. Add deadlines with your agent, a text
editor, or the bundled CLI. Try [the example file](examples/deadlines.md) if you'd
like to see the format; its deadlines are fictional.

To build and install from source, use Xcode 15+ or Swift 5.9+:

```sh
swift test
scripts/build-app.sh
scripts/install.sh codex claude cursor
open "$HOME/Applications/Producktive.app"
```

Open `Package.swift` in Xcode to browse the core, app, CLI, and tests. The build
script makes a universal native `.app` without generating an Xcode project.
Yams 6.2.2 is the only package dependency, pinned in `Package.resolved`.

## Deadlines

![Native deadline panel with fictional records](docs/screenshot.png)

The menu bar shows your earliest unresolved active deadline. Overdue deadlines
come first and stay until you choose **Mark complete** or **Archive**. If two
deadlines have the same time, their stable IDs decide the order. Open the panel
to see each active deadline's full title, countdown, exact date and time, and goals.

Long titles are shortened in the menu bar. Under **Settings**, set **Title length**
to anything from 1 to 80 characters, including the ellipsis. It updates straight
away and remembers your choice. You can still see the countdown and full titles
in the dropdown.

The countdown divides the seconds left by 86,400 and shows one decimal place.
Once a deadline passes, it says “overdue”. Rounding means `0.0 days` can still be
upcoming, and a day stays 24 hours across daylight saving changes.

Dates default to midnight Pacific time. If you travel, the displayed local time
changes, and you can still see the original deadline time. Completing a deadline
keeps its goals' progress and status as they were; it doesn't mark the goals as
achieved.

Choose **Restore** under Archived to bring a completed or archived deadline back.
Its date, goals, and progress stay as they were.

See [the file schema](docs/schema.md) for the fields and how edits are saved safely.

## Choose a file

`~/.producktive/config.yaml` can contain:

```yaml
deadlines_file: "~/Documents/My deadlines.md"
```

The app reads deadlines from the file you select. Use an absolute path;
relative paths are rejected. **Choose file…** checks the file before saving your
choice. The app watches both files for changes, including saves where an editor
such as Obsidian replaces the file.

## Agent skill and CLI

Choose **Install agent skill** in the panel, then select Codex, Claude Code, or
Cursor. Your agent can add deadlines, reschedule them, and update goal progress
using the CLI at `~/.producktive/bin/producktive-cli`. The installer shows where
each skill goes and won't overwrite an unrelated skill.

| Agent | User skill directory | Official documentation |
|---|---|---|
| Codex | `~/.agents/skills/producktive` | [Codex skills](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills) |
| Claude Code | `~/.claude/skills/producktive` | [Claude skills](https://code.claude.com/docs/en/skills) |
| Cursor | `~/.cursor/skills/producktive` | [Cursor skills](https://cursor.com/docs/skills) |

These directories were checked on 9 October 2026. Codex and Cursor both read the
shared `.agents` directory, so installing for Codex can make the skill available
to Cursor too.

```sh
~/.producktive/bin/producktive-cli validate
~/.producktive/bin/producktive-cli list
~/.producktive/bin/producktive-cli reschedule review-id '2027-04-15T10:00:00'
~/.producktive/bin/producktive-cli goal review-id feedback-id 12 active
~/.producktive/bin/producktive-cli complete review-id 'Review held.'
```

Use `add-event` with a JSON event, or `add-goal` with an event ID and JSON goal.
Pass `--file /absolute/path/deadlines.md` to use a different file for any data
command. [The bundled skill](skills/producktive/SKILL.md) has more examples.

## Troubleshooting

If the countdown is hidden behind the camera notch or your menu bar is crowded,
open **Producktive.app** from Applications or Spotlight to see the deadline window.
You can also use **Open deadline window** in the panel.

If an edit breaks the file format, the app keeps showing the last valid version
with a red **Stale data** message and a menu bar warning. Fix the file or choose a
valid one. You can't make changes through the app while its data is stale. Empty
or missing files get their own messages. Use the refresh button to try loading again.

Times that occur twice or don't exist during daylight saving changes are rejected.
Use a verified time or an explicit UTC offset. IDs must be unique, time zones must
be recognised, and intervals must be valid. Archived records need both a status
and a reason. YAML aliases and merge keys aren't supported. The app can read
flow-style records, but you'll need to change them to block style before editing
them through the app.

If you get an edit conflict, reload and check the other editor's changes before
trying again. Each `deadlines.md.backup-UUID` file contains the original UTF-8 file
from before an edit. Keep or remove these yourself; the app doesn't delete them.

Install the app in Applications before enabling **Launch at login**. It uses Apple's
ServiceManagement registration, which may need approval in System Settings →
General → Login Items.

The app has no network access, analytics, or AI service. It doesn't run a separate
timer for every row either.

## Release and validation

[Validation notes](docs/validation.md) cover the tests and measured performance.
Builds use ad hoc signing by default, and CI artefacts aren't notarised. To make a
Developer ID release, set `SIGNING_IDENTITY` and a `NOTARY_PROFILE` stored with
`xcrun notarytool store-credentials`, then run `scripts/package-release.sh`.
You can also use `APPLE_API_KEY_PATH`, `APPLE_API_KEY` (the key ID), and
`APPLE_API_ISSUER` for App Store Connect API authentication. Keep credentials
outside the repository. The packaging script checks Apple's notarisation result
before stapling and verifies Gatekeeper acceptance. Check the release notes for
that release's signing and notarisation status.

MIT licensed. The public examples, tests, screenshots, and CI use fictional data.
