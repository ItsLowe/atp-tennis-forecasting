# Portfolio figures: source and regeneration

## Verification boundary

All three images redraw **dissertation-reported aggregate results**. The authority is Zhiheng Huang's *When Ratings and Markets Disagree: TTT-Informed Covariate Models for Tennis Match Prediction*, MSc in Statistics and Sustainability, Trinity College Dublin, August 2026.

The supplied CSVs were reviewed against Table 4.3, Figures 4.1/4.2 and the sixteen Figure 4.3 values in its accompanying text. All 20 rows and 44 numerical result/count cells matched the source. No match-level input, prediction or fitted model was provided or executed.

**SOURCE-CHECKED** means agreement with the PDF, not statistical replication. **EXECUTED** applies to plotting, file checks and arithmetic on reported aggregates. **STATIC-ONLY** applies to the base R helper. No research finding was independently verified by executing analysis scripts 01-14.

Page references are one-based PDF viewer pages. Printed chapter pages are 13 lower for these results. The original PDF and page previews are reference material deliberately absent from this repository.

## Input-to-image map

Inputs are in [the reviewed aggregate directory](../outputs/selected_results/reported_aggregates/), with a [provenance note](../outputs/selected_results/README.md).

| Reviewed input | Public image | Source | Population |
|---|---|---|---|
| `figure_4_1_gap_reduction_reported.csv` | [test_gap_reduction.png](../figures/test_gap_reduction.png) | Figure 4.1, PDF p.57 | All 7,725 test matches, 2023-2025 |
| `figure_4_2_disagreement_by_uncertainty_reported.csv` | [disagreement_by_uncertainty.png](../figures/disagreement_by_uncertainty.png) | Figure 4.2, PDF p.60 | All test matches within each training-defined uncertainty group |
| `figure_4_3_disagreement_logloss_reported.csv` | [disagreement_logloss_by_uncertainty.png](../figures/disagreement_logloss_by_uncertainty.png) | Figure 4.3/text, PDF pp.61-62 | 1,496 test disagreement matches; subgroup n = 332/396/377/391 |
| `table_4_3_primary_test_results_reported.csv` | README metric table only | Table 4.3, PDF p.55 | All 7,725 test matches |

Each input retains starter bytes, source locator columns and original numeric precision. Formatting restores trailing zeros (21.7 to 21.70%) without changing values. Figure 4.1 percentages are read directly, not recalculated.

## Source checksums

SHA-256 fingerprints of the reviewed versions:

| File | SHA-256 |
|---|---|
| Authoritative source PDF (excluded) | `bf06fce4888d91ac6812c7acc815f9925fbaddd6e8d55472906fa2b8b06ef3e2` |
| `figure_4_1_gap_reduction_reported.csv` | `eb692ace73af88ddb38b629c1c8923e425df243a82bf67fba4712a48385255cd` |
| `figure_4_2_disagreement_by_uncertainty_reported.csv` | `affa41a6080051a51263b61f6a7f251ce3ae16e1d8b12cd18be5d71be2bc3fe6` |
| `figure_4_3_disagreement_logloss_reported.csv` | `9436eb55817b6279d458a45783f4092e3a3f8a1d539a6eace2fd928f05c2d940` |
| `table_4_3_primary_test_results_reported.csv` | `07d2ea3a95c8e16cfeded73031606dbbecb543a47e129b785ba0506e31dc5a02` |

## Numerical precision and interpretation

Gap closure is `100 * (TTT log loss - model log loss) / (TTT log loss - bookmaker log loss)`, evaluated separately on the full test set and disagreement subset.

Figure 4.1 reports primary logistic 57.3% and primary NN 58.8%. Rounded Table 4.3 entries yield approximately 57.323944% and 58.732394%; the latter rounds to 58.7% at one decimal. Some extension percentages also differ when recomputed from four-decimal tables. PDF p.57 reports a benchmark gap of 0.0709, whereas displayed entries give 0.6576 - 0.5866 = 0.0710.

These printed-precision differences are recorded without correction. Published Figure 4.1 labels are preserved. Full-precision predictions are unavailable, so their numerical identity has not been independently reconciled. No recovered unrounded quantities are claimed.

Disagreement-subset closures 69.6% and 75.1% are explicitly reported on PDF pp.59-60; they are not overall test closures. Full-sample disagreement is 18.25% (7,145/39,154), while test disagreement is 19.37% (1,496/7,725).

TTT uncertainty is the combined standard deviation of the two estimated skills. Training quartile cutoffs were held fixed. Exact cutoff values and all-test-group denominators are not in the supplied CSVs. Original assignments/rate calculations were not independently verified. Do not assume equal test groups or use Figure 4.3 subset counts as Figure 4.2 denominators.

## Regeneration

Run from the repository root. Choose one presentation helper:

```sh
python3 reproducibility/make_portfolio_figures.py
```

**Executed for the delivered PNGs:** Python 3.12.14, Matplotlib 3.10.8, Agg raster backend, DejaVu Sans, 200 dpi. Pillow 12.3.0 inspects PNG integrity/dimensions. The helper reads only three reviewed aggregate CSVs, guards their SHA-256 hashes, checks displayed text bounds and writes exactly the three named PNGs. It does not source R or read raw/processed research data.

```sh
Rscript --vanilla R/15_make_portfolio_figures.R
```

**STATIC-ONLY, not executed or parsed by R:** the base R alternative uses `utils`, `tools`, `graphics` and `grDevices`, with no external packages. MD5 byte guards identify the same reviewed CSVs; these are consistency checks, not security authentication. Numerical mappings were reviewed statically. Its typography/layout remain unverified and may differ from Matplotlib. Running it replaces the same three PNG paths.

Neither helper continues the research pipeline. The author confirms permission for public display of the existing aggregate CSVs and three author-created figures. The figures remain attributed to the dissertation and Tennis-Data as the underlying match/odds source. This does not authorize redistribution of source workbooks or match-level records. Do not run 01-14 to create these portfolio images. A separate statistical reproduction needs the [research pipeline](pipeline.md), [environment](environment.md), [input inventory](dependencies.md), privately held source data and substantial fitting work.

## Phase 2 checks

All PNGs were visually inspected for labels, legends, sample scope, plotted values, clipping and readability. Aggregate byte equality, 01-14 preservation, allowlist behaviour, local asset/document links and public-payload inventory were checked separately. [phase02_checks.json](phase02_checks.json) records lightweight checks, not R execution or model reproduction.
