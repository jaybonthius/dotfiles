---
name: to-spec
description: Turn settled evidence and decisions into one concise behavioral plan with explicit approval gates.
argument-hint: "<idea or evidence summary>"
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# To spec

Use only after research and the decisions needed to define the proposal have settled. Those decisions are inputs, not approval of the resulting plan. Do not reopen discovery.

Follow the repository's configured planning or delegation workflow. Before persisting the plan, obtain an explicitly assigned exact absolute output path. Relative delegated outputs are forbidden because Pi may namespace them outside the intended repository artifact directory.

Create one concise, behavioral, durable plan containing:

```markdown
# <title>

Status: draft
Oracle approval: pending
Owner approval: pending

## Goal
## Scope
## Non-goals
## Decisions
## Acceptance and test seam
## Validation
## Risks and open questions
```

Omit file-by-file instructions, progress logs, transcripts, exhaustive stories, and speculative future work. The status and approval fields record the current contract gate, not an execution ledger.

Have the configured Oracle review the exact draft read-only. Return findings through the repository's authorized planner and repeat review after substantive revisions. Record Oracle approval only after an actual approving verdict.

Present the exact Oracle-approved plan to the owner and wait for explicit implementation approval. The agent cannot infer or grant that approval. A substantive revision resets both approval gates.

Stop after presenting the completed plan unless implementation was explicitly requested as part of the workflow. Dispatch implementation only with the exact plan path and both recorded approval references.
