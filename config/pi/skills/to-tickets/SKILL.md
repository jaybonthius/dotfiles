---
name: to-tickets
description: Split an approved plan into owner-approved, independently executable vertical slices.
argument-hint: "<specification reference>"
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# To tickets

Use only when an approved plan needs multiple fresh implementation sessions or genuinely independent pieces. Do not use tickets for small linear changes.

Propose vertical slices that each:

- deliver observable behavior;
- name only real blockers;
- fit one implementation session;
- can be restarted independently.

Before writing ticket artifacts, enumerate every exact absolute output path and obtain explicit owner approval for the complete list. A directory, glob, naming pattern, implied sequence, or relative path is not sufficient approval. Write only the approved paths through the repository's authorized planning workflow.

Each ticket contains:

```markdown
# <NN> — <title>

Status: ready

## Delivers
## Blocked by
## Acceptance
## Validation
```

Work real blockers first. A ticket is a restartable implementation contract, not an agent claim, lock, manifest, progress database, research question, or list of source files. Do not create tickets for pieces that cannot independently deliver behavior. Give implementers the exact approved plan and ticket paths and follow the repository's single-writer policy.
