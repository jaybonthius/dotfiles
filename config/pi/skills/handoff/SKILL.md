---
name: handoff
description: Create a concise temporary handoff for a fresh session without duplicating durable artifacts.
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Handoff

Use only at an intentional context or session boundary.

Write a Markdown handoff in the operating system temporary directory. Include:

- the next session's goal;
- current Git or working-tree state and relevant paths;
- decisions made and decisions still needed;
- validation already observed;
- the smallest next action;
- useful project skills.

Reference existing contracts, research, architecture decision records, commits, and diffs rather than copying them. Redact secrets, credentials, personal data, and other sensitive information.

Do not launch another agent, create an execution ledger, mutate Git, or treat the handoff as a durable project document. Return the exact handoff path and a concise summary of the next action.
