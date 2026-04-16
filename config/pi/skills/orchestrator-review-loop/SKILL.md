---
name: orchestrator-review-loop
description: Delegate-only orchestrator for sub-agent workflows. Uses planner/worker to produce plans or implementation, requires reviewer review after every artifact, and iterates on reviewer feedback until approved or max cycles.
---

# Orchestrator Review Loop

Use this skill when the user wants orchestration via sub-agents with mandatory review gates.

## Non-negotiable rules

1. You are the orchestrator only.
   - MUST NOT create plans, write code, or execute implementation directly.
   - MUST delegate planning/implementation work through `subagent`.
2. Every plan or implementation artifact MUST be reviewed by a `reviewer` agent.
3. Reviewer verdict gates progress:
   - `APPROVED` -> proceed
   - `CHANGES_REQUIRED` -> revise via producer agent, then re-review
4. Use bounded loops: `MAX_CYCLES = 3` per phase.
5. If delegation capability or required agents are unavailable, fail fast and report what is missing.

## Agent routing

Preferred roles:
- Planning producer: `planner`
- Implementation producer: `worker`
- Reviewer: `reviewer`

Fallbacks:
- Planning producer fallback: `worker`
- Implementation producer fallback: `worker`
- Reviewer fallback: none (reviewer is required)

## Preflight

Before starting:
1. Check available agents via `subagent` management list.
2. Confirm `reviewer` exists; if missing, stop with `PRECHECK_FAILED: REVIEWER_MISSING`.
3. Choose planning producer (`planner` else `worker`) and implementation producer (`worker`).

## Workflow

### Phase A: Plan loop (default first)

1. Delegate plan draft to planning producer.
2. Delegate review to `reviewer` with this required format:
   - `Verdict: APPROVED | CHANGES_REQUIRED`
   - `Issues: ...`
   - `Suggested fixes: ...`
3. If verdict is `CHANGES_REQUIRED`, delegate revision to planning producer with reviewer feedback.
4. Repeat review/revise until `APPROVED` or cycles reach `MAX_CYCLES`.
5. If max cycles reached without approval, stop with `PLAN_REVIEW_FAILED_MAX_CYCLES`.
6. Present the approved plan to the user.
7. If user asked for planning only, stop.

### Phase B: Implementation loop

1. Delegate implementation to `worker` using the approved plan.
2. Delegate review to `reviewer` with same verdict format.
3. If verdict is `CHANGES_REQUIRED`, delegate fixes to `worker` with reviewer feedback.
4. Repeat review/fix until `APPROVED` or cycles reach `MAX_CYCLES`.
5. If max cycles reached without approval, stop with `IMPLEMENTATION_REVIEW_FAILED_MAX_CYCLES`.
6. On approval, report completion and summarize outcomes.

## Output contract

For every cycle, report:
- phase (`plan` or `implementation`)
- cycle number
- producer and reviewer agent names
- reviewer verdict
- next action

Final status must be one of:
- `PLAN_APPROVED`
- `PLAN_REVIEW_FAILED_MAX_CYCLES`
- `IMPLEMENTATION_APPROVED`
- `IMPLEMENTATION_REVIEW_FAILED_MAX_CYCLES`
- `PRECHECK_FAILED: <reason>`
