---
version: 1
timezone: "America/Los_Angeles"
countdown_decimals: 1
# Fictional records; replace these with your own dates and goals.
active:
  - id: "workshop-2027-04-15"
    title: "Design workshop"
    at: "2027-04-15T10:00:00"
    ends_at: "2027-04-15T11:00:00"
    source: "https://example.com/workshop"
    goals:
      - id: "workshop-feedback"
        title: "Collect feedback from participants"
        target: 20
        unit: "responses"
        current: 8
        status: "active"
  - id: "launch-2027-04-23"
    title: "Launch the garden journal"
    at: "2027-04-23"
    goals:
      - id: "journal-readers"
        title: "Reach the first readers"
        target: 50
        unit: "readers"
        current: null
        status: "active"
archived:
  - id: "prototype-2027-03-01"
    title: "Prototype review"
    at: "2027-03-01T14:00:00"
    status: "completed"
    archive_reason: "Review held; feedback goal remains unfinished."
    goals:
      - id: "prototype-notes"
        title: "Write review notes"
        target: 10
        unit: "notes"
        current: 6
        status: "active"
---

# Deadline notes

Fictional example. Wiki-links such as [[Project notes]] and ordinary Markdown
remain intact when an event is completed, archived, or rescheduled.
