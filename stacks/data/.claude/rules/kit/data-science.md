---
paths:
  - "**/*.ipynb"
  - "**/notebooks/**"
  - "**/analysis/**"
  - "**/*.sql"
  - "**/dbt_project.yml"
  - "**/models/**"
  - "**/data/**"
---

# Data science (claude-kit)

- **Context first.** Read `docs/data.md` (sources, grain, keys, units, known gotchas) before touching data.
  When you learn something non-obvious about the data, add it there; never keep it only in the conversation.
- **Look before you compute.** Shape, dtypes, null rates, duplicate keys, ranges and a few sample rows first.
  State the grain ("one row per order line") before any join or aggregate.
- **Check every result.** Row counts before and after each join and filter; totals that should reconcile; the
  number of rows asked for is the number returned. A number nobody can trace back to a query is not a result.
- **Never silently drop or impute.** Say how many rows were removed or filled, and why.
- **Right tool for the size.** pandas for what fits comfortably in memory, polars or DuckDB beyond that; push
  filters and aggregates into SQL instead of pulling whole tables into Python.
- **Models: baseline first.** A dumb baseline (mean, majority class, last value) before anything clever. Split
  before any fitting or scaling; time-ordered data splits by time. Watch for leakage (target-derived features,
  future information, duplicates across splits). Report metrics with their uncertainty, not one lucky run.
- **Reproducible.** Fixed random seeds, pinned dependencies, raw data read-only; derived data is rebuilt by code,
  never edited by hand. Paths are relative to the project.
- **Notebooks.** Restart-and-run-all must work top to bottom. Move reused logic into modules with tests; keep
  notebooks for narrative. Clear large outputs before committing.
- **Charts** answer one question each: a title that states the finding, labelled axes with units, honest scales.
- **Privacy.** Never print personal data into the conversation or logs: aggregate, sample with masking, or
  describe columns instead. Ask before reading any file that may hold credentials or raw personal data.
- Before sharing an analysis, run `/assumptions` and fix or state what it finds.
