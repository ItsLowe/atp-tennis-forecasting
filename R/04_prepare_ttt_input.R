# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Set the final bookmaker benchmark and create chronological match and player identifiers.
# Source: 04_PrepareTTTInput.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 04.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 04 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.
rm(list = ls())

input_file <- "data/processed/atp_odds_modelling_ready_with_scores.csv"

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

############################################################
#final bookmaker probability
############################################################

if ("p_book_market_mean_a" %in% names(df)) {
  df$p_book_final_a <- df$p_book_market_mean_a
} else {
  df$p_book_final_a <- df$p_book_main_a
}

############################################################
#Check required columns
############################################################

required_cols <- c(
  "date",
  "year",
  "player_a",
  "player_b",
  "y_a",
  "p_book_final_a",
  "winner",
  "loser"
)

missing_cols <- required_cols[!required_cols %in% names(df)]

if (length(missing_cols) > 0) {
  stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
}

############################################################
#Keep valid rows
############################################################

df <- df[!is.na(df$date), ]
df <- df[!is.na(df$player_a) & !is.na(df$player_b), ]
df <- df[df$player_a != "" & df$player_b != "", ]
df <- df[!is.na(df$y_a), ]
df <- df[!is.na(df$p_book_final_a), ]
df <- df[df$p_book_final_a > 0 & df$p_book_final_a < 1, ]

############################################################
#Create stable player IDs
############################################################

# Player names are in abbreviated format, for example "Federer R."
# This is fine for the main 2010–2025 analysis as long as the same
# spelling is used consistently within the dataset.

all_players <- sort(unique(c(df$player_a, df$player_b)))

player_lookup <- data.frame(
  player_name = all_players,
  player_id = seq_along(all_players),
  stringsAsFactors = FALSE
)

df$player_a_id <- player_lookup$player_id[
  match(df$player_a, player_lookup$player_name)
]

df$player_b_id <- player_lookup$player_id[
  match(df$player_b, player_lookup$player_name)
]

############################################################
#Create match ID and order by time
############################################################

# The original row order may not always be chronological.
# TTT must update ratings only using past matches, so sorting is essential.

df <- df[order(df$date, df$tournament, df$round, df$player_a, df$player_b), ]

df$match_id <- seq_len(nrow(df))

############################################################
#Keep modelling variables
############################################################
base_keep_cols <- c(
  "match_id",
  "date",
  "year",
  "split",
  "tournament",
  "series",
  "court",
  "surface",
  "round",
  "best_of",
  "player_a",
  "player_b",
  "player_a_id",
  "player_b_id",
  "y_a",
  "winner",
  "loser",
  "wrank",
  "lrank",
  "wpts",
  "lpts",
  "match_total_games",
  "p_book_final_a",
  "p_book_main_a",
  "p_book_b365_a",
  "p_book_avgodds_a",
  "p_book_market_mean_a"
)

score_cols <- c(
  "w1", "l1",
  "w2", "l2",
  "w3", "l3",
  "w4", "l4",
  "w5", "l5"
)

score_cols <- score_cols[score_cols %in% names(df)]

duration_cols <- c(
  "minutes",
  "mins",
  "duration",
  "match_minutes"
)

duration_cols <- duration_cols[duration_cols %in% names(df)]

keep_cols <- c(
  base_keep_cols,
  score_cols,
  duration_cols
)

keep_cols <- keep_cols[keep_cols %in% names(df)]

ttt_input <- df[, keep_cols, drop = FALSE]

############################################################
#Basic checks
############################################################

if (any(is.na(ttt_input$player_a_id)) || any(is.na(ttt_input$player_b_id))) {
  stop("Some player IDs are missing.")
}

if (any(ttt_input$player_a_id == ttt_input$player_b_id)) {
  stop("Some matches have the same player as player A and player B.")
}

if (any(duplicated(ttt_input$match_id))) {
  stop("Duplicate match_id found.")
}

############################################################
#Summary table
############################################################

summary_table <- data.frame(
  item = c(
    "matches",
    "players",
    "first_year",
    "last_year",
    "train_matches",
    "validation_matches",
    "test_matches",
    "bookmaker_logloss_reference"
  ),
  value = c(
    nrow(ttt_input),
    length(all_players),
    min(ttt_input$year),
    max(ttt_input$year),
    sum(ttt_input$split == "train"),
    sum(ttt_input$split == "validation"),
    sum(ttt_input$split == "test"),
    NA
  ),
  stringsAsFactors = FALSE
)

write.csv(
  ttt_input,
  file.path(processed_dir, "atp_ttt_input_2010_2025.csv"),
  row.names = FALSE
)

write.csv(
  player_lookup,
  file.path(processed_dir, "player_lookup_2010_2025.csv"),
  row.names = FALSE
)

write.csv(
  summary_table,
  file.path(table_dir, "ttt_input_summary.csv"),
  row.names = FALSE
)

cat("Finished preparing TTT input data.\n\n")

cat("Matches:", nrow(ttt_input), "\n")
cat("Players:", length(all_players), "\n")
cat("Years:", min(ttt_input$year), "to", max(ttt_input$year), "\n\n")

cat("Matches by split:\n")
print(table(ttt_input$split))

cat("\nMatches by year:\n")
print(table(ttt_input$year))

cat("\nScore columns retained in TTT input:\n")
print(score_cols)

cat("\nDuration columns retained in TTT input:\n")
print(duration_cols)

cat("\nColumns related to score in TTT input:\n")
print(
  names(ttt_input)[
    grepl("w1|l1|w2|l2|w3|l3|w4|l4|w5|l5|match_total_games", names(ttt_input))
  ]
)

cat("\nMissing match_total_games:\n")
print(sum(is.na(ttt_input$match_total_games)))

cat("\nFirst rows of TTT input:\n")
print(head(ttt_input, 10))

