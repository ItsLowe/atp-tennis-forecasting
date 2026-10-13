# Environment and dependencies

## Dissertation environment

The submitted dissertation, section 3.5 (printed page 38; PDF page 51), reports the following environment. These are reported versions, not versions installed or tested in Phase 1.

| Component | Reported version | Role / scripts |
|---|---|---|
| R | 4.5.2 | Entire analysis |
| Operating system | 64-bit Windows 11 | Original dissertation run |
| `readxl` | 1.4.5 | Excel import in 01 and 03 |
| `TrueSkillThroughTime` | 1.0.0 | TTT History, convergence and learning curves in 05 |
| `nnet` | 7.3-20 | NN fitting in 11, 12 and 13 |
| `hash` | Not stated in the PDF | Direct dependency in 05 for daily player priors |

Static inspection found four external/recommended packages: `readxl`, `TrueSkillThroughTime`, `hash` and `nnet`. Base/distributed R facilities also include `stats` (GLM, normal CDF, design matrices and quantiles), `utils` (CSV I/O and session information), `tools` (input MD5 hashes), `graphics` and `grDevices` (the retained original plotting code). `nnet` ships as a recommended R package in many installations but is still an explicit script dependency. Transitive dependency versions cannot be reconstructed from the provided materials.

The scripts check or load their dependencies; no active automatic package installation calls were found. Messages containing `install.packages(...)` are printed instructions, not executed installation code. No packages were installed and no external package pages were accessed during Phase 1.

## Phase 1 environment and checks

Preparation used Python for file organization, checksums, lexical checks and archive validation, Git solely for local ignore-rule checks, and Poppler for read-only PDF text extraction and one methodology-page rendering. Python is a preparation tool, not a dependency of the research pipeline.

`R` and `Rscript` are not available here. R syntax parsing, package loading, source-data reading, small analytical tests and full statistical reproduction are **NOT RUN**. Raw annual workbooks and generated outputs are absent. The original dissertation software versions and `hash` version have not been installed or validated. No `renv.lock`, fitted-model bundle or fabricated `sessionInfo()` is supplied.

## Future environment verification (not executed)

In a separate authorized phase, record the actual R version, operating system, external package versions and `sessionInfo()` before interpreting reproduced results. Prefer the reported versions for comparison; treat any differences as caveats rather than silently updating the dissertation methods or numbers. Determine the original `hash` version from an existing original session log if one becomes available.

For a syntax-only check from the repository root, the following command parses script files without sourcing them. It was not run here:

```sh
Rscript --vanilla -e 'files <- sort(list.files("R", pattern = "[.]R$", full.names = TRUE)); for (f in files) { parse(file = f); cat("Parsed:", f, "\n") }'
```

Use fresh R sessions when running research stages. Most scripts call `rm(list = ls())`; loading them into an interactive session can discard objects. Relative paths resolve against the process working directory, so run from the repository root, not `R/`.

## Checkpoint caution

Stages 05, 10-13 can resume existing checkpoints automatically. None is packaged. Stage 05's CSV checkpoint lacks an input-hash and complete settings signature; use only checkpoints whose original input/settings provenance is known. Stages 10-13 include input/settings signatures, with maxit explicitly included in the stage-12/13 signatures; they still do not pin R or package versions. Keep checkpoint families separate and do not bypass mismatch guards. Reproduction may require substantial computation; do not start it as an installation check.

## Phase 2 presentation environment

R and Rscript remain unavailable. No R parsing, dependency loading or research execution occurred in Phase 2. The base R aggregate plotting helper is supplied as **STATIC-ONLY**, not a tested rendering or research path.

Delivered PNGs used Python 3.12.14 and Matplotlib 3.10.8 (Agg backend), with Pillow 12.3.0 for inspection. Only reviewed dissertation-reported aggregates were read. Python compilation, lightweight file/arithmetic checks and plotting were executed; this does not establish independent statistical reproduction. No additional packages were installed.

See [portfolio_figures.md](portfolio_figures.md) for commands, input hashes, pages and precision limits. [static_checks.json](static_checks.json) remains an unchanged Phase 1 historical record; [phase02_checks.json](phase02_checks.json) records Phase 2.
