---
name: racket-docs
description: Browse official Racket documentation and extract the relevant rendered text for languages, libraries, modules, and exact bindings. Use when answering questions about Racket APIs or behavior, especially when the answer should match an installed Racket version.
---

# Racket Docs

Use official Racket documentation and return rendered documentation text, not raw HTML.

## Choose the documentation version

When the question concerns local code and `racket` is installed, run `racket --version` and use its major/minor release documentation. Use the latest documentation when requested or when no local version is available. State which version you consulted.

- Latest: `https://docs.racket-lang.org/`
- Release search: `https://download.racket-lang.org/releases/<version>/doc/search/index.html?q=<encoded-query>`

## Find the page

Search with the module and exact binding when known, such as `ffi/unsafe _fun`. Open the search URL with `agent_browser`, then use `snapshot -i` only to inspect and follow result links. Distinguish similarly named manuals such as `ffi/unsafe`, `ffi2`, and Rhombus FFI.

## Read documentation text

Start without launching a browser when the page URL is known:

```text
read <url> --outline
read <url> --filter <binding-or-heading>
```

`--outline` maps the page; `--filter` narrows its rendered text. Do not use `snapshot -i` to read prose because it contains interactive elements only. Do not force `--llms` for Racket documentation; the site may reject it, while normal `read` already falls back to readable HTML.

## Extract one Scribble definition

If `read --filter` remains too broad, open the exact result URL including its fragment and run this through `agent_browser` using `args: ["eval", "--stdin"]` and top-level `stdin`:

```javascript
(() => {
  const name = decodeURIComponent(location.hash.slice(1));
  const anchor = [...document.querySelectorAll("a[name]")]
    .find((a) => a.getAttribute("name") === name);
  const start = anchor?.closest(".SIntrapara") ?? anchor?.parentElement;
  if (!start) return null;

  const blocks = [];
  for (let node = start; node; node = node.nextElementSibling) {
    if (node !== start) {
      const nextDefinition = [...node.querySelectorAll("a[name]")]
        .some((a) => /^\((?:form|def)\._/.test(a.getAttribute("name") ?? ""));
      if (nextDefinition) break;
    }
    const text = node.innerText?.trim();
    if (text) blocks.push(text);
  }
  return blocks.join("\n\n");
})()
```

This follows Scribble's named anchor and collects rendered text through the next documented form or definition. If the page does not match that structure, use `snapshot --compact --search <term>` to identify a scoped selector, then `get text <selector>`; use a targeted `eval --stdin` only when no stable selector exists.

## Answer

Include:

- the direct definition or manual URL;
- the documentation version;
- the required module/package when shown;
- the relevant signature, explanation, caveats, and examples only.

Call out a material difference between installed-version and latest documentation. Stop once the requested API or behavior is documented; do not survey unrelated manuals.
