# caveman-commit

Terse, module-first commit messages.

## What it does

Generates subjects in this format:

```text
module[,module...]: brief imperative description
```

Every materially affected module is listed, comma-separated without spaces. Hierarchical names such as `client/internal` are valid. Subjects are at most 72 characters. Bodies are reserved for breaking changes, security fixes, migrations, reverts, or non-obvious rationale.

It never adds Conventional Commit categories such as `feat`, `fix`, or `chore`, and it never adds AI attribution.

Outputs only the message. Does not stage, commit, or amend.

## How to invoke

```text
/caveman-commit
```

Also triggers on phrases such as "write a commit", "commit message", and "generate commit".

## Examples

```text
client/internal: preserve retry state
```

```text
docs,client/internal: document retry ownership
```

## See also

- [`SKILL.md`](./SKILL.md) — full agent instructions
- [Caveman README](../../README.md) — repository overview
