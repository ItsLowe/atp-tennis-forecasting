# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Build previous-match and seven-day rest and workload covariates.
# Source: 07_BuildShortTermCovariates.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 07.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 07 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

rm(list = ls())

input_file <- "data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv"

processed_dir <- "data/processed"
table_dir <- "outputs/tables"

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

df <- read.csv(input_file, stringsAsFactors = FALSE)
names(df) <- tolower(names(df))

df$date <- as.Date(df$date)
df$date_num <- as.integer(df$date)

df <- df[order(df$date_num, df$match_id), ]

required_cols <- c(
  "match_id",
  "date",
  "date_num",
  "player_a_id",
  "player_b_id",
  "player_a",
  "player_b",
  "y_a",
  "match_total_games"
)

missing_cols <- required_cols[!required_cols %in% names(df)]

if (length(missing_cols) > 0) {
  stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
}

df$match_total_games <- as.numeric(df$match_total_games)

############################################################
# Storage
############################################################

n <- nrow(df)

df$days_since_last_match_a <- NA_real_
df$days_since_last_match_b <- NA_real_
df$days_since_last_match_diff_a <- NA_real_
df$abs_days_since_last_match_diff <- NA_real_

df$played_yesterday_a <- NA_integer_
df$played_yesterday_b <- NA_integer_
df$played_yesterday_diff_a <- NA_integer_

df$back_to_back_a <- NA_integer_
df$back_to_back_b <- NA_integer_
df$back_to_back_diff_a <- NA_integer_

df$last_match_games_a <- NA_real_
df$last_match_games_b <- NA_real_
df$last_match_games_diff_a <- NA_real_
df$abs_last_match_games_diff <- NA_real_

df$matches_last7_a <- NA_real_
df$matches_last7_b <- NA_real_
df$matches_last7_diff_a <- NA_real_

df$wins_last7_a <- NA_real_
df$wins_last7_b <- NA_real_
df$wins_last7_diff_a <- NA_real_

df$winrate_last7_a <- NA_real_
df$winrate_last7_b <- NA_real_
df$winrate_last7_diff_a <- NA_real_

df$games_last7_a <- NA_real_
df$games_last7_b <- NA_real_
df$games_last7_diff_a <- NA_real_
df$abs_games_last7_diff <- NA_real_

############################################################
# Rolling state objects
############################################################

player_ids <- sort(unique(c(df$player_a_id, df$player_b_id)))
player_keys <- as.character(player_ids)

last_day <- setNames(rep(NA_real_, length(player_ids)), player_keys)
last_games <- setNames(rep(NA_real_, length(player_ids)), player_keys)

history_days <- setNames(vector("list", length(player_ids)), player_keys)
history_wins <- setNames(vector("list", length(player_ids)), player_keys)
history_games <- setNames(vector("list", length(player_ids)), player_keys)

for (pid in player_keys) {
  history_days[[pid]] <- numeric(0)
  history_wins[[pid]] <- numeric(0)
  history_games[[pid]] <- numeric(0)
}

############################################################
# Helper functions
############################################################

count_last_days <- function(days_vec, current_day, window = 7) {
  if (length(days_vec) == 0) return(0)
  sum(days_vec < current_day & days_vec >= current_day - window)
}

sum_last_days <- function(values_vec, days_vec, current_day, window = 7) {
  if (length(days_vec) == 0) return(0)
  
  idx <- which(days_vec < current_day & days_vec >= current_day - window)
  
  if (length(idx) == 0) return(0)
  
  sum(values_vec[idx], na.rm = TRUE)
}

safe_winrate <- function(wins, matches) {
  if (matches == 0) return(0.5)
  wins / matches
}

cap_days <- function(x, cap_value = 60) {
  ifelse(is.na(x), NA_real_, pmin(x, cap_value))
}

############################################################
# Construct pre-match rolling features
############################################################

unique_days <- sort(unique(df$date_num))

for (current_day in unique_days) {
  
  rows_today <- which(df$date_num == current_day)
  
  ##########################################################
  # Create features using information before today
  ##########################################################
  
  for (i in rows_today) {
    
    a_key <- as.character(df$player_a_id[i])
    b_key <- as.character(df$player_b_id[i])
    
    # Days since last match
    
    dslm_a <- current_day - last_day[a_key]
    dslm_b <- current_day - last_day[b_key]
    
    dslm_a <- cap_days(dslm_a, 60)
    dslm_b <- cap_days(dslm_b, 60)
    
    df$days_since_last_match_a[i] <- dslm_a
    df$days_since_last_match_b[i] <- dslm_b
    df$days_since_last_match_diff_a[i] <- dslm_a - dslm_b
    df$abs_days_since_last_match_diff[i] <- abs(dslm_a - dslm_b)
    
    # Yesterday and back-to-back indicators
    
    df$played_yesterday_a[i] <- as.integer(!is.na(dslm_a) && dslm_a == 1)
    df$played_yesterday_b[i] <- as.integer(!is.na(dslm_b) && dslm_b == 1)
    df$played_yesterday_diff_a[i] <- df$played_yesterday_a[i] - df$played_yesterday_b[i]
    
    df$back_to_back_a[i] <- as.integer(!is.na(dslm_a) && dslm_a <= 1)
    df$back_to_back_b[i] <- as.integer(!is.na(dslm_b) && dslm_b <= 1)
    df$back_to_back_diff_a[i] <- df$back_to_back_a[i] - df$back_to_back_b[i]
    
    # Last match games
    
    df$last_match_games_a[i] <- last_games[a_key]
    df$last_match_games_b[i] <- last_games[b_key]
    df$last_match_games_diff_a[i] <- last_games[a_key] - last_games[b_key]
    df$abs_last_match_games_diff[i] <- abs(last_games[a_key] - last_games[b_key])
    
    # Last 7 days workload and performance
    
    matches7_a <- count_last_days(history_days[[a_key]], current_day, 7)
    matches7_b <- count_last_days(history_days[[b_key]], current_day, 7)
    
    wins7_a <- sum_last_days(history_wins[[a_key]], history_days[[a_key]], current_day, 7)
    wins7_b <- sum_last_days(history_wins[[b_key]], history_days[[b_key]], current_day, 7)
    
    games7_a <- sum_last_days(history_games[[a_key]], history_days[[a_key]], current_day, 7)
    games7_b <- sum_last_days(history_games[[b_key]], history_days[[b_key]], current_day, 7)
    
    df$matches_last7_a[i] <- matches7_a
    df$matches_last7_b[i] <- matches7_b
    df$matches_last7_diff_a[i] <- matches7_a - matches7_b
    
    df$wins_last7_a[i] <- wins7_a
    df$wins_last7_b[i] <- wins7_b
    df$wins_last7_diff_a[i] <- wins7_a - wins7_b
    
    df$winrate_last7_a[i] <- safe_winrate(wins7_a, matches7_a)
    df$winrate_last7_b[i] <- safe_winrate(wins7_b, matches7_b)
    df$winrate_last7_diff_a[i] <- df$winrate_last7_a[i] - df$winrate_last7_b[i]
    
    df$games_last7_a[i] <- games7_a
    df$games_last7_b[i] <- games7_b
    df$games_last7_diff_a[i] <- games7_a - games7_b
    df$abs_games_last7_diff[i] <- abs(games7_a - games7_b)
  }
  
  ##########################################################
  #Update state after all predictions for today
  ##########################################################
  
  for (i in rows_today) {
    
    a_key <- as.character(df$player_a_id[i])
    b_key <- as.character(df$player_b_id[i])
    
    a_win <- ifelse(df$y_a[i] == 1, 1, 0)
    b_win <- ifelse(df$y_a[i] == 1, 0, 1)
    
    current_games <- df$match_total_games[i]
    
    history_days[[a_key]] <- c(history_days[[a_key]], current_day)
    history_days[[b_key]] <- c(history_days[[b_key]], current_day)
    
    history_wins[[a_key]] <- c(history_wins[[a_key]], a_win)
    history_wins[[b_key]] <- c(history_wins[[b_key]], b_win)
    
    history_games[[a_key]] <- c(history_games[[a_key]], current_games)
    history_games[[b_key]] <- c(history_games[[b_key]], current_games)
    
    last_day[a_key] <- current_day
    last_day[b_key] <- current_day
    
    last_games[a_key] <- current_games
    last_games[b_key] <- current_games
  }
}

############################################################
# Missing handling
############################################################

train_idx <- df$split == "train"

median_last_games <- median(
  c(df$last_match_games_a[train_idx], df$last_match_games_b[train_idx]),
  na.rm = TRUE
)

df$days_since_last_match_a_filled <- ifelse(
  is.na(df$days_since_last_match_a),
  60,
  df$days_since_last_match_a
)

df$days_since_last_match_b_filled <- ifelse(
  is.na(df$days_since_last_match_b),
  60,
  df$days_since_last_match_b
)

df$days_since_last_match_diff_a_filled <-
  df$days_since_last_match_a_filled - df$days_since_last_match_b_filled

df$abs_days_since_last_match_diff_filled <-
  abs(df$days_since_last_match_diff_a_filled)

df$last_match_games_a_missing <- as.integer(is.na(df$last_match_games_a))
df$last_match_games_b_missing <- as.integer(is.na(df$last_match_games_b))

df$last_match_games_a_filled <- ifelse(
  is.na(df$last_match_games_a),
  median_last_games,
  df$last_match_games_a
)

df$last_match_games_b_filled <- ifelse(
  is.na(df$last_match_games_b),
  median_last_games,
  df$last_match_games_b
)

df$last_match_games_diff_a_filled <-
  df$last_match_games_a_filled - df$last_match_games_b_filled

df$abs_last_match_games_diff_filled <-
  abs(df$last_match_games_diff_a_filled)

############################################################
# Save selected variables
############################################################

shortterm_cols <- c(
  "match_id",
  "days_since_last_match_a",
  "days_since_last_match_b",
  "days_since_last_match_diff_a",
  "abs_days_since_last_match_diff",
  "days_since_last_match_a_filled",
  "days_since_last_match_b_filled",
  "days_since_last_match_diff_a_filled",
  "abs_days_since_last_match_diff_filled",
  "played_yesterday_a",
  "played_yesterday_b",
  "played_yesterday_diff_a",
  "back_to_back_a",
  "back_to_back_b",
  "back_to_back_diff_a",
  "last_match_games_a",
  "last_match_games_b",
  "last_match_games_diff_a",
  "abs_last_match_games_diff",
  "last_match_games_a_missing",
  "last_match_games_b_missing",
  "last_match_games_a_filled",
  "last_match_games_b_filled",
  "last_match_games_diff_a_filled",
  "abs_last_match_games_diff_filled",
  "matches_last7_a",
  "matches_last7_b",
  "matches_last7_diff_a",
  "wins_last7_a",
  "wins_last7_b",
  "wins_last7_diff_a",
  "winrate_last7_a",
  "winrate_last7_b",
  "winrate_last7_diff_a",
  "games_last7_a",
  "games_last7_b",
  "games_last7_diff_a",
  "abs_games_last7_diff"
)

shortterm <- df[, shortterm_cols, drop = FALSE]

output_file <- file.path(
  processed_dir,
  "atp_shortterm_fatigue_covariates_2010_2025.csv"
)

write.csv(shortterm, output_file, row.names = FALSE)

############################################################
# Summary checks
############################################################

summary_cols <- setdiff(shortterm_cols, "match_id")

missing_summary <- data.frame(
  variable = summary_cols,
  missing_n = sapply(shortterm[, summary_cols, drop = FALSE], function(x) sum(is.na(x))),
  missing_percent = sapply(shortterm[, summary_cols, drop = FALSE], function(x) round(mean(is.na(x)) * 100, 2)),
  stringsAsFactors = FALSE
)

write.csv(
  missing_summary,
  file.path(table_dir, "shortterm_fatigue_missing_summary.csv"),
  row.names = FALSE
)

cat("Finished constructing short-term fatigue covariates.\n\n")

cat("Rows:", nrow(shortterm), "\n")
cat("Output saved to:\n")
cat(output_file, "\n\n")

cat("Median last match games used for first appearances:\n")
print(median_last_games)

cat("\nMissing summary:\n")
print(missing_summary)

cat("\nFirst rows:\n")
print(head(shortterm, 15))

