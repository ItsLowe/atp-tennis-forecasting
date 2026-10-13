# Per-script dependency inventory

**Static source inspection only. Paths below are expected runtime inputs/outputs, not files supplied or generated during Phase 1.**

All paths are relative to the repository root. External packages listed per script are direct dependencies; base/distributed R is implicit. Checkpoints are optional resume inputs as well as runtime outputs. Generated tables, original plotting outputs and sensitivity details remain excluded by default. No result CSV is packaged.

## 01 - 01_data_processing.R

Import annual workbooks, clean completed matches and normalize bookmaker probabilities.

**External packages:** `readxl`.

**Required inputs:**

- `data/raw/atp_odds_2010_2025/{2010,...,2025}.xls or .xlsx`

**Main data outputs:**

- `data/processed/atp_odds_clean_all_completed.csv`
- `data/processed/atp_odds_clean_with_bookmaker_prob.csv`

External input. Reads every .xls/.xlsx in the raw folder, sorted by filename; use exactly one workbook per year. Both output files remain private.

## 02 - 02_prepare_bookmaker_data.R

Fix Player A/B orientation, assign chronological splits and evaluate preliminary bookmaker probabilities.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_odds_clean_with_bookmaker_prob.csv`

**Main data outputs:**

- `data/processed/atp_odds_modelling_ready.csv`

**Table/detail outputs:**

- `outputs/tables/bookmaker_overall_metrics.csv`
- `outputs/tables/bookmaker_probability_source_comparison.csv`
- `outputs/tables/bookmaker_metrics_by_split.csv`
- `outputs/tables/bookmaker_metrics_by_year.csv`
- `outputs/tables/bookmaker_metrics_by_surface.csv`
- `outputs/tables/bookmaker_metrics_by_court.csv`
- `outputs/tables/bookmaker_metrics_by_series.csv`
- `outputs/tables/bookmaker_metrics_by_round.csv`
- `outputs/tables/bookmaker_calibration_bins.csv`

**Retained plotting outputs (NOT generated in Phase 1):**

- `outputs/figures/bookmaker_logloss_by_year.png`
- `outputs/figures/bookmaker_accuracy_by_year.png`
- `outputs/figures/bookmaker_calibration.png`

Seed 123 fixes label orientation. The surface/court/series/round summaries are conditional on those columns. The default early benchmark is p_book_main_a; stage 04 sets the final market-mean benchmark. Existing plotting code is retained and was not executed.

## 03 - 03_add_score_data.R

Merge annual set scores into modelling data and calculate the total-games workload proxy.

**External packages:** `readxl`.

**Required inputs:**

- `data/processed/atp_odds_modelling_ready.csv`
- `data/raw/atp_odds_2010_2025/{2010,...,2025}.xls or .xlsx`

**Main data outputs:**

- `data/processed/atp_odds_modelling_ready_with_scores.csv`

**Table/detail outputs:**

- `outputs/tables/score_columns_missing_summary.csv`

Prefers .xls over .xlsx if both exist for a year; warns and skips missing years. Merge keys: date, tournament, winner, loser; duplicated score keys keep their first occurrence. No workbooks were supplied.

## 04 - 04_prepare_ttt_input.R

Set the final bookmaker benchmark and create chronological match and player identifiers.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_odds_modelling_ready_with_scores.csv`

**Main data outputs:**

- `data/processed/atp_ttt_input_2010_2025.csv`
- `data/processed/player_lookup_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/ttt_input_summary.csv`

Uses p_book_market_mean_a when the column exists, otherwise p_book_main_a; filters invalid final probabilities. Retains available score fields and match_total_games.

## 05 - 05_ttt_baseline.R

Generate annual-refit TTT forecasts with same-date predictions before daily updates.

**External packages:** `TrueSkillThroughTime`, `hash`.

**Required inputs:**

- `data/processed/atp_ttt_input_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/ttt_genuine_yearly_metrics_by_split.csv`
- `outputs/tables/ttt_genuine_yearly_vs_bookmaker_by_split.csv`
- `outputs/tables/ttt_genuine_yearly_model_settings.csv`

**Checkpoint outputs / optional resume inputs:**

- `data/processed/atp_ttt_genuine_yearly_predictions_checkpoint.csv`

**Logs:**

- `outputs/logs/ttt_genuine_yearly_run_log.txt`
- `outputs/logs/ttt_genuine_yearly_sessionInfo.txt`

Costly stage; NOT RUN. Automatically reads its checkpoint if present and resume is enabled. Annual checkpoint matching checks match_id and annual frequency but lacks input hashes and a complete settings signature.

## 06 - 06_build_covariates.R

Build pre-match ranking, form, surface, experience, rest and workload covariates.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_covariates_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/covariate_missing_summary.csv`
- `outputs/tables/covariate_summary.csv`

Computes all covariates for a date before updating histories. Retains the input columns, including scores. Exposes TTT logit and uncertainty; the mean-skill difference is descriptive and is not a separate fitted predictor.

## 07 - 07_build_short_term_covariates.R

Build previous-match and seven-day rest and workload covariates.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_shortterm_fatigue_covariates_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/shortterm_fatigue_missing_summary.csv`

Separate branch from stage 05, kept seventh in the supplied order. Requires match_total_games; uses the training-set median for missing previous-match games. Exports match_id and short-term features.

## 08 - 08_merge_covariates.R

Merge the base and short-term feature branches by match_id.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_covariates_2010_2025.csv`
- `data/processed/atp_shortterm_fatigue_covariates_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_covariates_with_shortterm_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/merged_shortterm_covariate_missing_summary.csv`

Checks unique identifiers and unchanged row count; restores the base row order.

## 09 - 09_build_matchup_covariates.R

Add pre-match identity labels, head-to-head and common-opponent features.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_covariates_with_shortterm_2010_2025.csv`

**Conditional input (only when the score column is absent):**

- `data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_covariates_with_identity_h2h_common_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/identity_h2h_common_missing_summary.csv`

Conditional score input is read only if match_total_games is absent; its legacy filename was corrected to the stage-05 output. Normal 03-08 propagation retains this column. Stops if any total-games values remain missing. Identity labels are retained outputs, not predictors in the fitted formulas.

## 10 - 10_logistic_models.R

Fit eight predefined logistic candidates and generate daily rolling-origin test predictions.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_covariates_with_identity_h2h_common_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_logistic_predictions_with_h2h_common_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/logistic_rolling_origin_audit.csv`
- `outputs/tables/logistic_rolling_origin_settings.csv`
- `outputs/tables/logistic_model_comparison_by_split.csv`
- `outputs/tables/logistic_model_comparison_test.csv`
- `outputs/tables/logistic_full_shortterm_model_coefficients.csv`
- `outputs/tables/logistic_h2h_common_gap_reduction_summary.csv`

**Retained plotting outputs (NOT generated in Phase 1):**

- `outputs/figures/test_logloss_model_comparison.png`
- `outputs/figures/test_accuracy_model_comparison.png`

**Checkpoint outputs / optional resume inputs:**

- `data/processed/rolling_checkpoints/glm_<probability_column>_date.rds`

Costly stage; NOT RUN. Imputation and standardization use the original training partition; test fits use dates strictly earlier than the forecast date. Checkpoint signatures include input MD5 and formula. The saved coefficient table is for the initial full-short-term candidate, not the primary H2H model or all rolling fits. Plotting code retained, not executed.

## 11 - 11_neural_network_models.R

Compare four NN feature families at maxit 300 and generate daily rolling-origin test predictions.

**External packages:** `nnet`.

**Required inputs:**

- `data/processed/atp_logistic_predictions_with_h2h_common_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_nn_shortterm_h2h_common_predictions_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/nn_h2h_common_hyperparameter_results.csv`
- `outputs/tables/nn_h2h_common_best_hyperparameters.csv`
- `outputs/tables/nn_rolling_origin_audit.csv`
- `outputs/tables/nn_rolling_origin_settings.csv`
- `outputs/tables/nn_model_comparison_by_split.csv`
- `outputs/tables/nn_model_comparison_test.csv`
- `outputs/tables/nn_h2h_common_gap_summary.csv`

**Retained plotting outputs (NOT generated in Phase 1):**

- `outputs/figures/nn_test_logloss_comparison.png`
- `outputs/figures/nn_test_accuracy_comparison.png`

**Checkpoint outputs / optional resume inputs:**

- `data/processed/rolling_checkpoints/nnet_<probability_column>_date.rds`

Costly stage; NOT RUN. Uses 48 size/decay/seed combinations per family (192 fits), selected by validation log loss. Preprocessed z_ columns come from stage 10. The selected family fits then undergo daily test refits. The final primary NN results come from stage 13, not this provisional short-term column. Plotting code retained, not executed.

## 12 - 12_nn_convergence_sensitivity.R

Compare maxit 300 and 1000 at sampled test dates using the already selected family configurations.

**External packages:** `nnet`.

**Required inputs:**

- `data/processed/atp_logistic_predictions_with_h2h_common_2010_2025.csv`
- `outputs/tables/nn_h2h_common_best_hyperparameters.csv`
- `outputs/tables/nn_rolling_origin_audit.csv`

**Optional comparison inputs:**

- `data/processed/atp_nn_shortterm_h2h_common_predictions_2010_2025.csv`
- `outputs/tables/nn_model_comparison_by_split.csv`

**Table/detail outputs:**

- `outputs/sensitivity/nn_convergence_sensitivity_selected_origins.csv`
- `outputs/sensitivity/nn_convergence_sensitivity_original_audit.csv`
- `outputs/sensitivity/nn_convergence_sensitivity_fit_summary.csv`
- `outputs/sensitivity/nn_convergence_sensitivity_predictions.csv`
- `outputs/sensitivity/nn_convergence_sensitivity_by_origin.csv`
- `outputs/sensitivity/nn_convergence_sensitivity_summary.csv`

**Checkpoint outputs / optional resume inputs:**

- `outputs/sensitivity/nn_convergence_sensitivity_checkpoint.rds`

Research sensitivity branch; NOT RUN and not a lightweight check. Four dates per test year, four families and two iteration limits imply 96 fits when all three test years are present. Optional prediction input enables the maxit-300 reproduction comparison; optional metrics input supplies its reference comparison. No stage-13 input is produced here.

## 13 - 13_primary_nn_final_rerun.R

Rerun the primary short-term NN validation grid and rolling test fits at maxit 1000.

**External packages:** `nnet`.

**Required inputs:**

- `data/processed/atp_logistic_predictions_with_h2h_common_2010_2025.csv`
- `data/processed/atp_nn_shortterm_h2h_common_predictions_2010_2025.csv`

**Main data outputs:**

- `data/processed/atp_nn_primary_maxit1000_predictions_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/primary_nn_maxit1000/nn_primary_maxit1000_hyperparameter_results.csv`
- `outputs/tables/primary_nn_maxit1000/nn_primary_maxit1000_best_hyperparameters.csv`
- `outputs/tables/primary_nn_maxit1000/nn_primary_maxit1000_rolling_origin_audit.csv`
- `outputs/tables/primary_nn_maxit1000/nn_primary_maxit1000_model_comparison_by_split.csv`
- `outputs/tables/primary_nn_maxit1000/nn_primary_maxit1000_run_summary.csv`
- `outputs/tables/primary_nn_maxit1000/nn_primary_maxit1000_run_settings.csv`

**Checkpoint outputs / optional resume inputs:**

- `data/processed/rolling_checkpoints_primary_nn_maxit1000/primary_nn_validation_grid_checkpoint.rds`
- `data/processed/rolling_checkpoints_primary_nn_maxit1000/primary_nn_rolling_origin_checkpoint.rds`

Costly stage; NOT RUN. Selects the lowest validation log loss among converged grid fits and keeps size/decay/seed fixed for daily test refits. Requires the stage-11 file to carry forward the three extension-NN columns and preserves the old short-term column as p_nn_shortterm_a_maxit300. Enforces split sizes 28890/2539/7725 and 876 test dates. It does not read stage-12 outputs.

## 14 - 14_final_diagnostics.R

Evaluate final disagreement subsets and training-defined TTT uncertainty quartiles without fitting models.

**External packages:** None beyond base/distributed R.

**Required inputs:**

- `data/processed/atp_nn_primary_maxit1000_predictions_2010_2025.csv`
- `outputs/tables/primary_nn_maxit1000/nn_primary_maxit1000_run_summary.csv`

**Main data outputs:**

- `data/processed/atp_final_disagreement_diagnostics_primary_nn_maxit1000_2010_2025.csv`

**Table/detail outputs:**

- `outputs/tables/final_disagreement_maxit1000/final_disagreement_count_summary.csv`
- `outputs/tables/final_disagreement_maxit1000/final_model_disagreement_results_by_split.csv`
- `outputs/tables/final_disagreement_maxit1000/final_disagreement_gap_recovery.csv`
- `outputs/tables/final_disagreement_maxit1000/final_ttt_uncertainty_training_quartile_breaks.csv`
- `outputs/tables/final_disagreement_maxit1000/final_disagreement_ttt_uncertainty_quartile_counts.csv`
- `outputs/tables/final_disagreement_maxit1000/final_disagreement_by_ttt_uncertainty_quartile.csv`

NOT RUN. Requires a maxit-1000 summary with zero nonconverged validation and rolling fits, expected split counts and agreement with the primary NN test log loss. Uses >=0.5 directions and training-only type-7 uncertainty quartiles with open-ended outer intervals. No plots are produced by this script.

## Path closure and availability

Every mandatory generated input maps to an earlier numbered producer. Stage 09's conditional score input now maps to stage 05. Stage 12's optional comparison inputs come from 11; no downstream primary-analysis stage reads sensitivity outputs.

The 16 annual workbooks are the missing external inputs. All other required CSV files are absent intermediate outputs of the pipeline, rather than extra files needed to complete Phase 1. Runtime schemas, file contents and numerical agreement have not been tested.

Dynamic checkpoint names use the actual probability-column name from their model specifications: `glm_<probability_column>_date.rds` in 10 and `nnet_<probability_column>_date.rds` in 11. The configured origin unit stays `date`. The broader monthly/yearly modes in those functions were not selected or changed.
