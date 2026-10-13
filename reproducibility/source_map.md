# Source-to-public filename map

Source paths refer to the starter package, under `sources/ATP/R_original/`. Originals were preserved unchanged outside the deliverable. Public filenames are under `R/`. All 14 scripts received descriptive comment headers; only 09 has an executable path-literal edit, and 12 also has three comment-reference updates.

| Order | Source filename | Public filename | Body change |
|---|---|---|---|
| 01 | `01_DataProcessing.R` | `R/01_data_processing.R` | None |
| 02 | `02_PrepareBookmakerData.R` | `R/02_prepare_bookmaker_data.R` | None |
| 03 | `03_AddScoreData.R` | `R/03_add_score_data.R` | None |
| 04 | `04_PrepareTTTInput.R` | `R/04_prepare_ttt_input.R` | None |
| 05 | `05_TTTBaseline.R` | `R/05_ttt_baseline.R` | None |
| 06 | `06_BuildCovariates.R` | `R/06_build_covariates.R` | None |
| 07 | `07_BuildShortTermCovariates.R` | `R/07_build_short_term_covariates.R` | None |
| 08 | `08_MergeCovariates.R` | `R/08_merge_covariates.R` | None |
| 09 | `09_BuildMatchupCovariates.R` | `R/09_build_matchup_covariates.R` | Conditional score filename |
| 10 | `10_LogisticModels.R` | `R/10_logistic_models.R` | None |
| 11 | `11_NeuralNetworkModels.R` | `R/11_neural_network_models.R` | None |
| 12 | `12_NNConvergenceSensitivity.R` | `R/12_nn_convergence_sensitivity.R` | Three comment references |
| 13 | `13_PrimaryNNFinalRerun.R` | `R/13_primary_nn_final_rerun.R` | None |
| 14 | `14_FinalDiagnostics.R` | `R/14_final_diagnostics.R` | None |

## SHA-256 provenance

These checksums cover complete script bytes, including comments and original line endings. Machine-readable paths, hashes, inputs and outputs are also in [source_map.json](source_map.json). The unified edit map is [code_edits.patch](code_edits.patch).

### 01 - 01_data_processing.R

- Original: `e54571c56479dc1a1fddd5e5cb3019c00e359a85b2d923b58e3effc9593adb16`
- Prepared: `6eb4fa35938771096d6d79d0fd60b3bbde77dd64c2ef6ee7e86809dbcd62c7a4`

### 02 - 02_prepare_bookmaker_data.R

- Original: `42350c0c724064941398c881f53e3186571fa677b82cfd18428d5e7bf950995b`
- Prepared: `f5e863ef6909f297f444e246c4f077d2f0555a153ddb34622303fdbd95572d8c`

### 03 - 03_add_score_data.R

- Original: `167163bf0506b5c0b8d80e1356d73f665ebf056c9ab9ca32057cbb92c78f7e95`
- Prepared: `b0390414e2bf3e20b342247c9d896a05a3242830491631d31bee280ea47fe508`

### 04 - 04_prepare_ttt_input.R

- Original: `ca7b342c91757f9e60a933c7a2212c8d80fb7fcc6ab9bc4b6c57c9bca74d5791`
- Prepared: `28ec49f9c1e3af6c38f66c704751673c6752bd47300c776a5460e7616367c759`

### 05 - 05_ttt_baseline.R

- Original: `4168a756a8a8f51a44002c1fb01a2390d28e982ee9a9c16a49b371cabfad9c67`
- Prepared: `28f6440c8dd78755bd08d9a12f1e18af202bce13b890d70e26286271f87e0f59`

### 06 - 06_build_covariates.R

- Original: `5579e81f8298da717a581068ec452f70c6d865535f6f6cf6928d43666f06e093`
- Prepared: `b823611b95f81d3b88754c2f3e29ccc6f1e09d9aaf58d3cb6ce8c5a8ad3d975d`

### 07 - 07_build_short_term_covariates.R

- Original: `11660218abe18a8c1518e708cec35eac307609a639a22e6d3f74a566984f1d38`
- Prepared: `fcb9461dfe62b2f6f9fafe2fa240610744e41bd7fad8ca64beeaf7283ddc8d03`

### 08 - 08_merge_covariates.R

- Original: `31c0794d0ddd8bdd98e2bd13feadb8adeb7c45be474c46d2dd94044b3b797dba`
- Prepared: `53ff14b22f3aae53f613b39ed3ec161d7eedfe8cde819188b5b40b34030654b0`

### 09 - 09_build_matchup_covariates.R

- Original: `a2e6206f169afb17cd6567283abd3bcc98e1ed32836fb9f84e720ccf2f80a1da`
- Prepared: `bfd047c26f3ff1263b9e7a46d2b311515da2f3b6ee2b1f11ceaf8ee3db2f48c1`

### 10 - 10_logistic_models.R

- Original: `a142b2dae32ec93b754e3c1ba1f3837f777167d166934cf7812de1a600202d82`
- Prepared: `fea7f8c5c4b09ccec14755531897cc911389e2e16afc1b6bee5681022f1b5c20`

### 11 - 11_neural_network_models.R

- Original: `db815887f6fac230d1e34b7ea7fd1a9282cb51fb4f4f716f257b09cce240fc61`
- Prepared: `c266278b388add08e6e971eebfc73c335a191aac9b16d5b184ed244261021990`

### 12 - 12_nn_convergence_sensitivity.R

- Original: `b2d4b404f1eff6c4e493b10c579a406cb385e1d75f5636223533202e980fa9c8`
- Prepared: `e23eb0533e48eebd35abf2804f43d7da1ad87b0153961e17a33cc42852bf3a5b`

### 13 - 13_primary_nn_final_rerun.R

- Original: `2c2f8696bdc498ca72e4f8b086cc8a33144249b2e2796fc3c2ef9790baba14c9`
- Prepared: `f983ae8742355ef1c5fa4bbbced82e45e82155ba7c1cebdf2b4dd6adc5a35544`

### 14 - 14_final_diagnostics.R

- Original: `33cc4de9d65496d619e30007bd8ddae9a9ed07df292239b396f4eb995a9a881b`
- Prepared: `29908a0699d6b1000e1ee39c9b1cef7e97a9639b2bbb01a5322b2d785dfb7ac2`
