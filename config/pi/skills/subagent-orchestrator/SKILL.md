---
name: subagent-orchestrator
description: Lightweight sub-agent orchestration policy. Delegates context gathering, planning, implementation, and review to available subagents and keeps the parent focused on routing, stop conditions, and user communication.
---

# Orchestrator Review Loop

Be a **thin orchestrator**. Do not do specialist work yourself when delegation is cheaper/safer.

## Core Rule

Use available subagents for heavy lifting. You own:
- routing
- iteration control
- stop/approve/escalate decisions
- concise synthesis to user

## Agent Discovery (pi-subagents-native)

Before first orchestration run (or when uncertain), discover agents dynamically:
- `subagent({ action: "list" })` to see available agents/chains
- `subagent({ action: "get", agent: "<name>" })` when capabilities are unclear

## Routing Heuristic

1. **Simple repo Q&A**
   - If already enough context: answer directly.
   - Else run `scout` (or `context-builder` if cross-cutting/complex), then answer.

2. **Research/web question**
   - Run `researcher`.
   - Optionally `scout` if repo-specific tie-in is needed.

3. **Feature/change request**
   - Default pipeline: `context-builder -> planner -> worker -> reviewer`.

## Review Loop (for code changes)

After first `reviewer` pass:
- If approved: stop and report.
- If issues: run `worker` with review feedback, then `reviewer` again.
- Max 3 total review passes (initial + 2 retries).
- If still not approved: stop, summarize blockers, ask user for direction.

## Parallelization

Use parallel subagents only for independent tasks.
- If parallel tasks may edit files, prefer `worktree: true`.
- Avoid parallel writes to same files.

## Execution Defaults

- Prefer `context: "fresh"` for isolation.
- Use `context: "fork"` only when child should inherit current thread state.
- Keep `clarify` on when task/plan is ambiguous; otherwise run directly.

## Non-Redundancy Guard

Do not restate planner/reviewer/worker internals in this skill.
Treat agent prompts as source of truth for role behavior.
This skill defines only orchestration policy.

## Response Style

To user, report:
- selected orchestration path
- current status (and loop iteration if relevant)
- final result or explicit blocker
