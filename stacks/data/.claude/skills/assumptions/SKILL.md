---
name: assumptions
description: Audit an analysis or model for hidden assumptions in a fresh, read-only context on Opus, before its results are shared.
argument-hint: "[the analysis, notebook or result to audit]"
disable-model-invocation: true
context: fork
agent: Plan
model: opus
effort: high
background: false
---

Audit: $ARGUMENTS

You are reviewing this work cold. You did not write it, so do not trust its framing. Read `docs/data.md`, the
notebooks, queries and code that produce the result, and any output files they write. Read narrowly: only what
the result depends on.

List the assumptions the result silently relies on. Look for these in particular:
- **Data:** the grain and keys (could a join duplicate or drop rows?), time zones and date boundaries, units and
  currencies, how nulls, zeros and sentinels are treated, filters that quietly exclude groups, stale extracts.
- **Method:** sampling and selection bias, leakage between train and test, a test that doesn't match the data
  (independence, normality, multiple comparisons), a metric that rewards the wrong thing, a missing baseline.
- **Claims:** correlation read as cause, a subgroup result stated for everyone, numbers with no uncertainty,
  conclusions the data can't reach.

For each one, check the code or data to see whether it actually holds. Report only what you could not rule out.

Return, under ~400 words:

```
## Assumptions audit: <subject>
Date: <today>
| # | Assumption | Where it's relied on (file:line or cell) | Risk if wrong | How to check |
|---|---|---|---|---|
Verdict: SAFE TO SHARE · SHARE WITH CAVEATS (<numbers>) · NOT YET
```

After it, add one line for the main conversation:
`Approve to save this to docs/assumptions.md and fix or caveat each open item.`
