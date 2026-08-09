---
name: develop
description: "Route a feature, fix, or behavior change through the smallest useful flow: inspect, research, decide, implement, validate, and review."
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Develop

One invocation owns one requested outcome, not a batch of unrelated work.

## Route

- A question, audit, research request, or review stays read-only and stops after the answer.
- A hard bug, regression, flake, or performance problem starts with `diagnosing-bugs`.
- A clear feature or fix proceeds to implementation after its outcome, non-goals, test seam, and validation are understood.
- Use `handoff` only at an intentional session or context boundary.

## Understand before editing

Inspect repository evidence before asking the owner for facts. Prefer applicable instructions, source, tests, configuration, and authoritative documentation.

If a product, behavior, API, persistence, security, compatibility, scope, or architecture decision remains, apply `grilling`: give a recommendation and meaningful alternative, then wait for the owner's decision. Do not edit while a necessary decision is unresolved.

For clear one-session work, state a short contract covering the outcome, non-goals, test seam, and validation. For substantial or hard-to-reverse work, propose a durable contract only when it creates a real restart point or records a lasting decision.

## Implement and finish

Apply `implement`. Keep one writer per checkout and parallelize only read-only research or review. Use `tdd` when behavior has an honest public seam and repository policy permits test changes.

Run the agreed validation. Apply `code-review` for substantial, risky, security-sensitive, persistence-related, or long-running changes; do not turn a trivial verified change into ceremony.

Report the outcome, changed paths, observed validation, and residual risks directly.
