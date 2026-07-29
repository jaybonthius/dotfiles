# ADR 0001 — No per-transaction state; `category` is the only durable signal

Date: 2026-07-08
Status: Accepted

## Context

The `actual-ai` container project we replaced tracks per-transaction state by
writing note-tags (`#actual-ai` applied, `#actual-ai-miss` skipped) and refusing
to re-classify tagged transactions. That lets it avoid re-surfacing skipped
transactions forever. We considered three options for our skill:
watermark + note-tags, note-tags alone, waterfall alone, or no extra state.

## Decision

Carry **no** extra per-transaction state. The Transaction's existing
`category` field is the only durable signal that it has been handled:
`category IS NULL` → Candidate; `category` non-null → not a Candidate. A simple
24h lookback window gates the query. No watermark file, no note-tags, no DB.

## Consequences

- Skipped Candidates may re-surface on later Runs while inside the 24h window
  ("Aging Out"). Accepted: with daily cadence + 24h window, a skipped txn
  surfaces at most ~once more, then ages out. Not worth a state machine.
- The skill's review logic is drastically simpler and stateless: one GET pass,
  filter, reason, PATCH. Nothing to corrupt, nothing to migrate.
- Re-running the skill manually (or a duplicate cron fire) is idempotent for
  already-categorized transactions (they're filtered out by `category
  IS NULL`) and harmless for not-yet-categorized ones.

## Why this is a real trade-off

- **Hard to reverse:** no, but it shapes every downstream assumption in the
  skill. If we later need "skip forever," we'd add note-tags and a migration.
- **Surprising without context:** a future reader expects skipped txns to be
  remembered; they aren't. Worth recording why.
- **Real alternatives:** the actual-ai container's tag scheme was a live
  alternative we explicitly rejected for simplicity.