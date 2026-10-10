# File schema and editing

A UTF-8 Markdown file starts with `---`, version-1 YAML frontmatter, and `---`,
followed by arbitrary notes. Required root keys: `version: 1`, IANA `timezone`,
`countdown_decimals: 1`, `active`, and `archived`. Empty lists use `[]`.

Events require stable string `id`, nonempty `title`, and quoted `at`. Accept local
`YYYY-MM-DD`, `YYYY-MM-DDTHH:MM[:SS]`, or ISO timestamps with explicit offsets.
Date-only values mean midnight in the event's zone. Root `timezone` defaults in
the supplied examples to `America/Los_Angeles`; optional event `timezone` overrides
it. `ends_at` must be strictly later than `at`. Optional `source` is a string URL.

Optional `goals` is a list of stable-ID records with `title`, nonnegative finite
numeric `target`, `unit`, optional nonnegative finite numeric/null `current`, and
`status`: `active`, `achieved`, `paused`, or `abandoned`. All event and goal IDs are
unique across active and archived lists.

Archived records also require a nonempty `status` and an `archive_reason` string.
Imported historical/cancelled statuses are retained. App actions use `completed`
or `archived`. Completing events never updates goal statuses implicitly.

The core retains original source text and a Yams syntax tree. Edits replace only
selected single-line scalars or move complete record text. Unknown fields,
comments, nested goals, Unicode, Markdown notes, and wiki-links survive. Runtime
sorting does not rewrite other records. Rescheduling preserves IDs; if no new
end time is supplied, the original duration is retained.

Writes validate the full resulting document, use NSFileCoordinator for cooperating
editors, compare current bytes with the loaded revision immediately before commit,
keep a private pre-edit backup, sync a temporary sibling file, and atomically rename
it. A conflict aborts the write. Uncoordinated processes can still race in the tiny
interval between the final comparison and rename; normal coordinated editor saves
and observed intervening edits are protected. No claim of filesystem-wide locking
is made.

To preserve data safely, aliases, merge keys, duplicate YAML keys, and nesting over
40 levels are rejected. Editing flow lists/records or multiline edited scalar
fields is refused. Unknown multiline fields are retained as source text. Maximum
file size is 5 MB. Config path updates preserve unrelated settings and comments.
