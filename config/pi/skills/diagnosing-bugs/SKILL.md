---
name: diagnosing-bugs
description: Diagnose a hard bug, regression, flake, race, or performance problem through a tight reproduction before attempting a fix.
license: MIT; adapted from Matt Pocock skills@9603c1c
---

# Diagnose a bug

## Establish the loop

Do not theorize from source alone. First build and run one unattended, bounded command that demonstrates the reported symptom and can later prove it gone. Prefer a focused test through the affected public seam, then the smallest reproducible harness or user flow.

The loop must be specific, deterministic enough to diagnose, safe to run, and fast enough to rerun. For a flake or race, improve the reproduction rate before guessing. If no honest loop is possible, state what was tried and stop for missing evidence, access, or authorization.

## Diagnose

1. Reproduce and minimize the failing case.
2. List a small set of falsifiable hypotheses and their predictions.
3. Test one prediction at a time with focused logging, inspection, tracing, or narrow instrumentation.
4. Measure before changing performance-sensitive code.
5. Distinguish dependency or runtime behavior from application behavior using authoritative documentation or source when necessary.

## Fix

Turn the minimized reproduction into a regression test at an honest public seam when possible and permitted by repository policy. Observe it fail, fix the cause, observe it pass, then rerun the original loop and applicable validation.

Remove temporary instrumentation and report the cause, proof, changed paths, commands, and remaining risk. Do not leave debug debris or processes behind.
