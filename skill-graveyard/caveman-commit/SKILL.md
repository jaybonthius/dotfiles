---
name: caveman-commit
description: >
  Ultra-compressed commit message generator. Uses module-first subjects:
  module[,module...]: brief description. Subject ≤72 characters; body only in
  exceptional cases. Use when user says "write a commit", "commit message",
  "generate commit", "/commit", or invokes /caveman-commit. Auto-triggers when staging changes.
---

Write commit messages terse and exact. Name affected modules, not change categories.

## Rules

**Subject line:**
- Format: `<module>[,<module>...]: <imperative summary>`.
- List every materially affected module once, separated by commas with no spaces.
- Use repository module/domain names. Hierarchical names such as `client/internal` are valid.
- Treat `docs`, `test`, `build`, and `ci` as modules when those areas are materially affected.
- Never add Conventional Commit categories such as `feat`, `fix`, `refactor`, or `chore` unless one is literally the repository module name.
- Keep the complete subject at or below 72 characters; shorter is better.
- Use imperative mood: "add", "fix", "preserve" — not "added", "adds", "adding".
- No capitalization after the colon unless required by a proper noun or exact identifier.
- No trailing period.

**Body:**
- Omit it when the subject is sufficient.
- Add one only for exceptional context: breaking changes, security fixes, data migrations, reverts, or non-obvious rationale.
- Explain why or migration impact; do not restate the diff.
- Wrap at 72 characters. Use `-` for bullets.
- Put issue references last: `Closes #42`, `Refs #17`.

**Never include:**
- "This commit does X", "I", "we", "now", or "currently".
- AI attribution or co-author trailers for an AI agent.
- Emoji unless the repository explicitly requires it.

## Examples

```text
client/internal: preserve retry state
```

```text
docs,client/internal: document retry ownership
```

```text
parser,terminal: retain incomplete UTF-8 input
```

Exceptional body:

```text
client,protocol: rename checkout endpoint

Breaking change: callers must migrate from /v1/orders to /v1/checkout
before 2026-06-01. The old route returns 410 after that date.

Closes #128
```

## Boundaries

Only generate the commit message. Do not stage, commit, amend, or add attribution. "stop caveman-commit" or "normal mode" reverts only the compressed presentation style; the global module-first commit format remains authoritative.
