# Phase 1 code changes

The original 14 scripts remain unchanged in the extracted source staging area. Original and prepared SHA-256 hashes are recorded in [source_map.md](source_map.md) and [source_map.json](source_map.json). A complete unified diff is provided in [code_edits.patch](code_edits.patch); original line references below precede the added header.

| Files | Change | Potential numerical effect |
|---|---|---|
| All 14 | Moved into `R/`, renamed using the specification's lowercase 01-14 names; added ten descriptive comment lines and a separator newline | Names and comments do not change calculations. Invocation paths change; internal data/output paths stay rooted at the repository root |
| 09, original line 27 | Replaced conditional score path `data/processed/atp_ttt_predictions_2010_2025.csv` with `data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv` | Normal 03-08 column propagation makes this branch inactive, so no expected effect on the complete pipeline. If the column is absent, the branch now reads the actual stage-05 output instead of a missing/legacy file. A manually supplied legacy file could contain different values; this fallback has not been executed or numerically compared |
| 12, original comment lines 8, 32 and 255 | Updated three references to the renamed `11_neural_network_models.R` | Comments only; no numerical effect |

The path correction is justified by the actual stage-05 output filename and the retained `match_id`/`match_total_games` columns. The fallback merge, key handling and missing-score checks were left unchanged. No broad path refactor was needed: the original scripts already use relative `data/` and `outputs/` paths.

No formulas, random seeds, splits, priors, grid values, iteration limits, preprocessing rules, fitting routines, checkpoint logic or diagnostic definitions were edited. Original console messages and plotting blocks were preserved. No helper functions were extracted, no pipeline runner was introduced, and no script 15 was created. Original body bytes and line endings were retained apart from the four documented replacements (one path literal and three comment references).

Verification compares the complete prepared body against the original with only those replacements allowed, then compares lexical non-comment tokens: 13 scripts are identical; 09 differs at exactly one string token. This is a content check, not an R parse or runtime equivalence test.
