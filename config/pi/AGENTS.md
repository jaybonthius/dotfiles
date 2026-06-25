# Global pi instructions

Always-on guidance loaded by pi (`~/.pi/agent/AGENTS.md`). Keep it short and
high-signal.

## Code exploration: prefer the knowledge graph over grep

For **structural** questions about a codebase, use the native **`cbm_*` tools**
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
