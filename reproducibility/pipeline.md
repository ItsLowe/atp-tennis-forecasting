# Pipeline order and interpretation

**Phase 1 status: static inspection only; no research stage executed.**

The supplied execution order is 01 through 14. The filenames retain the numeric prefixes and now use consistent lowercase names. Paths are relative to the repository root and each stage communicates through files rather than a persistent workspace.

| Order | Script | Required predecessor stages | Role |
|---|---|---|---|
| 01 | `R/01_data_processing.R` | External annual workbooks | Import annual workbooks, clean completed matches and normalize bookmaker probabilities. |
| 02 | `R/02_prepare_bookmaker_data.R` | 01 | Fix Player A/B orientation, assign chronological splits and evaluate preliminary bookmaker probabilities. |
| 03 | `R/03_add_score_data.R` | 02 | Merge annual set scores into modelling data and calculate the total-games workload proxy. |
| 04 | `R/04_prepare_ttt_input.R` | 03 | Set the final bookmaker benchmark and create chronological match and player identifiers. |
| 05 | `R/05_ttt_baseline.R` | 04 | Generate annual-refit TTT forecasts with same-date predictions before daily updates. |
| 06 | `R/06_build_covariates.R` | 05 | Build pre-match ranking, form, surface, experience, rest and workload covariates. |
| 07 | `R/07_build_short_term_covariates.R` | 05 | Build previous-match and seven-day rest and workload covariates. |
| 08 | `R/08_merge_covariates.R` | 06, 07 | Merge the base and short-term feature branches by match_id. |
| 09 | `R/09_build_matchup_covariates.R` | 08 | Add pre-match identity labels, head-to-head and common-opponent features. |
| 10 | `R/10_logistic_models.R` | 09 | Fit eight predefined logistic candidates and generate daily rolling-origin test predictions. |
| 11 | `R/11_neural_network_models.R` | 10 | Compare four NN feature families at maxit 300 and generate daily rolling-origin test predictions. |
| 12 | `R/12_nn_convergence_sensitivity.R` | 10, 11 | Compare maxit 300 and 1000 at sampled test dates using the already selected family configurations. |
| 13 | `R/13_primary_nn_final_rerun.R` | 10, 11 | Rerun the primary short-term NN validation grid and rolling test fits at maxit 1000. |
| 14 | `R/14_final_diagnostics.R` | 13 | Evaluate final disagreement subsets and training-defined TTT uncertainty quartiles without fitting models. |

See [dependencies.md](dependencies.md) for exact paths, conditional inputs, optional comparisons, logs and checkpoints. The recommended historical order remains 01-14 even where branches are independent: 06 and 07 both consume 05, 08 combines them, and 12 is a sensitivity branch whose outputs are not read by 13 or 14.

## Execution contract for a later authorized run

Use a fresh process per numbered script, with the working directory set to the repository root. For example, `Rscript --vanilla R/01_data_processing.R` starts the first stage when the data and environment are available. **This command and all following research stages were not run in Phase 1.** No automatic full-pipeline runner is supplied.

Scripts 01-04 prepare data; 05 fits TTT; 06-09 build covariates; 10 fits all logistic candidates; 11 fits the original NN families; 12 fits sampled convergence-sensitivity comparisons; 13 produces the final primary NN rerun; 14 computes final diagnostics from that rerun and its run summary. Original plotting blocks in 02, 10 and 11 remain part of those scripts and would execute if the scripts were sourced in a later phase.

## Method constraints read from the final dissertation

| Constraint | Source and static implementation evidence |
|---|---|
| Train 2010-2021, validation 2022, test 2023-2025 | Section 3.1.3 (printed p.18); stage 02 sets the partitions |
| Player A/B assignment seed 123 | Section 3.1.2 (p.18); stage 02 |
| Final bookmaker probability is the mean of normalized individual-bookmaker probabilities | Sections 3.1.1 and 3.2.1 (pp.17 and 22-23); stages 01 and 04 |
| TTT prior mean 0, prior SD 6, beta 1, gamma 0.03, no draws | Section 3.2.1 (pp.21-22); stage 05 constants |
| Annual historical refit; all same-date matches predicted before updating | Section 3.2.1 (p.22); stage 05 annual loop and daily update |
| Historical feature windows exclude the current date | Section 3.1.5 (pp.20-21); stages 06, 07 and 09 batch by date |
| Numeric imputation and scaling estimated on training and held fixed | Sections 3.1.5 and 3.3.2 (pp.21 and 30); stage 07 workload imputation and stage 10 preprocessing |
| Bookmaker probabilities are benchmarks, not fitted-model predictors | Section 3.2 (p.21) and Table 3.3; formulas in 10-13 |
| Candidate specifications selected by validation; test histories expand strictly before each date | Section 3.3 (pp.28-31); stages 10, 11 and 13 |
| Primary logistic is full short-term plus H2H | Section 3.3.1 (p.29); stage 14 role labels |
| Final primary NN is short-term, maxit 1000; extensions stay at 300 | Sections 3.2.3 and 3.5 (pp.26-28 and 38), Appendix B; stages 11 and 13 |
| Final primary size 3, decay 0.01, seed 303 are reported selections | Table 3.5 (p.27) and Table B.2 (p.74); stage 13 retains the full prescribed validation search rather than hardcoding a newly chosen test model |
| TTT uncertainty groups use training quartiles, type 7, open-ended outer intervals | Section 3.4.3 (pp.37-38); stage 14 |

These observations describe source code and methodology. They are not evidence that sample counts, convergence, selected configurations or forecasting metrics were reproduced.

## Final output provenance

Stage 11's short-term NN probabilities are provisional maxit-300 results. Stage 13 reselects the primary configuration from the prescribed validation grid at maxit 1000, refits daily test origins, writes a new prediction file and preserves the maxit-300 column. The three predefined extension-NN columns are carried forward from stage 11 without changing their iteration limit.

Stage 14 requires both the stage-13 prediction file and run summary. It checks zero nonconverged validation and rolling fits, expected split sizes and agreement with the final primary test log loss before writing disagreement and uncertainty summaries. Do not substitute earlier NN tables for the final primary analysis. No new model choice was made in Phase 1.

The reported split sizes (28,890 / 2,539 / 7,725) and 876 test dates are hardcoded assertions in stage 13. Revised raw files or different cleaning results may trigger them. Record a discrepancy; do not change assertions, methods or reported results merely to make a run complete.

## Phase 2 standalone presentation path

No research stage 01-14 was executed or changed in Phase 2. `R/15_make_portfolio_figures.R` is a standalone aggregate-only presentation helper, not a new fitting/diagnostic stage or a consumer of stage 14 outputs. It is **STATIC-ONLY** because R remains unavailable.

The three delivered PNGs were generated by `reproducibility/make_portfolio_figures.py` from checked dissertation transcriptions under `outputs/selected_results/reported_aggregates/`. They require no raw workbooks, match-level predictions or fitted objects. See [figure provenance](portfolio_figures.md). The historical Phase 1 contract above describes a future authorized research run, not work performed for these images.
