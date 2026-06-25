---
name: codebase-memory-cli
description: "FALLBACK only. Use the `codebase-memory-mcp` CLI for structural code queries (callers, callees, architecture, dead code, impact) ONLY when the native `cbm_*` tools (cbm_search_graph, cbm_trace_path, etc.) are not available/connected. If `cbm_*` tools exist, prefer them. Triggers on: who calls this function, what does X call, trace the call chain, find callers, dead code, architecture overview, when cbm_ tools are missing."
---

# Codebase Memory — Knowledge Graph (CLI fallback)

**Prefer the native `cbm_*` tools** (registered by the pi-codebase-memory-mcp
extension) when present. Use this CLI form only if those tools aren't connected.
The params below are identical to the `cbm_*` tool inputs.

Graph tools return precise structural results in ~500 tokens vs ~80K for grep.

**CLI form — invoke the binary directly via bash:**

```bash
codebase-memory-mcp cli <tool> '<json-args>'    # JSON → stdout, logs → stderr
```

Pipe through `| jq` to extract fields. The graph persists at `~/.cache/codebase-memory-mcp/`.

## First, always: get the project name

**Every tool below except `index_repository`/`list_projects` REQUIRES a `"project"` arg.**

```bash
codebase-memory-mcp cli list_projects '{}'                              # see indexed projects + names
codebase-memory-mcp cli index_repository '{"repo_path":"/ABS/PATH"}'    # index once if missing (absolute path; a watcher keeps it fresh)
```

Use the `name` from `list_projects` as `<PROJ>` in every call below.

## Decision matrix

| Question | CLI call |
|----------|----------|
| Who calls X? | `trace_path '{"project":"<PROJ>","function_name":"X","direction":"inbound"}'` |
| What does X call? | `trace_path '{"project":"<PROJ>","function_name":"X","direction":"outbound"}'` |
| Full call context | `trace_path '{"project":"<PROJ>","function_name":"X","direction":"both","depth":3}'` |
| Find by name pattern | `search_graph '{"project":"<PROJ>","name_pattern":".*X.*","label":"Function"}'` |
| Natural-language find | `search_graph '{"project":"<PROJ>","query":"update settings"}'` |
| Dead code | `search_graph '{"project":"<PROJ>","max_degree":0,"exclude_entry_points":true}'` |
| High fan-in/out | `search_graph '{"project":"<PROJ>","min_degree":10,"relationship":"CALLS"}'` |
| Read a symbol's source | `get_code_snippet '{"project":"<PROJ>","qualified_name":"<PROJ>.path.FuncName"}'` |
| Architecture overview | `get_architecture '{"project":"<PROJ>"}'` |
| Impact of local git changes | `detect_changes '{"project":"<PROJ>"}'` |
| Cross-service / multi-hop | `query_graph '{"project":"<PROJ>","query":"MATCH ... RETURN ... LIMIT 20"}'` |
| Text/string search | `search_code '{"project":"<PROJ>","pattern":"..."}'` or plain grep |

## Workflows

- **Explore:** `list_projects` → `get_graph_schema '{"project":"<PROJ>"}'` → `search_graph` → `get_code_snippet`
- **Trace:** `search_graph '{"project":"<PROJ>","name_pattern":".*FuncName.*"}'` (get exact name) → `trace_path` → `detect_changes`

## Exact params — do NOT invent fields (the failure mode is inventing `repo_path`/`node_type` on query tools; `repo_path` belongs ONLY to `index_repository`)

- `search_graph` — req `project`; opt `name_pattern`, `query`, `semantic_query`, `label`, `file_pattern`, `qn_pattern`, `min_degree`, `max_degree`, `exclude_entry_points`, `relationship`, `include_connected`, `limit`(200), `offset`
- `trace_path` — req `project`, `function_name`; opt `direction`(inbound|outbound|both), `depth`, `mode`(calls|data_flow|cross_service), `edge_types`, `risk_labels`, `include_tests`
- `get_code_snippet` — req `project`, `qualified_name`; opt `include_neighbors`
- `query_graph` — req `project`, `query`; opt `max_rows`
- `get_architecture` — req `project`; opt `aspects`
- `search_code` — req `project`, `pattern`; opt `mode`(compact|full|files), `path_filter`, `file_pattern`, `regex`, `context`, `limit`(10)
- `detect_changes` — req `project`; opt `base_branch`, `since`, `scope`, `depth`
- `index_repository` — req `repo_path`; opt `mode`, `persistence`, `target_projects`
- `index_status` / `delete_project` / `get_graph_schema` — req `project`
- `list_projects` — no args; `manage_adr` — req `project` (+`mode`,`content`,`sections`); `ingest_traces` — req `project`,`traces`

## Edge types

`CALLS`, `HTTP_CALLS`, `ASYNC_CALLS`, `IMPORTS`, `DEFINES`, `DEFINES_METHOD`, `HANDLES`, `IMPLEMENTS`, `OVERRIDE`, `USAGE`, `FILE_CHANGES_WITH`, `CONTAINS_FILE`, `CONTAINS_FOLDER`, `CONTAINS_PACKAGE`

## Cypher examples (read-only subset, for `query_graph` — always include a `LIMIT`)

```
MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path LIMIT 20
MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name LIMIT 50
MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence LIMIT 20
```

## Gotchas

1. **`project` is required** on every query tool — get it from `list_projects` first. Don't pass `repo_path` to query tools (that's only for `index_repository`).
2. `trace_path`/`get_code_snippet` need **exact** names — run `search_graph(name_pattern=...)` first to discover them.
3. `direction:"outbound"` misses cross-service callers — use `"both"`.
4. `search_graph` caps at `limit` (default 200); check `has_more` and page with `offset`. `search_code` defaults to 10.
5. The graph is strongest on real languages (TS/JS/Py/Go/Java/Rust/C/…); for **shell/config** repos call-graph data is sparse — falling back to grep there is correct.
