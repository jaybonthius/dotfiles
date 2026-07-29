# Actual Categorize — Domain Glossary

## Work units

A **Run** executes once per day (~8am ET) via system crontab. One Run ends when
the Crone has finished posting (its Turn is resolved or there were no
Candidates in the lookback window).

A **Candidate** is a single uncategorized Transaction eligible for review in a
Run. A Transaction becomes a Candidate when, and only when, its `category`
field is `null` and it sits in an open Account (closed accounts are excluded;
off-budget accounts are INCLUDED) with `date` inside the lookback window. The
only durable signal that a Transaction is no longer a Candidate is a non-null
`category` — there is no separate "queued"/"proposed" status, no watermark
file, and no per-Transaction skip-marker.

The **Run window** is the date range the Run uses to fetch Transactions from
the Actual Budget HTTP API.

- Default cron/manual mode: last 24h-ish, implemented as
  `since_date = today minus one day` and no `until_date`.
- Explicit backfill mode: exact date, implemented as
  `since_date = YYYY-MM-DD` and `until_date = YYYY-MM-DD`.

A **skipped** Candidate (the user declined to categorize it) may re-surface on
a later Run while it remains inside the Run window and `category` stays null;
that is accepted as **Aging Out**.

## Roles

The **Crone** is the AI agent the cron uses to create each Budget AI thread
(fine, "Crone" — she watches the books). A Crone Run is self-contained: the
bash script passes no transactions to the AI; the Crone re-fetches its own
view of the budget through the HTTP API.

The **Gate** is the bash-layer check that decides whether an AI Crane should be
spawned at all. It counts Candidates over the last 24h; zero → post an
"all caught up" thread with no AI, >0 → spawn the Crone.

## Actions

**Categorize**: the Crone asserts a category for a Candidate using the
Existing Categories as the universe of valid choices, reasoning per
transaction (web_search for obscure merchants). The Crone self-splits each
batch into **Confident** (apply immediately, report in the message) and
**Unsure** (do not apply, present for the user's call).

**Approve**: the user accepts a proposed category, which triggers a PATCH of
the Candidate's `category`. The Transaction is no longer a Candidate (category
now non-null).

**Skip**: the user declines to categorize a Candidate this Run. Skip does NOT
write the category, so the Candidate remains a Candidate and may re-surface
until it ages out of the window or gets a category.

**New Category** creation: when no Existing Category fits, the Crone may
propose a new category in its message, but creating it (POST `/categories`) is
always **gated by explicit user approval** even if the Crone is otherwise
Confident. Schema mutations are never applied silently.

## Channels

An **Account** in Actual Budget. Scanned accounts = all open accounts
(`closed != true`), including off-budget (credit cards being paid down,
savings, HSA, loans). Closed accounts are excluded.

The **Existing Categories** are the universe of valid `category` ids the Crone
may assign. A **New Category** is a category that does not yet exist.

The **Budget AI forum** (`1524501403156873497` in Jay's server
`1519098938958024704`) is the Discord forum where one thread is created per
Run. The Crone chooses the forum title and starter message through the shared
`create-piscord-thread` script. Each thread is a fresh Pi session — the Crone
has no memory across Runs.

## Out of scope (deliberate)

- No `pending_review` / `proposed` status. Only `category` is durable.
- No `#actual-ai`/`#actual-ai-miss` note-tags (unlike the actual-ai container).
- No SQLite jobs.db / bounded queue. The window bounds the batch.
- No bank reconciliation, no sync triggering, no balance checks. The HTTP API
  is read for transactions/categories and written for category assignments +
  new categories only.