---
name: conductor
description: Orchestrate authorized multi-stage repository work through visible Herdr worktrees and direct Pi subagents.
disable-model-invocation: true
---

# Conductor

Own the authorized body of work from the current top-level Pi session. Keep orchestration visible here and launch research, implementation, review, fix, integration, and artifact children directly; do not wrap the roadmap in another conductor or long-lived workflow subagent.

## Establish the contract

Inspect the supplied spec, issues, comments, repository state, applicable `AGENTS.md` or `CLAUDE.md`, `docs/agents/`, domain context, ADRs, tracker conventions, and validation entry points before delegating. Resolve every supplied source and artifact location to an absolute path.

Start with proportionality. For one coherent session-sized change, use one short inline contract, one `develop` outcome, and one delivery worktree. Create or update durable specs, tickets, research, ADRs, and receipts only when the owner requests them, an existing tracker requires them, or they preserve a material restart point or reusable decision. Use owner-supplied or repository-existing milestones and genuinely independent deliverables; do not manufacture milestones or artifacts to create orchestration checkpoints.

Identify the authorized outcomes, dependency order, non-goals, test seams, validation gates, target branch, writable repositories, artifact ownership, commit conventions, and stop condition. Trace every proposed outcome, changed path, artifact, dependency, and validation gate to the owner request or an applicable mandatory instruction. Research and child-agent advice may inform implementation choices but cannot create scope or acceptance requirements. Review against the original owner outcome and repository instructions, not only an agent-authored contract.

Use the repository's standard focused and full validation by default. Add performance, load, container, deployment, compatibility, or other specialized gates only when the owner or an existing mandatory acceptance condition requires them, or when they are necessary to prove the authorized change on that surface. Do not promote a speculative risk or an unrelated pre-existing failure into a gate.

Ask the owner only when evidence cannot settle a required product, behavior, API, persistence, security, compatibility, scope, or architecture decision. State the observed convention, concrete tradeoffs, and one recommendation before asking.

## Create visible lane worktrees

Use Herdr-created Git worktrees for writable product lanes so the owner can inspect them throughout execution.

1. Verify `HERDR_ENV=1`. If this session is not inside Herdr, report the blocker and ask the owner how to proceed; do not silently fall back to a hidden or primary checkout.
2. Read the installed command help before the first mutation: `herdr --help`, `herdr worktree`, and `herdr worktree create --help`. The installed CLI is authoritative.
3. Inspect existing worktrees with `herdr worktree list --cwd <repository-root>`. Reuse an exact clean target worktree when repository convention and branch ownership permit it; open an existing unopened checkout with `herdr worktree open`.
4. Otherwise create the authorized branch and checkout with `herdr worktree create`, specifying the repository cwd, branch, base ref, path or repository-established location, a useful label, and `--no-focus`. Parse the returned JSON for the actual workspace ID and checkout path.
5. Use one persistent Herdr worktree for the serial delivery or integration branch. Create additional Herdr worktrees only for genuinely independent parallel writers. Read-only researchers and reviewers do not need their own worktrees.
6. Keep overlay and artifact repositories in their established worktrees. A product checkout symlink does not transfer ownership; open the existing artifact worktree in Herdr when useful rather than recreating it.

Record a lane map before launching writers: repository, absolute checkout path, Herdr workspace ID, branch, base commit, owned paths, writable/read-only status, and commit destination. Never remove a Herdr worktree automatically. Return its workspace ID, path, branch, and cleanup disposition in the final receipt.

A Herdr worktree makes the checkout visible; a direct Pi subagent working there remains headless. Start a separate agent inside a Herdr pane only when the owner explicitly requests a visible agent terminal, because that creates another Pi session outside this session's subagent budget and lifecycle.

## Delegate directly

Before the first launch, list configured agents and use only executable, enabled roles. Remain the sole orchestrator and launch each child directly from this session.

For every child:

- Set `cwd` to the exact Herdr worktree or artifact-lane path.
- Set managed `worktree` isolation off; the Herdr checkout already provides the lane.
- Pass the absolute spec, issue, context, and artifact sources it needs.
- Pass the original owner outcome and only requirements whose provenance survives the contract check; never promote another child's proposal into authority by copying it into a later prompt.
- State the single outcome, non-goals, test seam, allowed paths, branch, base commit, commit boundary, validation contract, authority, and required handoff.
- Use fresh context when durable artifacts contain the contract. Fork only when inherited conversation reasoning is itself authoritative.
- Give implementation and fix children an explicit timeout suitable for the outcome. Keep the session-wide spawn budget available for reviews, fixes, and recovery.

Use foreground children when the next action depends on their result. Run independent research or distinct read-only reviews in parallel. After asynchronous launches, continue only independent work and consume results before crossing their dependency barrier.

## Execute one outcome at a time

For each ready outcome:

1. Confirm the delivery worktree is on the expected branch and commit and has no unexplained changes.
2. Complete only the prior-art research needed to resolve implementation facts. Save durable findings only when the contract's artifact criterion is met and use the repository-established location.
3. Launch one implementation worker as the sole writer for its checkout. Require coherent local commits, validation evidence, commit IDs, changed paths, and clean status.
4. Inspect the committed diff and evidence. Launch fresh read-only Standards and Spec reviewers with distinct contracts grounded in the original owner outcome. Add security, compatibility, performance, documentation, or workflow review only when the authorized outcome requires it.
5. Synthesize findings against their requirement provenance. Reject findings about unchanged or unrelated systems and findings that merely expand the agent-authored contract. Launch exactly one fix writer for accepted in-scope findings, then rerun affected reviews and validation.
6. Verify commit reachability, final diff, validation evidence, and clean lane status independently.
7. Report the outcome inline unless an existing tracker or owner-requested artifact must record it. When that tracker belongs to another worktree, commit its update through one artifact writer with product and artifact commits, changed paths, commands and results, review disposition, residual risks, and the next unblocked outcome.

Advance only after the outcome passes its gates and no owner decision remains.

## Parallel work and integration

Parallelize writers only when their outcomes are independent and each has a distinct Herdr worktree from the same verified base. Keep one writer per checkout.

Integrate accepted parallel commits into the persistent delivery worktree serially through one integration writer. Pass source commit IDs, worktree paths, review disposition, allowed paths, and validation requirements. Resolve mechanical conflicts there; escalate conflicts that require product or architecture judgment. Re-review the combined diff and rerun integration-level validation before advancing.

Preserve every worktree after integration so the owner can inspect it. Mark whether it is integrated, superseded, blocked, or still active; cleanup remains an explicit owner action.

## Authority and recovery

Local branches, Herdr worktrees, commits, and integration into the authorized delivery branch are part of execution. Pushes, merges into protected or upstream branches, publication, release, deployment, version changes, destructive cleanup, and scope expansion require explicit owner authority.

Escalate missing credentials, unavailable required tooling, unexplained workspace changes, unsafe integration, and failures of required validation that need scope change. A failure from an unnecessary or unrelated command is not a blocker: remove that command from the plan rather than expanding scope around it. Do not invent workarounds to owner-resolvable blockers.

If interrupted, return a recovery receipt naming completed outcomes, active direct children, Herdr workspace IDs and paths, branches and commits, artifact state, validation state, open decisions, and the exact next ready action.

## Completion

Finish only when every authorized outcome is complete or an explicit stop condition is reached. Report outcomes, product and artifact commits, Herdr workspaces and paths, validation, review disposition, residual risks, preserved worktrees, and anything requiring owner action.
