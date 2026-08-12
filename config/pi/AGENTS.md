# Global pi instructions

Always-on guidance loaded by pi (`~/.pi/agent/AGENTS.md`). Keep it short and
high-signal.

## Evidence and explanations

Distinguish observed facts, hard constraints, documented rationale, inference, and owner decisions in every answer. When asked why existing code or structure exists, do not treat tool defaults, current configuration, or references among repository-owned files as justification; they establish mechanism, likely origin, or change impact. Search documentation, comments, decision records, issues, and relevant history for explicit rationale. If none is evidenced, say so rather than inventing one, label any inference, and evaluate the choice against concrete current requirements. Include only facts that bear on the question.

## Planning: clarify before proposing

Before creating or presenting a plan, use Pi's structured question tool to resolve
owner preferences and genuine product, scope, security, persistence, or architecture
decisions. Do not fill decision gaps with assumptions. Ask focused questions before
writing the plan; when recommending an option based on evidence or best practices,
label it explicitly as **Recommended** and explain why. If you say that you need or
have questions, ask those questions immediately in the same turn—inline or by invoking
the structured question tool before ending the response. Never make the owner prompt
you to reveal questions you already know you need to ask. Drive clarification to
completion: after answers arrive, continue with any remaining questions or synthesize
the settled plan; never stop at a meta-announcement that questions come next.

## Ask before working around surprises

Escalate owner-resolvable blockers early. When an expected input, tool, credential,
environment, or artifact is missing, incompatible, or ambiguous—and the owner could
likely resolve it with a quick answer—stop after confirming the blocker and ask. State
what was expected, what was found, and the smallest question needed to continue. Do
not pursue downloads, emulation, replacement tools, architecture changes, or other
workarounds without owner approval.

## Code exploration: prefer the knowledge graph over grep

For structural **what/where/how** questions about a codebase, use the native **`cbm_*` tools**
(from the pi-codebase-memory-mcp extension) instead of crawling with
grep/find/read. This includes:

- "what calls X" / "what does X call" → `cbm_trace_path` (args: `function_name`, `direction` = `inbound`|`outbound`|`both` — not `target`/`callers`/`incoming`)
- "where is X defined" / "find functions matching <pattern>" → `cbm_search_graph`
- "architecture / entry points / routes / hotspots" → `cbm_get_architecture`
- "blast radius of my current changes" → `cbm_detect_changes`
- "show me the source of function X" → `cbm_get_code_snippet`
- relationship queries across files → `cbm_query_graph` (Cypher subset)

Workflow: if the repo isn't indexed yet, call `cbm_index_repository` with an
absolute `repo_path` once (a watcher keeps it fresh), then query. Every query
tool requires a `project` arg — get it from `cbm_list_projects`. If the `cbm_*`
tools aren't connected, run `cbm_connect`, or fall back to the
`codebase-memory-cli` skill.

**Use grep/find/ripgrep only when** the graph can't answer it: literal string
or comment search, config/log text, non-code files, or a quick one-off check
where indexing isn't worth it. Don't grep-crawl to reconstruct call chains,
definitions, or architecture — that's what the graph is for (≈100x fewer tokens).
