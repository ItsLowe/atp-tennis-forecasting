# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Merge annual set scores into modelling data and calculate the total-games workload proxy.
# Source: 03_AddScoreData.R
# Working directory: repository root (not R/).
# Dependencies: readxl.
# Inputs: see reproducibility/dependencies.md, stage 03.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 03 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

rm(list = ls())

library(readxl)


ready_file <- "data/processed/atp_odds_modelling_ready.csv"

raw_dir <- "data/raw/atp_odds_2010_2025"

processed_dir <- "data/processed"
table_dir <- "outputs/tables"

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(ready_file)) {
  stop("Ready file not found: ", ready_file)
}

############################################################
#Read existing modelling-ready data
############################################################

ready <- read.csv(ready_file, stringsAsFactors = FALSE)
names(ready) <- tolower(names(ready))

ready$date <- as.Date(ready$date)

ready$row_order_original <- seq_len(nrow(ready))

############################################################
# Read all yearly raw files
############################################################

years <- 2010:2025

key_cols <- c("date", "tournament", "winner", "loser")

score_cols_full <- c(
  "w1", "l1",
  "w2", "l2",
  "w3", "l3",
  "w4", "l4",
  "w5", "l5"
)

duration_candidates <- c(
  "minutes",
  "mins",
  "duration",
  "match_minutes"
)

target_cols <- c(
  key_cols,
  "round",
  score_cols_full,
  duration_candidates
)

raw_list <- list()

convert_raw_date <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  
  out <- as.Date(rep(NA, length(x)))
  
  suppressWarnings({
    numeric_x <- as.numeric(x)
  })
  
  is_excel_date <- !is.na(numeric_x) & numeric_x > 20000 & numeric_x < 60000
  
  out[is_excel_date] <- as.Date(numeric_x[is_excel_date], origin = "1899-12-30")
  
  is_not_excel_date <- !is_excel_date
  
  out[is_not_excel_date] <- suppressWarnings(as.Date(x[is_not_excel_date]))
  
  if (any(is.na(out) & is_not_excel_date)) {
    out[is.na(out) & is_not_excel_date] <- suppressWarnings(
      as.Date(x[is.na(out) & is_not_excel_date], format = "%d/%m/%Y")
    )
  }
  
  if (any(is.na(out) & is_not_excel_date)) {
    out[is.na(out) & is_not_excel_date] <- suppressWarnings(
      as.Date(x[is.na(out) & is_not_excel_date], format = "%m/%d/%Y")
    )
  }
  
  return(out)
}

for (yr in years) {
  
  file_xls <- file.path(raw_dir, paste0(yr, ".xls"))
  file_xlsx <- file.path(raw_dir, paste0(yr, ".xlsx"))
  
  if (file.exists(file_xls)) {
    raw_file <- file_xls
  } else if (file.exists(file_xlsx)) {
    raw_file <- file_xlsx
  } else {
    warning("Raw file not found for year ", yr)
    next
  }
  
  cat("Reading:", raw_file, "\n")
  
  tmp <- read_excel(raw_file, col_types = "text")
  tmp <- as.data.frame(tmp, stringsAsFactors = FALSE)
  names(tmp) <- tolower(names(tmp))
  
  cat("Columns in", yr, ":\n")
  print(names(tmp))
  
  missing_needed <- target_cols[!target_cols %in% names(tmp)]
  
  if (length(missing_needed) > 0) {
    for (v in missing_needed) {
      tmp[[v]] <- NA_character_
    }
  }
  
  tmp <- tmp[, target_cols, drop = FALSE]
  
  tmp$year_file <- yr
  
  raw_list[[as.character(yr)]] <- tmp
}

if (length(raw_list) == 0) {
  stop("No yearly raw files were read. Please check raw_dir.")
}

raw_all <- do.call(rbind, raw_list)

raw_all$date <- convert_raw_date(raw_all$date)

cat("\nRows in raw yearly files:", nrow(raw_all), "\n")
cat("Date missing after conversion:", sum(is.na(raw_all$date)), "\n")

############################################################
#Standardise date and text fields
############################################################

text_cols <- c("tournament", "winner", "loser", "round")

for (v in text_cols) {
  if (v %in% names(raw_all)) {
    raw_all[[v]] <- trimws(as.character(raw_all[[v]]))
  }
  if (v %in% names(ready)) {
    ready[[v]] <- trimws(as.character(ready[[v]]))
  }
}

############################################################
# Identify score and duration columns
############################################################

score_cols <- c(
  "w1", "l1",
  "w2", "l2",
  "w3", "l3",
  "w4", "l4",
  "w5", "l5"
)

score_cols <- score_cols[score_cols %in% names(raw_all)]

duration_candidates <- c(
  "minutes",
  "mins",
  "duration",
  "match_minutes"
)

duration_cols <- duration_candidates[duration_candidates %in% names(raw_all)]

cat("\nScore columns found:\n")
print(score_cols)

cat("\nDuration columns found:\n")
print(duration_cols)

if (length(score_cols) == 0) {
  stop("No score columns found in raw yearly files.")
}

############################################################
# Build score lookup
############################################################

key_cols <- c("date", "tournament", "winner", "loser")

missing_ready_keys <- key_cols[!key_cols %in% names(ready)]
missing_raw_keys <- key_cols[!key_cols %in% names(raw_all)]

if (length(missing_ready_keys) > 0) {
  stop("Missing key columns in ready data: ", paste(missing_ready_keys, collapse = ", "))
}

if (length(missing_raw_keys) > 0) {
  stop("Missing key columns in raw data: ", paste(missing_raw_keys, collapse = ", "))
}

lookup_cols <- c(key_cols, score_cols, duration_cols)

score_lookup <- raw_all[, lookup_cols, drop = FALSE]

dup_raw_keys <- duplicated(score_lookup[, key_cols])

cat("\nDuplicated raw keys:", sum(dup_raw_keys), "\n")

score_lookup <- score_lookup[!dup_raw_keys, ]

############################################################
# Merge score columns back
############################################################

ready_with_scores <- merge(
  ready,
  score_lookup,
  by = key_cols,
  all.x = TRUE,
  sort = FALSE
)

ready_with_scores <- ready_with_scores[
  order(ready_with_scores$row_order_original),
]

if (nrow(ready_with_scores) != nrow(ready)) {
  stop(
    "Row count changed after merge. Before: ",
    nrow(ready),
    ", after: ",
    nrow(ready_with_scores)
  )
}

############################################################
# Compute match total games
############################################################

for (v in score_cols) {
  ready_with_scores[[v]] <- suppressWarnings(as.numeric(ready_with_scores[[v]]))
}

ready_with_scores$match_total_games <- rowSums(
  ready_with_scores[, score_cols, drop = FALSE],
  na.rm = TRUE
)

ready_with_scores$match_total_games[
  ready_with_scores$match_total_games == 0
] <- NA_real_

ready_with_scores$has_score <- !is.na(ready_with_scores$match_total_games)

score_coverage <- mean(ready_with_scores$has_score) * 100

cat("\nRows in modelling-ready data:", nrow(ready), "\n")
cat("Rows after merge:", nrow(ready_with_scores), "\n")
cat("Score coverage:", round(score_coverage, 2), "%\n")

############################################################
# Summary table
############################################################

score_summary <- data.frame(
  variable = c(score_cols, "match_total_games"),
  missing_n = c(
    sapply(ready_with_scores[, score_cols, drop = FALSE], function(x) sum(is.na(x))),
    sum(is.na(ready_with_scores$match_total_games))
  ),
  missing_percent = c(
    sapply(
      ready_with_scores[, score_cols, drop = FALSE],
      function(x) round(mean(is.na(x)) * 100, 2)
    ),
    round(mean(is.na(ready_with_scores$match_total_games)) * 100, 2)
  ),
  stringsAsFactors = FALSE
)

write.csv(
  score_summary,
  file.path(table_dir, "score_columns_missing_summary.csv"),
  row.names = FALSE
)

############################################################
# Save output
############################################################

ready_with_scores$row_order_original <- NULL

output_file <- file.path(
  processed_dir,
  "atp_odds_modelling_ready_with_scores.csv"
)

write.csv(
  ready_with_scores,
  output_file,
  row.names = FALSE
)

cat("\nScore missing summary:\n")
print(score_summary)

cat("\nFirst rows with scores:\n")
print(
  head(
    ready_with_scores[
      ,
      c(
        "date",
        "tournament",
        "winner",
        "loser",
        score_cols,
        "match_total_games"
      )
    ],
    10
  )
)

cat("\nOutput saved to:\n")
cat(output_file, "\n")
