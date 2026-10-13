# AI workflow

## Tools

- **Claude Code (Claude Opus) in VS Code**: reading the repository, writing read-only diagnostic
  queries, drafting SQL changes and tests, and running the build and tests locally.
- **ChatGPT**: second-pass review of proposed diagnostics, SQL diffs, test design and the
  interpretation of results. Used to challenge assumptions and decide what evidence was required
  before approving a change.
- **Python 3 + the standard-library `sqlite3` module**: the same stack as the scaffolding, so every
  diagnostic and the independent calculation ran against the real warehouse with no extra install.

No subagents, parallel agents or worktrees were used. Claude Code and ChatGPT were used sequentially
rather than as parallel agents: repository actions were performed in Claude Code, while proposed
changes and evidence were reviewed before approval.

## Workflow

1. **Read before changing.** README, `REVENUE_POLICY.md`, `HANDOVER.md`, every model, every test and
   both `bin/` scripts, then a baseline build and test run (4/7 passing).
2. **Hypotheses, separated from facts.** Each Finance rule was mapped to its implementation, a
   possible violation and the query that would prove or disprove it. Confirmed defects, open
   hypotheses and test-suite weaknesses were kept as separate lists.
3. **Read-only diagnostics.** The warehouse was opened `mode=ro`; intermediate work lived in temp
   tables or scratch copies. The database hash was compared before and after diagnostic runs.
4. **Independent result first.** FY2026 Q2 was derived directly from the `raw_*` tables, without
   `models/` or `fact_order`, before any model was changed: $328,697.94. A parameterised bridge then
   reproduced both the delivered baseline ($727,922.09) and this figure exactly, which priced each
   defect.
5. **One change at a time.** Grain, scope, FX, platform fee, refunds, fiscal calendar and the
   settlement column were fixed in separate steps. Each was predicted (tests, row counts, Q2 net),
   shown as an exact diff, and reviewed before being written to the repository.
6. **Validate before applying.** Proposed models ran on scratch copies first. After one performance
   miss (Example B), simulations moved to on-disk copies and recorded query plans and timings, not
   just results.
7. **Apply, rebuild, verify.** Applied files were compared byte for byte with the approved draft,
   followed by a full rebuild, the full test suite, the Q2 figure and `git status`.
8. **Regression tests for real defects.** t08–t13 were each shown to fail on the defect they guard:
   on the pre-fix pipeline, or, where the data has no real example (replay conflicts), on a scratch
   copy with synthetic rows.

### Representative requests (summarised)

| Representative request | What came back | How it was used |
|---|---|---|
| Audit each Finance rule against the code; separate confirmed defects from hypotheses | A rule-by-rule table, plus diagnostics showing the three baseline failures had distinct causes (line-item fan-out, pending orders, weekend FX NULLs) | Became the defect backlog; two items it listed as hypotheses were later confirmed by data |
| Compute FY2026 Q2 independently from raw tables, with row counts per step and reconciliation checks | $328,697.94 by title, with a step-by-step row waterfall and a list of open assumptions | Became the reference for every later fix and for the golden test |
| Bridge the delivered number to the independent one in a fixed order, plus non-additive isolated impacts | An eight-step bridge that closed to the cent, and evidence that step deltas depend on the order | §4–5 of FINDINGS.md |
| Propose a grain-only redesign; detect conflicting replays without concatenating columns | Per-field `COUNT(DISTINCT)` checks with a NULL-vs-value rule, and a `UNIQUE` index | `02_stg_order.sql`, later guarded by t13 |

## Where the AI was wrong or incomplete

### Example A: a false "refund > gross" anomaly

An early diagnostic reported **85 orders whose refunds exceeded their gross**, which looked like a
data-quality defect. The query had joined refunds to `raw_orders` before replayed orders were
removed, so the refund sum was doubled for the 2,957 duplicated orders. Repeated on one row per
`order_id`, the count was **0**.

**Lesson:** establish the grain before trusting an anomaly count. Any aggregate over a table with
unresolved duplicates is suspect.

### Example B: a correct filter that hung the build

The internal-account exclusion was proposed as a correlated `NOT EXISTS` against `dim_player`. It was
logically correct and gave the right rows in a simulation. But that simulation ran on an **in-memory**
copy. On the real build, on a Google Drive-backed disk, `04_fact_order.sql` **hung for more than
11 minutes**. `EXPLAIN QUERY PLAN` showed a `CORRELATED SCALAR SUBQUERY` re-scanning the unindexed
`dim_player` once per order (about 109k × 45k rows). A 1/10-scale check took 4.15 s against 0.00 s
for the alternative. It was replaced by a non-correlated `NOT IN` with an `IS NOT NULL` guard (same
rows, subquery evaluated once). The full build then completed in about **17 seconds**.

**Lesson:** correctness and performance both need validating in the real execution environment.
From that point every proposal was simulated on an on-disk copy, with its query plan and timing.

Smaller slips were caught by the same discipline. Examples: a validation harness that rebuilt
`stg_order_priced` but not the materialised `fact_order`, so a fix appeared to do nothing; and a
model comment left stale by an earlier step. The stale comment was committed in the first checkpoint and corrected in a later change; the harness slip never affected a repository file.

## Guardrails

- **Landing files were never edited.** `data/` was read only; `bin/test.py` verifies its checksums
  on every run.
- **Line endings.** The original working checkout had CRLF line endings, which break those
  checksums, so all work moved to a clean LF checkout. `.gitattributes` (`data/*.csv -text`) stops
  git from converting the CSVs.
- **Scratch copies for anything destructive or synthetic.** Mutation tests, reverted-fix experiments
  and synthetic replays ran only on copies in a scratch directory, deleted afterwards.
- **`git diff` and `git status`** before and after every change; staging only named files.
- **One defect per step,** so each revenue effect stayed attributable and matched the bridge.
- **Evidence over explanation.** A generated explanation was accepted only once a query, a test or
  the independent reconciliation confirmed it.

## Outcome

- Independent raw-table result: **FY2026 Q2 net revenue = $328,697.94**.
- The final pipeline matches it by title and total, selected through `dim_date`.
- **13/13 tests pass**: the original 7 plus t08–t13, each validated against the defect it guards.
