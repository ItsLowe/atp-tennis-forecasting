# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Add pre-match identity labels, head-to-head and common-opponent features.
# Source: 09_BuildMatchupCovariates.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 09.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 09 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.
rm(list = ls())

input_file <- "data/processed/atp_covariates_with_shortterm_2010_2025.csv"

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
df$date_num <- as.integer(df$date)

############################################################
# Add match_total_games if it is not in the current file
############################################################

if (!"match_total_games" %in% names(df)) {
  
  score_file <- "data/processed/atp_ttt_genuine_yearly_predictions_2010_2025.csv"
  
  if (!file.exists(score_file)) {
    stop(
      "match_total_games is not in the input file, and score file was not found: ",
      score_file
    )
  }
  
  score_df <- read.csv(score_file, stringsAsFactors = FALSE)
  names(score_df) <- tolower(names(score_df))
  
  if (!all(c("match_id", "match_total_games") %in% names(score_df))) {
    stop("score_file does not contain match_id and match_total_games.")
  }
  
  score_df <- score_df[, c("match_id", "match_total_games"), drop = FALSE]
  score_df <- score_df[!duplicated(score_df$match_id), ]
  
  df$row_order_original <- seq_len(nrow(df))
  
  df <- merge(
    df,
    score_df,
    by = "match_id",
    all.x = TRUE,
    sort = FALSE
  )
  
  df <- df[order(df$row_order_original), ]
  df$row_order_original <- NULL
}

df$match_total_games <- as.numeric(df$match_total_games)

if (any(is.na(df$match_total_games))) {
  stop("Some match_total_games values are missing after merge.")
}

df <- df[order(df$date_num, df$match_id), ]

required_cols <- c(
  "match_id",
  "date",
  "date_num",
  "player_a",
  "player_b",
  "player_a_id",
  "player_b_id",
  "y_a",
  "match_total_games"
)

missing_cols <- required_cols[!required_cols %in% names(df)]

if (length(missing_cols) > 0) {
  stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
}

############################################################
# Player identity variables
############################################################

df$player_a_factor <- df$player_a
df$player_b_factor <- df$player_b

############################################################
# Storage for new features
############################################################

n <- nrow(df)

df$h2h_matches_before <- 0
df$h2h_wins_a_before <- 0
df$h2h_wins_b_before <- 0
df$h2h_winrate_a <- 0.5
df$h2h_winrate_b <- 0.5
df$h2h_winrate_diff_a <- 0
df$h2h_games_a_before <- 0
df$h2h_games_b_before <- 0
df$h2h_games_diff_a <- 0

df$common_opp_count <- 0
df$common_opp_winrate_a <- 0.5
df$common_opp_winrate_b <- 0.5
df$common_opp_winrate_diff_a <- 0
df$common_opp_games_a <- 0
df$common_opp_games_b <- 0
df$common_opp_games_diff_a <- 0

############################################################
# Rolling state objects
############################################################

player_ids <- sort(unique(c(df$player_a_id, df$player_b_id)))
player_keys <- as.character(player_ids)

# Head-to-head records stored by unordered pair key
h2h_matches <- new.env(hash = TRUE, parent = emptyenv())
h2h_wins <- new.env(hash = TRUE, parent = emptyenv())
h2h_games <- new.env(hash = TRUE, parent = emptyenv())

# Player vs opponent records
# For each player, store named vectors by opponent id
player_opp_matches <- setNames(vector("list", length(player_keys)), player_keys)
player_opp_wins <- setNames(vector("list", length(player_keys)), player_keys)
player_opp_games <- setNames(vector("list", length(player_keys)), player_keys)

for (pid in player_keys) {
  player_opp_matches[[pid]] <- numeric(0)
  player_opp_wins[[pid]] <- numeric(0)
  player_opp_games[[pid]] <- numeric(0)
}

make_pair_key <- function(id1, id2) {
  ids <- sort(c(as.character(id1), as.character(id2)))
  paste(ids[1], ids[2], sep = "_")
}

get_env_value <- function(env, key, default = 0) {
  if (exists(key, envir = env, inherits = FALSE)) {
    get(key, envir = env)
  } else {
    default
  }
}

set_env_value <- function(env, key, value) {
  assign(key, value, envir = env)
}

safe_rate <- function(wins, matches) {
  if (matches <= 0) return(0.5)
  wins / matches
}

get_named_value <- function(x, name, default = 0) {
  name <- as.character(name)
  if (name %in% names(x)) {
    return(x[[name]])
  } else {
    return(default)
  }
}

set_named_value <- function(x, name, value) {
  name <- as.character(name)
  x[[name]] <- value
  return(x)
}

############################################################
# Construct features without look-ahead
############################################################

unique_days <- sort(unique(df$date_num))

for (current_day in unique_days) {
  
  rows_today <- which(df$date_num == current_day)
  
  ##########################################################
  # Compute features using information before today
  ##########################################################
  
  for (i in rows_today) {
    
    a <- as.character(df$player_a_id[i])
    b <- as.character(df$player_b_id[i])
    
    pair_key <- make_pair_key(a, b)
    
    pair_matches <- get_env_value(h2h_matches, pair_key, 0)
    
    a_pair_wins <- get_env_value(h2h_wins, paste(pair_key, a, sep = "_"), 0)
    b_pair_wins <- get_env_value(h2h_wins, paste(pair_key, b, sep = "_"), 0)
    
    a_pair_games <- get_env_value(h2h_games, paste(pair_key, a, sep = "_"), 0)
    b_pair_games <- get_env_value(h2h_games, paste(pair_key, b, sep = "_"), 0)
    
    df$h2h_matches_before[i] <- pair_matches
    df$h2h_wins_a_before[i] <- a_pair_wins
    df$h2h_wins_b_before[i] <- b_pair_wins
    df$h2h_winrate_a[i] <- safe_rate(a_pair_wins, pair_matches)
    df$h2h_winrate_b[i] <- safe_rate(b_pair_wins, pair_matches)
    df$h2h_winrate_diff_a[i] <- df$h2h_winrate_a[i] - df$h2h_winrate_b[i]
    df$h2h_games_a_before[i] <- a_pair_games
    df$h2h_games_b_before[i] <- b_pair_games
    df$h2h_games_diff_a[i] <- a_pair_games - b_pair_games
    
    # Common opponent features
    
    opps_a <- names(player_opp_matches[[a]])
    opps_b <- names(player_opp_matches[[b]])
    
    common_opps <- intersect(opps_a, opps_b)
    
    # Exclude each other as opponents, so this is not just direct H2H again
    common_opps <- setdiff(common_opps, c(a, b))
    
    df$common_opp_count[i] <- length(common_opps)
    
    if (length(common_opps) > 0) {
      
      a_matches_common <- 0
      b_matches_common <- 0
      a_wins_common <- 0
      b_wins_common <- 0
      a_games_common <- 0
      b_games_common <- 0
      
      for (opp in common_opps) {
        a_matches_common <- a_matches_common + get_named_value(player_opp_matches[[a]], opp, 0)
        b_matches_common <- b_matches_common + get_named_value(player_opp_matches[[b]], opp, 0)
        
        a_wins_common <- a_wins_common + get_named_value(player_opp_wins[[a]], opp, 0)
        b_wins_common <- b_wins_common + get_named_value(player_opp_wins[[b]], opp, 0)
        
        a_games_common <- a_games_common + get_named_value(player_opp_games[[a]], opp, 0)
        b_games_common <- b_games_common + get_named_value(player_opp_games[[b]], opp, 0)
      }
      
      df$common_opp_winrate_a[i] <- safe_rate(a_wins_common, a_matches_common)
      df$common_opp_winrate_b[i] <- safe_rate(b_wins_common, b_matches_common)
      df$common_opp_winrate_diff_a[i] <-
        df$common_opp_winrate_a[i] - df$common_opp_winrate_b[i]
      
      df$common_opp_games_a[i] <- a_games_common
      df$common_opp_games_b[i] <- b_games_common
      df$common_opp_games_diff_a[i] <- a_games_common - b_games_common
    }
  }
  
  ##########################################################
  # Update histories after all features for today
  ##########################################################
  
  for (i in rows_today) {
    
    a <- as.character(df$player_a_id[i])
    b <- as.character(df$player_b_id[i])
    
    pair_key <- make_pair_key(a, b)
    
    a_win <- ifelse(df$y_a[i] == 1, 1, 0)
    b_win <- ifelse(df$y_a[i] == 1, 0, 1)
    
    games <- as.numeric(df$match_total_games[i])
    
    if (is.na(games)) {
      games <- 0
    }
    
    # Update direct H2H
    
    old_pair_matches <- get_env_value(h2h_matches, pair_key, 0)
    set_env_value(h2h_matches, pair_key, old_pair_matches + 1)
    
    old_a_wins <- get_env_value(h2h_wins, paste(pair_key, a, sep = "_"), 0)
    old_b_wins <- get_env_value(h2h_wins, paste(pair_key, b, sep = "_"), 0)
    
    set_env_value(h2h_wins, paste(pair_key, a, sep = "_"), old_a_wins + a_win)
    set_env_value(h2h_wins, paste(pair_key, b, sep = "_"), old_b_wins + b_win)
    
    old_a_games <- get_env_value(h2h_games, paste(pair_key, a, sep = "_"), 0)
    old_b_games <- get_env_value(h2h_games, paste(pair_key, b, sep = "_"), 0)
    
    set_env_value(h2h_games, paste(pair_key, a, sep = "_"), old_a_games + games)
    set_env_value(h2h_games, paste(pair_key, b, sep = "_"), old_b_games + games)
    
    # Update player vs opponent history
    
    player_opp_matches[[a]] <- set_named_value(
      player_opp_matches[[a]],
      b,
      get_named_value(player_opp_matches[[a]], b, 0) + 1
    )
    
    player_opp_matches[[b]] <- set_named_value(
      player_opp_matches[[b]],
      a,
      get_named_value(player_opp_matches[[b]], a, 0) + 1
    )
    
    player_opp_wins[[a]] <- set_named_value(
      player_opp_wins[[a]],
      b,
      get_named_value(player_opp_wins[[a]], b, 0) + a_win
    )
    
    player_opp_wins[[b]] <- set_named_value(
      player_opp_wins[[b]],
      a,
      get_named_value(player_opp_wins[[b]], a, 0) + b_win
    )
    
    player_opp_games[[a]] <- set_named_value(
      player_opp_games[[a]],
      b,
      get_named_value(player_opp_games[[a]], b, 0) + games
    )
    
    player_opp_games[[b]] <- set_named_value(
      player_opp_games[[b]],
      a,
      get_named_value(player_opp_games[[b]], a, 0) + games
    )
  }
}

############################################################
# Simple transformations
############################################################

df$log_h2h_matches_before <- log1p(df$h2h_matches_before)
df$log_common_opp_count <- log1p(df$common_opp_count)

df$h2h_exists <- as.integer(df$h2h_matches_before > 0)
df$common_opp_exists <- as.integer(df$common_opp_count > 0)

############################################################
# Save output and checks
############################################################

output_file <- file.path(
  processed_dir,
  "atp_covariates_with_identity_h2h_common_2010_2025.csv"
)

write.csv(df, output_file, row.names = FALSE)

new_vars <- c(
  "player_a_factor",
  "player_b_factor",
  "h2h_matches_before",
  "h2h_winrate_diff_a",
  "h2h_games_diff_a",
  "h2h_exists",
  "log_h2h_matches_before",
  "common_opp_count",
  "common_opp_winrate_diff_a",
  "common_opp_games_diff_a",
  "common_opp_exists",
  "log_common_opp_count"
)

summary_table <- data.frame(
  variable = new_vars,
  missing_n = sapply(df[, new_vars, drop = FALSE], function(x) sum(is.na(x))),
  missing_percent = sapply(
    df[, new_vars, drop = FALSE],
    function(x) round(mean(is.na(x)) * 100, 2)
  ),
  stringsAsFactors = FALSE
)

write.csv(
  summary_table,
  file.path(table_dir, "identity_h2h_common_missing_summary.csv"),
  row.names = FALSE
)

cat("Finished adding player identity, H2H, and common opponent features.\n\n")
cat("Rows:", nrow(df), "\n")
cat("Output saved to:\n")
cat(output_file, "\n\n")

cat("New feature missing summary:\n")
print(summary_table)

cat("\nH2H summary:\n")
print(summary(df[, c(
  "h2h_matches_before",
  "h2h_winrate_diff_a",
  "h2h_games_diff_a",
  "log_h2h_matches_before"
)]))

cat("\nCommon opponent summary:\n")
print(summary(df[, c(
  "common_opp_count",
  "common_opp_winrate_diff_a",
  "common_opp_games_diff_a",
  "log_common_opp_count"
)]))

cat("\nProportion with previous H2H:\n")
print(mean(df$h2h_exists))

cat("\nProportion with common opponents:\n")
print(mean(df$common_opp_exists))

cat("\nFirst rows of new variables:\n")
print(head(df[, c(
  "match_id",
  "date",
  "player_a",
  "player_b",
  "h2h_matches_before",
  "h2h_winrate_diff_a",
  "common_opp_count",
  "common_opp_winrate_diff_a"
)], 20))

