# Selected reported aggregates

`reported_aggregates/` contains exactly four reviewed CSVs, copied byte-for-byte from the Phase 2 starter package. They transcribe the final dissertation's rounded summary results and were checked against its tables, text and figures. They are **not generated model outputs or an independent statistical replication**.

| File | Content | One-based PDF viewer pages |
|---|---|---|
| `figure_4_1_gap_reduction_reported.csv` | Eight overall test gap-closure percentages and primary/extension roles | 57 |
| `figure_4_2_disagreement_by_uncertainty_reported.csv` | Four all-test-group disagreement rates (%) | 60 |
| `figure_4_3_disagreement_logloss_reported.csv` | Sixteen disagreement-subset log losses and four subgroup counts | 61-62 |
| `table_4_3_primary_test_results_reported.csv` | Four forecasts' overall test log loss, Brier score and accuracy (%) | 55 |

Figure 4.2 rates use all test matches in each uncertainty group. Figure 4.3 counts refer only to disagreement matches. Do not interchange the denominators.

Only these four exact paths are allowlisted in `.gitignore`. Any additional CSV, prediction file, raw/processed data, checkpoint, fitted object or log remains excluded by default. No match identifiers, player-level records, third-party raw data or original report pages are included.

See [figure provenance](../../reproducibility/portfolio_figures.md) for hashes, precision and regeneration. The original dissertation remains the authority for the reported values; these transcriptions are not generated model outputs or an independent statistical replication. The author confirms permission for public display of these existing aggregate tables and their derived figures. No match-level records, source workbooks or original report pages are included, and no third-party data licence is granted by this repository.
