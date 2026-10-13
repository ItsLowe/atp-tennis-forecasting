# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Import annual workbooks, clean completed matches and normalize bookmaker probabilities.
# Source: 01_DataProcessing.R
# Working directory: repository root (not R/).
# Dependencies: readxl.
# Inputs: see reproducibility/dependencies.md, stage 01.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 01 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("Package 'readxl' is required. Install it with install.packages('readxl')")
}

input_dir  <- "data/raw/atp_odds_2010_2025"
output_dir <- "data/processed"

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

clean_colnames <- function(x) {
  x <- trimws(x)
  x <- gsub("[^A-Za-z0-9]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  tolower(x)
}

as_numeric_safe <- function(x) {
  if (is.numeric(x)) return(x)
  suppressWarnings(as.numeric(as.character(x)))
}

as_date_safe <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXct") || inherits(x, "POSIXt")) return(as.Date(x))
  if (is.numeric(x)) return(as.Date(x, origin = "1899-12-30"))
  out <- as.Date(x, format = "%Y-%m-%d")
  if (all(is.na(out))) out <- as.Date(x, format = "%d/%m/%Y")
  if (all(is.na(out))) out <- as.Date(x, format = "%m/%d/%Y")
  out
}

implied_prob_winner <- function(odds_w, odds_l) {
  odds_w <- as_numeric_safe(odds_w)
  odds_l <- as_numeric_safe(odds_l)
  ok <- !is.na(odds_w) & !is.na(odds_l) & odds_w > 1 & odds_l > 1
  p <- rep(NA_real_, length(odds_w))
  p[ok] <- (1 / odds_w[ok]) / ((1 / odds_w[ok]) + (1 / odds_l[ok]))
  p
}

process_one_file <- function(path) {
  message("Reading: ", basename(path))
  df <- as.data.frame(readxl::read_excel(path), stringsAsFactors = FALSE)
  names(df) <- clean_colnames(names(df))

  required_cols <- c("date", "winner", "loser", "comment")
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    stop("Missing required columns in ", basename(path), ": ", paste(missing_cols, collapse = ", "))
  }

  # Basic standardisation
  df$date <- as_date_safe(df$date)
  char_cols <- names(df)[sapply(df, is.character)]
  for (cc in char_cols) df[[cc]] <- trimws(df[[cc]])

  # Year from date, falling back to filename if needed
  df$year <- as.integer(format(df$date, "%Y"))
  if (all(is.na(df$year))) {
    yr <- regmatches(basename(path), regexpr("[0-9]{4}", basename(path)))
    if (length(yr) == 1) df$year <- as.integer(yr)
  }

  # Keep completed matches only. This removes retirements, walkovers, abandoned matches, etc.
  df <- df[tolower(df$comment) == "completed", , drop = FALSE]

  # Remove rows without essential player/date information
  df <- df[!is.na(df$date) & !is.na(df$winner) & !is.na(df$loser) &
             df$winner != "" & df$loser != "", , drop = FALSE]

  # Numeric columns that are useful before the match
  numeric_cols <- intersect(c("wrank", "lrank", "wpts", "lpts", "best_of"), names(df))
  for (cc in numeric_cols) df[[cc]] <- as_numeric_safe(df[[cc]])

  # Calculate bookmaker probabilities for every odds pair that exists.
  w_cols <- grep("^[a-z0-9]+w$", names(df), value = TRUE)
  prefixes <- sub("w$", "", w_cols)
  prefixes <- prefixes[paste0(prefixes, "l") %in% names(df)]

  # Exclude set-score columns automatically. This pattern should already avoid w1/l1.
  prefixes <- setdiff(prefixes, c("w", "l"))

  for (pref in prefixes) {
    w_col <- paste0(pref, "w")
    l_col <- paste0(pref, "l")
    df[[w_col]] <- as_numeric_safe(df[[w_col]])
    df[[l_col]] <- as_numeric_safe(df[[l_col]])
    df[[paste0("p_", pref, "_w")]] <- implied_prob_winner(df[[w_col]], df[[l_col]])
  }

  # Main bookmaker probability: B365 if available.
  if ("p_b365_w" %in% names(df)) {
    df$p_book_b365_w <- df$p_b365_w
  } else {
    df$p_book_b365_w <- NA_real_
  }

  # Average odds probability if AvgW/AvgL exist.
  if ("p_avg_w" %in% names(df)) {
    df$p_book_avgodds_w <- df$p_avg_w
  } else {
    df$p_book_avgodds_w <- NA_real_
  }

  # Exclude max and avg because they are aggregates, not individual bookmakers.
  p_cols <- grep("^p_[a-z0-9]+_w$", names(df), value = TRUE)
  p_cols_market <- p_cols[!grepl("^p_(max|avg)_w$", p_cols)]

  if (length(p_cols_market) > 0) {
    df$p_book_market_mean_w <- rowMeans(df[, p_cols_market, drop = FALSE], na.rm = TRUE)
    df$p_book_market_mean_w[is.nan(df$p_book_market_mean_w)] <- NA_real_
    df$n_bookmakers_available <- rowSums(!is.na(df[, p_cols_market, drop = FALSE]))
  } else {
    df$p_book_market_mean_w <- NA_real_
    df$n_bookmakers_available <- 0L
  }

  # Use B365 as the main bookmaker benchmark where possible, otherwise market mean.
  df$p_book_main_w <- df$p_book_b365_w
  missing_main <- is.na(df$p_book_main_w)
  df$p_book_main_w[missing_main] <- df$p_book_market_mean_w[missing_main]

  # Pre-match covariates. Do not include post-match statistics such as scores or set scores.
  keep <- c(
    "year", "date", "location", "tournament", "series", "court", "surface", "round", "best_of",
    "winner", "loser", "wrank", "lrank", "wpts", "lpts",
    "b365w", "b365l", "avgw", "avgl", "maxw", "maxl",
    "p_book_b365_w", "p_book_avgodds_w", "p_book_market_mean_w", "p_book_main_w", "n_bookmakers_available"
  )
  keep <- keep[keep %in% names(df)]
  df <- df[, keep, drop = FALSE]

  # Construct basic covariates. These are known before the match.
  if (all(c("wrank", "lrank") %in% names(df))) {
    df$rank_diff_winner_minus_loser <- df$wrank - df$lrank
    df$rank_ratio_winner_to_loser <- df$wrank / df$lrank
  }
  if (all(c("wpts", "lpts") %in% names(df))) {
    df$points_diff_winner_minus_loser <- df$wpts - df$lpts
    df$log_points_diff_winner_minus_loser <- log1p(df$wpts) - log1p(df$lpts)
  }

  df
}

files <- list.files(input_dir, pattern = "\\.xls[x]?$", full.names = TRUE)
files <- files[order(files)]

if (length(files) == 0) {
  stop("No .xls or .xlsx files found in input_dir: ", input_dir)
}

all_matches <- do.call(rbind, lapply(files, process_one_file))

all_matches_with_odds <- all_matches[!is.na(all_matches$p_book_main_w), , drop = FALSE]

write.csv(all_matches, file.path(output_dir, "atp_odds_clean_all_completed.csv"), row.names = FALSE)
write.csv(all_matches_with_odds, file.path(output_dir, "atp_odds_clean_with_bookmaker_prob.csv"), row.names = FALSE)

cat("\nFinished.\n")
cat("Completed matches total:", nrow(all_matches), "\n")
cat("Completed matches with bookmaker probability:", nrow(all_matches_with_odds), "\n")
cat("Years:", paste(range(all_matches$year, na.rm = TRUE), collapse = " to "), "\n")
cat("Bookmaker probability coverage:", round(mean(!is.na(all_matches$p_book_main_w)) * 100, 2), "%\n")

cat("\nMatches by year:\n")
print(table(all_matches$year))

cat("\nBookmaker coverage by year:\n")
coverage_by_year <- aggregate(!is.na(p_book_main_w) ~ year, data = all_matches, FUN = mean)
names(coverage_by_year)[2] <- "coverage"
coverage_by_year$coverage <- round(coverage_by_year$coverage * 100, 2)
print(coverage_by_year)
