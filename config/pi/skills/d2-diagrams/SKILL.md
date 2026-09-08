---
name: d2-diagrams
description: Create and edit D2 (.d2) architecture diagrams, flowcharts, sequence diagrams, and ER diagrams. Use when D2 is requested or the diagram source is already D2; produce editable source and a locally rendered, visually checked SVG.
compatibility: Requires the D2 CLI; examples tested with D2 0.7.1. Visual inspection requires a local browser or image viewer.
---

# D2 diagrams

This is a locally authored skill grounded in the official D2 docs, not an upstream-endorsed package. See [the reference](references/d2.md) for source provenance and syntax. Resolve bundled paths relative to this skill directory.

## 1. Establish the content

Identify the diagram's question, audience, and output location. Follow the target repository's diagram convention; otherwise use a descriptive `.d2` filename alongside its `.svg`. Preserve existing source and outputs unless the task authorizes updating them.

For a diagram of existing software, inspect repository evidence first, using the code knowledge graph when available. Account for each component and connection; distinguish implemented behavior from proposed behavior. Ask about unresolved product or architecture decisions rather than inventing missing services, relationships, cardinalities, or guarantees. Finish this step with a small inventory of nodes, boundaries, and labeled edges.

## 2. Check local tooling

Run `d2 --version` and `d2 layout`. If D2 or a required engine is unavailable, report the blocker and ask before installing anything. Prefer built-in Dagre or ELK; this skill requires neither TALA nor a hosted service. Check the installed CLI's `--help` before using options outside the commands below.

Keep source and rendering local. Use plain shapes and local assets by default. Do not send diagrams to `d2 play`, a public playground, or another service without explicit permission. Check external icons and imports before rendering supplied source; remote assets can cause network requests even when the renderer runs locally.

## 3. Write the smallest useful diagram

Read only the relevant sections of [the reference](references/d2.md) and the matching starter:

| Diagram | Starter | Initial layout |
| --- | --- | --- |
| Components, deployment boundaries, data flow | [architecture.d2](examples/architecture.d2) | ELK |
| Decisions and process steps | [flowchart.d2](examples/flowchart.d2) | Dagre |
| Messages in time order | [sequence.d2](examples/sequence.d2) | D2's sequence layout; select Dagre for the outer graph |
| Tables, keys, relationships | [erd.d2](examples/erd.d2) | ELK for row-level connections |

Adapt a starter into the destination, leaving the bundled example unchanged. Examples are fictional, not facts about the target codebase. Preserve existing diagram style when editing. For a new diagram:

- Use short stable IDs and separate human-readable labels. Declare nodes before edges so accidental extra nodes are easier to spot.
- Use containers for real ownership or deployment boundaries, not decoration. Keep one main reading direction.
- Label relationships with actions or protocols; label decision branches explicitly. Add a legend when color or line style conveys meaning.
- Prefer a restrained theme, readable text, and whitespace. Split an overloaded view into an overview and detail diagrams before shrinking labels.
- Store the chosen layout and theme in `vars.d2-config` as in the examples, so a plain `d2 input.d2 output.svg` reproduces the intent, including from Emacs. Explicit CLI flags and environment variables can override that configuration.

## 4. Validate, render, inspect, repair

For the actual output file, replacing the sample paths:

```sh
d2 fmt ./diagram.d2
d2 fmt --check ./diagram.d2
d2 validate ./diagram.d2
d2 ./diagram.d2 ./diagram.svg
```

A successful validation is only a syntax/compilation check, not proof of correctness or readability. Confirm rendering exits successfully and creates a nonempty SVG, then inspect it in the available local browser or image viewer. Pi's `agent_browser` blocks inspection of `file://` pages; use a loopback HTTP preview rooted in a dedicated directory containing only the diagram artifacts, then take/read a screenshot. Bind the preview to `127.0.0.1`, stop it after inspection, and never serve the repository root or agent state. If the browser runs on another host, ask for an approved preview route rather than exposing a listener or uploading the diagram.

Inspect at the intended viewing size:

- Every required node, boundary, and connection is present; no typo-generated nodes or unintended duplicate edges appear.
- Labels are legible and unclipped, arrows point the right way, and crossings do not obscure their endpoints.
- Containers reflect the intended scope; sequence messages appear in the right order; ER links land on the intended columns with justified cardinalities.
- Meaning is understandable without color alone; important distinctions have text labels or a legend.

Fix content and labels first, then grouping/direction, then compare Dagre and ELK if routing remains poor. Change the stored layout when selecting the better result. Re-run formatting, validation, rendering, and visual inspection after changes. Stop when the checklist passes; after three unsuccessful repair passes, report the remaining issue and propose a simpler view instead of endlessly restyling. If no viewer is available, report visual inspection as unverified rather than claiming the diagram looks correct.

## 5. Deliver

Return paths to both `.d2` and `.svg`, the D2 version/layout used, checks performed, and any assumptions or unresolved visual issues. Render PNG or other formats only when requested and supported by the installed tooling; SVG is the default artifact. Keep intermediate renders/screenshots outside the repository unless requested. Do not edit generated SVG by hand: fixes belong in `.d2` so regeneration preserves them.
