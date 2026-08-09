---
name: domain-modeling
description: Clarify durable domain terminology and hard-to-reverse decisions.
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Domain modeling

This workflow is read-only by default. Read relevant domain documentation, architecture decision records, plans, and repository usage when available. Proceed silently when such documents are absent. Challenge ambiguous or overloaded terms against concrete scenarios, then return proposed glossary or decision language directly.

Recommend documenting a settled term only when it will clarify future discussion, APIs, code, or tests. Keep the proposal a glossary or decision record, not a task plan, progress report, or implementation guide.

Write a domain artifact only through the repository's authorized workflow and only to an exact owner-approved path. When it changes behavior or governance, apply the repository's planning, review, approval, and single-writer gates.

Offer an architecture decision record only when all are true:

1. Reversing the choice would be costly.
2. The result is surprising without its trade-off.
3. Materially different alternatives were considered.

Otherwise keep the decision in the current contract or conversation. Surface conflicts with an existing decision record rather than silently overriding it.
