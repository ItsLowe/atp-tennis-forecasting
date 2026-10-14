# ATP data requirements

The submitted dissertation uses annual ATP men's singles match and bookmaker-odds workbooks for 2010-2025 from [tennis-data.co.uk](http://www.tennis-data.co.uk/), as documented in section 3.1.1 (printed pages 16-17). The reported final analytical sample is 39,154 completed matches and 1,091 players after filtering. These counts were read from the dissertation, not reproduced during Phase 1.

## Expected local placement

Place exactly one source workbook for each of the 16 years in `data/raw/atp_odds_2010_2025/`:

`2010.xls` or `2010.xlsx`, continuing through `2025.xls` or `2025.xlsx`.

Use the original extension for each workbook. Stage 01 reads all matching files in filename order; stage 03 looks for each year explicitly and prefers `.xls` if both extensions exist. Keeping both copies, extra workbooks or different row orders can change the sample or seeded Player A/B assignment. Do not add unrelated spreadsheets to this folder. Stage 03 warns and skips missing years, so a successful read by itself does not establish complete coverage.

No annual workbooks are included in this repository. The author confirms permission for public display of the existing aggregate research tables and figures; that permission does not authorize publication of annual workbooks, match-level records or other raw source data. The exact historical workbook snapshots and terms applicable to those downloads are not recorded here. See the attribution and reuse note in the project README. No download/scraping script or source workbook is included.

## Schema needed by the supplied scripts

| Fields in original workbooks | Role |
|---|---|
| `Date`, `Winner`, `Loser`, `Comment` | Required import fields; completed-match filter |
| `Tournament`, `Round`, `Surface`, `Series`, `Court`, `Best of` | Match context, score-merge key and categorical predictors |
| `WRank`, `LRank`, `WPts`, `LPts` | Ranking and points covariates |
| Paired bookmaker fields such as `B365W`/`B365L`, `PSW`/`PSL` | Margin-normalized win probabilities |
| `AvgW`/`AvgL`, `MaxW`/`MaxL` | Aggregate odds fields; excluded from the individual-bookmaker mean |
| `W1`-`W5`, `L1`-`L5` | Set scores; total games provides the workload proxy |
| Optional `minutes`, `mins`, `duration`, `match_minutes` | Retained when available; not necessary for the total-games calculation |

Stage 01 normalizes column names (for example, `Best of` becomes `best_of`). Stage 03 lowercases score-import column names. Exact workbook schemas, dates, score coverage and duplicate-key handling remain untested because the data are absent. Stage 01 binds cleaned yearly frames using base `rbind`; different retained column sets across years can cause a runtime error. Review the actual source schemas before a future run instead of silently changing the cleaning rules.

## Local outputs and release policy

Generated cleaned data, player lookup, covariates, match-level predictions and diagnostic data are written to `data/processed/`. This entire directory is ignored, as are raw workbooks, fitted objects and checkpoints. The repository does not redistribute third-party raw data or match-level derivatives.

No processed data, tables, figures or checkpoints were generated during Phase 1. An ignore rule only protects ordinary Git staging; it does not grant redistribution rights or prevent manual inclusion in an archive. Review all future public files separately.
