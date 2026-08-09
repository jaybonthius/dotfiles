---
name: implement
description: Implement an understood feature or fix through one writer, behavior tests, focused checks, and proportionate validation.
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Implement

Read the applicable repository instructions, supplied contract, relevant decisions or research, and affected code and tests. Treat an approved contract as authoritative. Stop when code reality exposes an unresolved product, API, persistence, security, architecture, compatibility, or scope decision.

## Work

Use one writer in one checkout. Make the smallest coherent vertical change and follow existing repository boundaries and conventions. Do not introduce speculative abstractions, dependencies, services, persistence, concurrency, or generation before the behavior requires them.

Apply `tdd` when behavior can be exercised through an honest public seam and repository policy permits test changes. Prefer production-facing boundaries over implementation details. Run focused checks while working, followed by proportionate broader validation.

## Verify

Derive validation from repository instructions and available tooling. Run checks that prove the changed behavior, formatting and static checks where applicable, relevant tests, and `git diff --check` when a diff exists.

Apply `code-review` when the diff is substantial, risky, security-sensitive, persistence-related, or produced across a long session.

Report the outcome, changed paths, tests added or updated, commands and observed results, review findings, generated or dependency changes when applicable, and residual risks.
