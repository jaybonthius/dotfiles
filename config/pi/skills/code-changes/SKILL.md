---
name: code-changes
description: Format an explicit request for a file-by-file summary of source-code edits that are planned or already completed. Organize exact paths under Create, Modify, Rename, and Delete.
argument-hint: "[planned|completed]"
---

# Code Changes

Present a file inventory for a source-code change, not a general plan or session summary.

## Establish the evidence

An invocation without arguments refers to the active code-change scope in the current conversation. Infer its phase from context: before editing, summarize the intended changes; after editing, summarize the changes actually made. Ask for a target only when multiple change sets are plausible and context provides no clear referent.

- **Planned:** inspect the relevant code and approved scope before naming files. Describe only intended edits. Identify uncertainty instead of inventing a path or change.
- **Completed:** inspect the actual relevant diff and status. Do not rely on conversation memory when repository evidence is available. Ask for the comparison base when it is ambiguous.

Once invoked for a source-code change, include every materially affected supporting test, documentation, configuration, migration, and generated file.

## Format

Use these headings in this order, omitting empty sections:

```markdown
# Create

- `path/to/file`: Brief purpose.

# Modify

- `path/to/file`:
  - First distinct change.
  - Second distinct change.

# Rename

- `old/path` → `new/path`: Brief reason.

# Delete

- `path/to/file`: Brief reason for removal.
```

Rules:

- Use exact repository-relative paths in backticks.
- Give each path one bullet.
- Keep one coherent change on the path's first line. Use nested bullets only for multiple distinct changes.
- State what changes and why it matters; avoid generic phrases such as “update code.”
- For planned work, use present-tense imperatives such as “Add” and “Update.”
- For completed work, use past tense such as “Added” and “Updated.”
- Explain deletions and renames briefly.
- Add prose outside the sections only for material uncertainty or residual risk.
- If there are no applicable code changes, say so directly instead of printing empty headings.
