---
name: tdd
description: Build testable behavior one red-green vertical slice at a time through public seams.
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Test-driven development

Test observable behavior through a public seam, not private helpers or implementation-coupled mocks. Prefer an existing seam; introduce one only when behavior genuinely varies there. Follow repository policy for test approval and established test conventions.

For each slice:

1. Add the smallest behavior-facing test.
2. Run it and observe the expected failure for the intended reason.
3. Add only enough production code to make it pass.
4. Rerun it and observe success.
5. Refactor only when passing behavior reveals a clearer design.
6. Move to the next observable behavior.

Run proportionate broader validation at the end.

Do not force TDD onto documentation, generated files, mechanical edits, or behavior with no honest test seam. Prefer faithful integration boundaries over over-mocking dependency internals.
