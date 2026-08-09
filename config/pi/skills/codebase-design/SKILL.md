---
name: codebase-design
description: Evaluate a small, high-leverage interface using repository evidence.
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Codebase design

Inspect existing callers, callees, tests, module boundaries, and domain terms when evaluating a proposed interface. Use available structural codebase tools when helpful, and verify conclusions in source.

Evaluate:

- What observable behavior should callers receive through the seam?
- Which complexity belongs behind it?
- Does the interface improve leverage and locality, or move complexity into callers?
- Would deleting it concentrate complexity or only remove a pass-through?
- Is the abstraction supported by present behavior rather than imagined reuse?
- Does it preserve clear boundaries and accurate error ownership?

Prefer a small public seam, behavior-facing tests at that interface, and one coherent deep module over speculative flexibility.

For hard-to-reverse design, compare two or three materially different shapes and identify whether a decision record is warranted. Ordinary refactors do not require durable plans, review fanout, or decision records.
