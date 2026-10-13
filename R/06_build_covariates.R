# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Build pre-match ranking, form, surface, experience, rest and workload covariates.
# Source: 06_BuildCovariates.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 06.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 06 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

rm(list = ls())

input_file <- "data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv"

processed_dir <- "data/processed"
table_dir <- "outputs/tables"

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file)
}

df <- read.csv(input_file, stringsAsFactors = FALSE)
names(df) <- tolower(names(df))

df$date <- as.Date(df$date)
df$year <- as.integer(format(df$date, "%Y"))
df$date_num <- as.integer(df$date)

df <- df[order(df$date_num, df$match_id), ]

required_cols <- c(
  "match_id",
  "date",
  "date_num",
  "split",
  "player_a",
  "player_b",
  "player_a_id",
  "player_b_id",
  "y_a",
  "surface",
  "p_ttt_a",
  "p_book_final_a"
)

missing_cols <- required_cols[!required_cols %in% names(df)]

if (length(missing_cols) > 0) {
  stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
}

############################################################
#Convert ranking and point variables to player A and B
############################################################

# wrank and lrank refer to the actual winner and loser.
# Because player_a can be either winner or loser, we convert them into
# rank_a and rank_b.

if ("wrank" %in% names(df) & "lrank" %in% names(df)) {
  df$rank_a <- ifelse(df$y_a == 1, df$wrank, df$lrank)
  df$rank_b <- ifelse(df$y_a == 1, df$lrank, df$wrank)
} else {
  df$rank_a <- NA_real_
  df$rank_b <- NA_real_
}

if ("wpts" %in% names(df) & "lpts" %in% names(df)) {
  df$points_a <- ifelse(df$y_a == 1, df$wpts, df$lpts)
  df$points_b <- ifelse(df$y_a == 1, df$lpts, df$wpts)
} else {
  df$points_a <- NA_real_
  df$points_b <- NA_real_
}

df$rank_advantage_a <- log(df$rank_b) - log(df$rank_a)
df$rank_gap_abs <- abs(df$rank_a - df$rank_b)

df$points_advantage_a <- log(df$points_a + 1) - log(df$points_b + 1)
df$points_gap_abs <- abs(df$points_a - df$points_b)

############################################################
#Initialise storage for rolling covariates
############################################################

n <- nrow(df)

df$matches_played_a <- NA_real_
df$matches_played_b <- NA_real_
df$matches_played_diff_a <- NA_real_

df$career_winrate_a <- NA_real_
df$career_winrate_b <- NA_real_
df$career_winrate_diff_a <- NA_real_

df$recent5_winrate_a <- NA_real_
df$recent5_winrate_b <- NA_real_
df$recent5_winrate_diff_a <- NA_real_

df$recent10_winrate_a <- NA_real_
df$recent10_winrate_b <- NA_real_
df$recent10_winrate_diff_a <- NA_real_

df$surface_matches_a <- NA_real_
df$surface_matches_b <- NA_real_
df$surface_matches_diff_a <- NA_real_

df$surface_winrate_a <- NA_real_
df$surface_winrate_b <- NA_real_
df$surface_winrate_diff_a <- NA_real_

df$rest_days_a <- NA_real_
df$rest_days_b <- NA_real_
df$rest_days_diff_a <- NA_real_
df$abs_rest_days_diff <- NA_real_

df$matches_last30_a <- NA_real_
df$matches_last30_b <- NA_real_
df$matches_last30_diff_a <- NA_real_

df$new_player_a <- NA_integer_
df$new_player_b <- NA_integer_

############################################################
#Rolling state objects
############################################################

all_ids <- sort(unique(c(df$player_a_id, df$player_b_id)))
n_players <- max(all_ids)

surface_levels <- sort(unique(df$surface))
surface_levels <- surface_levels[!is.na(surface_levels)]

n_surfaces <- length(surface_levels)

surface_index <- match(df$surface, surface_levels)

overall_matches <- rep(0, n_players)
overall_wins <- rep(0, n_players)

surface_matches <- matrix(0, nrow = n_players, ncol = n_surfaces)
surface_wins <- matrix(0, nrow = n_players, ncol = n_surfaces)

last_played_day <- rep(NA_real_, n_players)

recent_results <- vector("list", n_players)
match_days <- vector("list", n_players)

for (i in seq_len(n_players)) {
  recent_results[[i]] <- numeric(0)
  match_days[[i]] <- numeric(0)
}

############################################################
#Helper functions for rolling features
############################################################

smooth_rate <- function(wins, matches, prior_wins = 1, prior_matches = 2) {
  return((wins + prior_wins) / (matches + prior_matches))
}

recent_rate <- function(x, k) {
  if (length(x) == 0) {
    return(0.5)
  }
  
  x_tail <- tail(x, k)
  return(mean(x_tail))
}

count_last_days <- function(days_vec, current_day, window = 30) {
  if (length(days_vec) == 0) {
    return(0)
  }
  
  return(sum(days_vec < current_day & days_vec >= current_day - window))
}

get_rest_days <- function(last_day, current_day) {
  if (is.na(last_day)) {
    return(NA_real_)
  }
  
  return(current_day - last_day)
}

cap_rest_days <- function(x, cap_value = 60) {
  ifelse(is.na(x), NA_real_, pmin(x, cap_value))
}

############################################################
#Construct rolling covariates
############################################################

unique_days <- sort(unique(df$date_num))

for (current_day in unique_days) {
  
  rows_today <- which(df$date_num == current_day)
  
  
  for (row_id in rows_today) {
    
    a_id <- df$player_a_id[row_id]
    b_id <- df$player_b_id[row_id]
    s_id <- surface_index[row_id]
    
    # Overall match experience
    
    df$matches_played_a[row_id] <- overall_matches[a_id]
    df$matches_played_b[row_id] <- overall_matches[b_id]
    df$matches_played_diff_a[row_id] <- overall_matches[a_id] - overall_matches[b_id]
    
    # Career win rate with simple smoothing
    
    career_a <- smooth_rate(overall_wins[a_id], overall_matches[a_id])
    career_b <- smooth_rate(overall_wins[b_id], overall_matches[b_id])
    
    df$career_winrate_a[row_id] <- career_a
    df$career_winrate_b[row_id] <- career_b
    df$career_winrate_diff_a[row_id] <- career_a - career_b
    
    # Recent form
    
    r5_a <- recent_rate(recent_results[[a_id]], 5)
    r5_b <- recent_rate(recent_results[[b_id]], 5)
    
    r10_a <- recent_rate(recent_results[[a_id]], 10)
    r10_b <- recent_rate(recent_results[[b_id]], 10)
    
    df$recent5_winrate_a[row_id] <- r5_a
    df$recent5_winrate_b[row_id] <- r5_b
    df$recent5_winrate_diff_a[row_id] <- r5_a - r5_b
    
    df$recent10_winrate_a[row_id] <- r10_a
    df$recent10_winrate_b[row_id] <- r10_b
    df$recent10_winrate_diff_a[row_id] <- r10_a - r10_b
    
    # Surface-specific performance with smoothing
    
    if (!is.na(s_id)) {
      sm_a <- surface_matches[a_id, s_id]
      sm_b <- surface_matches[b_id, s_id]
      
      sw_a <- surface_wins[a_id, s_id]
      sw_b <- surface_wins[b_id, s_id]
      
      surface_rate_a <- smooth_rate(sw_a, sm_a)
      surface_rate_b <- smooth_rate(sw_b, sm_b)
      
      df$surface_matches_a[row_id] <- sm_a
      df$surface_matches_b[row_id] <- sm_b
      df$surface_matches_diff_a[row_id] <- sm_a - sm_b
      
      df$surface_winrate_a[row_id] <- surface_rate_a
      df$surface_winrate_b[row_id] <- surface_rate_b
      df$surface_winrate_diff_a[row_id] <- surface_rate_a - surface_rate_b
    }
    
    # Rest days and recent workload
    
    rest_a <- get_rest_days(last_played_day[a_id], current_day)
    rest_b <- get_rest_days(last_played_day[b_id], current_day)
    
    rest_a_capped <- cap_rest_days(rest_a, 60)
    rest_b_capped <- cap_rest_days(rest_b, 60)
    
    df$rest_days_a[row_id] <- rest_a_capped
    df$rest_days_b[row_id] <- rest_b_capped
    
    df$rest_days_diff_a[row_id] <- rest_a_capped - rest_b_capped
    df$abs_rest_days_diff[row_id] <- abs(rest_a_capped - rest_b_capped)
    
    load_a <- count_last_days(match_days[[a_id]], current_day, 30)
    load_b <- count_last_days(match_days[[b_id]], current_day, 30)
    
    df$matches_last30_a[row_id] <- load_a
    df$matches_last30_b[row_id] <- load_b
    df$matches_last30_diff_a[row_id] <- load_a - load_b
    
    # New player indicators
    
    df$new_player_a[row_id] <- as.integer(overall_matches[a_id] == 0)
    df$new_player_b[row_id] <- as.integer(overall_matches[b_id] == 0)
  }
  
  for (row_id in rows_today) {
    
    a_id <- df$player_a_id[row_id]
    b_id <- df$player_b_id[row_id]
    s_id <- surface_index[row_id]
    
    y <- df$y_a[row_id]
    
    a_win <- ifelse(y == 1, 1, 0)
    b_win <- ifelse(y == 1, 0, 1)
    
    overall_matches[a_id] <- overall_matches[a_id] + 1
    overall_matches[b_id] <- overall_matches[b_id] + 1
    
    overall_wins[a_id] <- overall_wins[a_id] + a_win
    overall_wins[b_id] <- overall_wins[b_id] + b_win
    
    if (!is.na(s_id)) {
      surface_matches[a_id, s_id] <- surface_matches[a_id, s_id] + 1
      surface_matches[b_id, s_id] <- surface_matches[b_id, s_id] + 1
      
      surface_wins[a_id, s_id] <- surface_wins[a_id, s_id] + a_win
      surface_wins[b_id, s_id] <- surface_wins[b_id, s_id] + b_win
    }
    
    recent_results[[a_id]] <- c(recent_results[[a_id]], a_win)
    recent_results[[b_id]] <- c(recent_results[[b_id]], b_win)
    
    match_days[[a_id]] <- c(match_days[[a_id]], current_day)
    match_days[[b_id]] <- c(match_days[[b_id]], current_day)
    
    last_played_day[a_id] <- current_day
    last_played_day[b_id] <- current_day
  }
}

############################################################
#Additional transformed variables
############################################################

df$rest_days_a_filled <- ifelse(is.na(df$rest_days_a), 60, df$rest_days_a)
df$rest_days_b_filled <- ifelse(is.na(df$rest_days_b), 60, df$rest_days_b)

df$rest_days_diff_a_filled <- df$rest_days_a_filled - df$rest_days_b_filled
df$abs_rest_days_diff_filled <- abs(df$rest_days_diff_a_filled)

df$log_matches_played_a <- log(df$matches_played_a + 1)
df$log_matches_played_b <- log(df$matches_played_b + 1)
df$log_matches_played_diff_a <- df$log_matches_played_a - df$log_matches_played_b

df$log_surface_matches_a <- log(df$surface_matches_a + 1)
df$log_surface_matches_b <- log(df$surface_matches_b + 1)
df$log_surface_matches_diff_a <- df$log_surface_matches_a - df$log_surface_matches_b

# TTT based variables

df$ttt_prob_logit_a <- log(df$p_ttt_a / (1 - df$p_ttt_a))

if ("ttt_mu_diff_a_minus_b" %in% names(df)) {
  df$ttt_mu_advantage_a <- df$ttt_mu_diff_a_minus_b
}

if ("ttt_combined_uncertainty" %in% names(df)) {
  df$ttt_uncertainty <- df$ttt_combined_uncertainty
}

############################################################
#Basic missing value summary
############################################################

covariate_cols <- c(
  "rank_advantage_a",
  "points_advantage_a",
  "rank_gap_abs",
  "points_gap_abs",
  "career_winrate_diff_a",
  "recent5_winrate_diff_a",
  "recent10_winrate_diff_a",
  "surface_winrate_diff_a",
  "log_matches_played_diff_a",
  "log_surface_matches_diff_a",
  "rest_days_diff_a_filled",
  "abs_rest_days_diff_filled",
  "matches_last30_diff_a",
  "new_player_a",
  "new_player_b",
  "ttt_prob_logit_a",
  "ttt_mu_advantage_a",
  "ttt_uncertainty",
  "surface",
  "series",
  "round"
)

covariate_cols <- covariate_cols[covariate_cols %in% names(df)]

missing_summary <- data.frame(
  variable = covariate_cols,
  missing_n = sapply(df[, covariate_cols, drop = FALSE], function(x) sum(is.na(x))),
  missing_percent = sapply(df[, covariate_cols, drop = FALSE], function(x) round(mean(is.na(x)) * 100, 2)),
  stringsAsFactors = FALSE
)

write.csv(
  missing_summary,
  file.path(table_dir, "covariate_missing_summary.csv"),
  row.names = FALSE
)

############################################################
#Numeric covariate summary
############################################################

numeric_cols <- covariate_cols[sapply(df[, covariate_cols, drop = FALSE], is.numeric)]

summary_list <- list()

for (v in numeric_cols) {
  x <- df[[v]]
  
  summary_list[[v]] <- data.frame(
    variable = v,
    n = sum(!is.na(x)),
    mean = mean(x, na.rm = TRUE),
    sd = sd(x, na.rm = TRUE),
    min = min(x, na.rm = TRUE),
    q25 = quantile(x, 0.25, na.rm = TRUE),
    median = median(x, na.rm = TRUE),
    q75 = quantile(x, 0.75, na.rm = TRUE),
    max = max(x, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

covariate_summary <- do.call(rbind, summary_list)
rownames(covariate_summary) <- NULL

write.csv(
  covariate_summary,
  file.path(table_dir, "covariate_summary.csv"),
  row.names = FALSE
)

############################################################
#Save covariate dataset
############################################################

write.csv(
  df,
  file.path(processed_dir, "atp_covariates_2010_2025.csv"),
  row.names = FALSE
)

############################################################
#Print results
############################################################

cat("Finished constructing covariates.\n\n")

cat("Rows:", nrow(df), "\n")
cat("Columns:", ncol(df), "\n\n")

cat("Missing value summary for selected covariates:\n")
print(missing_summary)

cat("\nNumeric covariate summary:\n")
print(covariate_summary)

cat("\nFirst rows of selected covariates:\n")
print(
  head(
    df[
      ,
      c(
        "match_id",
        "date",
        "split",
        "player_a",
        "player_b",
        "y_a",
        "surface",
        "series",
        "rank_advantage_a",
        "points_advantage_a",
        "recent5_winrate_diff_a",
        "surface_winrate_diff_a",
        "rest_days_diff_a_filled",
        "matches_last30_diff_a",
        "ttt_mu_advantage_a",
        "ttt_uncertainty",
        "p_ttt_a",
        "p_book_final_a"
      )
    ],
    10
  )
)

