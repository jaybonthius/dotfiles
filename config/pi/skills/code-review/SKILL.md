---
name: code-review
description: Review a pinned change against its acceptance contract and repository standards.
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Code review

Pin and state the review target before reviewing:

- a supplied comparison: inspect that comparison plus requested working-tree changes;
- a supplied contract: inspect its associated current diff;
- no argument: inspect the current working-tree diff and untracked files.

Stop if there is no change or the comparison is ambiguous.

Read applicable repository instructions, the contract, the actual diff, and validation evidence. Review these axes:

1. **Acceptance** — missing, incorrect, unsafe, or out-of-scope behavior.
2. **Standards and architecture** — repository-backed conventions, correctness, simplicity, public boundaries, edge cases, security, resource handling, and regression risk.

For meaningful changes, independent read-only review may cover separate axes. Small, mechanical, well-validated changes need no review ceremony beyond direct inspection.

Verify findings and cite exact paths and line ranges. Classify verified findings as Blocker, Important, or Note. Distinguish defects from validation gaps and residual risks. Review is read-only unless separately authorized to fix issues.
