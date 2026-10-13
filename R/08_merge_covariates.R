# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Merge the base and short-term feature branches by match_id.
# Source: 08_MergeCovariates.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 08.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 08 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

rm(list = ls())

base_file <- "data/processed/atp_covariates_2010_2025.csv"
shortterm_file <- "data/processed/atp_shortterm_fatigue_covariates_2010_2025.csv"

processed_dir <- "data/processed"
table_dir <- "outputs/tables"

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(base_file)) {
  stop("Base covariate file not found: ", base_file)
}

if (!file.exists(shortterm_file)) {
  stop("Short-term covariate file not found: ", shortterm_file)
}

base <- read.csv(base_file, stringsAsFactors = FALSE)
shortterm <- read.csv(shortterm_file, stringsAsFactors = FALSE)

names(base) <- tolower(names(base))
names(shortterm) <- tolower(names(shortterm))

if (!"match_id" %in% names(base)) {
  stop("match_id not found in base covariate file.")
}

if (!"match_id" %in% names(shortterm)) {
  stop("match_id not found in short-term covariate file.")
}

if (any(duplicated(base$match_id))) {
  stop("Duplicated match_id in base covariate file.")
}

if (any(duplicated(shortterm$match_id))) {
  stop("Duplicated match_id in short-term covariate file.")
}

base$row_order_original <- seq_len(nrow(base))

############################################################
# Avoid duplicate columns if rerunning this script
############################################################

shortterm_vars <- setdiff(names(shortterm), "match_id")

existing_shortterm_vars <- shortterm_vars[shortterm_vars %in% names(base)]

if (length(existing_shortterm_vars) > 0) {
  base <- base[, !(names(base) %in% existing_shortterm_vars), drop = FALSE]
}

############################################################
# Merge
############################################################

merged <- merge(
  base,
  shortterm,
  by = "match_id",
  all.x = TRUE,
  sort = FALSE
)

merged <- merged[order(merged$row_order_original), ]
merged$row_order_original <- NULL

if (nrow(merged) != nrow(base)) {
  stop(
    "Row count changed after merge. Before: ",
    nrow(base),
    ", after: ",
    nrow(merged)
  )
}

############################################################
# Check missingness in added variables
############################################################

added_vars <- setdiff(names(shortterm), "match_id")

missing_summary <- data.frame(
  variable = added_vars,
  missing_n = sapply(merged[, added_vars, drop = FALSE], function(x) sum(is.na(x))),
  missing_percent = sapply(
    merged[, added_vars, drop = FALSE],
    function(x) round(mean(is.na(x)) * 100, 2)
  ),
  stringsAsFactors = FALSE
)

write.csv(
  missing_summary,
  file.path(table_dir, "merged_shortterm_covariate_missing_summary.csv"),
  row.names = FALSE
)

############################################################
# Save
############################################################

output_file <- file.path(
  processed_dir,
  "atp_covariates_with_shortterm_2010_2025.csv"
)

write.csv(merged, output_file, row.names = FALSE)

cat("Finished merging short-term covariates.\n\n")

cat("Rows in base file:", nrow(base), "\n")
cat("Rows after merge:", nrow(merged), "\n")
cat("Columns in merged file:", ncol(merged), "\n\n")

cat("Missing summary for added short-term variables:\n")
print(missing_summary)

cat("\nFirst rows of selected variables:\n")

selected_cols <- c(
  "match_id",
  "date",
  "split",
  "player_a",
  "player_b",
  "y_a",
  "p_ttt_a",
  "p_book_final_a",
  "days_since_last_match_diff_a_filled",
  "last_match_games_diff_a_filled",
  "matches_last7_diff_a",
  "winrate_last7_diff_a",
  "games_last7_diff_a",
  "played_yesterday_diff_a",
  "back_to_back_diff_a"
)

selected_cols <- selected_cols[selected_cols %in% names(merged)]

print(head(merged[, selected_cols, drop = FALSE], 15))

cat("\nOutput saved to:\n")
cat(output_file, "\n")

