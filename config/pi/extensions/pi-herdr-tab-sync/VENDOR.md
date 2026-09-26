# Vendored copy

Source: [`justcyl/pi-herdr-tab-sync`](https://github.com/justcyl/pi-herdr-tab-sync) at commit
`b8c931ce2e205d9acb15a95814c83fd9770ef244` ("fix: sync tab immediately after session rename").

That commit lives only in `refs/pull/2/head` — it is not on `main`, and `main` has not moved since
`7b1837ff` (2026-04-12). Referencing it as
`git:github.com/justcyl/pi-herdr-tab-sync@b8c931ce...` in `settings.base.json` made pi abort at
startup with `fatal: unable to read tree (b8c931ce...)`, because pi's clone only fetches branch refs
so the object never arrives. Vendoring keeps the immediate `/name` sync without that dependency.

Local changes: the `ExtensionAPI` type import points to the installed `@earendil-works/pi-coding-agent` package; renames are serialized so older requests cannot overwrite newer names, and failed requests can retry on the next event.

If PR #2 lands on `main`, this directory can be dropped in favour of a `git:` entry pinned to a
commit that is reachable from a branch.
