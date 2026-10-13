# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Fix Player A/B orientation, assign chronological splits and evaluate preliminary bookmaker probabilities.
# Source: 02_PrepareBookmakerData.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 02.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 02 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

rm(list = ls())

input_file <- "data/processed/atp_odds_clean_with_bookmaker_prob.csv"

processed_dir <- "data/processed"
table_dir <- "outputs/tables"
figure_dir <- "outputs/figures"

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(input_file)) {
  stop("Input file not found. Please check the file path: ", input_file)
}

df <- read.csv(input_file, stringsAsFactors = FALSE)

# Make column names lower case for consistency
names(df) <- tolower(names(df))

# Check required columns
required_cols <- c("date", "winner", "loser", "p_book_main_w")

missing_cols <- required_cols[!required_cols %in% names(df)]

if (length(missing_cols) > 0) {
  stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
}

############################################################
#Basic date handling
############################################################
df$date <- as.Date(df$date)

if (any(is.na(df$date))) {
  stop("Some dates could not be converted to Date format. Please check df$date.")
}

df$year <- as.integer(format(df$date, "%Y"))

############################################################
#Keep matches with valid bookmaker probability
############################################################

df <- df[!is.na(df$p_book_main_w), ]
df <- df[df$p_book_main_w > 0 & df$p_book_main_w < 1, ]

cat("Matches with valid bookmaker probability:", nrow(df), "\n")

############################################################
#Construct a neutral player A / player B format
############################################################

set.seed(123)

player_a_is_winner <- sample(c(TRUE, FALSE), size = nrow(df), replace = TRUE)

df$player_a <- ifelse(player_a_is_winner, df$winner, df$loser)
df$player_b <- ifelse(player_a_is_winner, df$loser, df$winner)

df$y_a <- ifelse(player_a_is_winner, 1, 0)

df$p_book_main_a <- ifelse(
  player_a_is_winner,
  df$p_book_main_w,
  1 - df$p_book_main_w
)

alt_prob_cols <- c(
  "p_book_b365_w",
  "p_book_avgodds_w",
  "p_book_market_mean_w"
)

for (col in alt_prob_cols) {
  if (col %in% names(df)) {
    new_col <- sub("_w$", "_a", col)
    df[[new_col]] <- ifelse(
      player_a_is_winner,
      df[[col]],
      1 - df[[col]]
    )
  }
}

############################################################
#Create time split
############################################################

df$split <- NA_character_

df$split[df$year >= 2010 & df$year <= 2021] <- "train"
df$split[df$year == 2022] <- "validation"
df$split[df$year >= 2023 & df$year <= 2025] <- "test"

df <- df[!is.na(df$split), ]

############################################################
#Evaluation functions
############################################################

clip_prob <- function(p, eps = 1e-15) {
  p[p < eps] <- eps
  p[p > 1 - eps] <- 1 - eps
  return(p)
}

log_loss <- function(y, p) {
  p <- clip_prob(p)
  return(-mean(y * log(p) + (1 - y) * log(1 - p), na.rm = TRUE))
}

brier_score <- function(y, p) {
  return(mean((y - p)^2, na.rm = TRUE))
}

accuracy_score <- function(y, p) {
  pred <- ifelse(p >= 0.5, 1, 0)
  return(mean(pred == y, na.rm = TRUE))
}

mean_prob_winner <- function(y, p) {
  return(mean(ifelse(y == 1, p, 1 - p), na.rm = TRUE))
}

evaluate_predictions <- function(data, prob_col) {
  ok <- !is.na(data[[prob_col]]) & !is.na(data$y_a)
  d <- data[ok, ]
  
  if (nrow(d) == 0) {
    return(data.frame(
      n = 0,
      logloss = NA_real_,
      brier = NA_real_,
      accuracy = NA_real_,
      mean_predicted_prob_for_actual_winner = NA_real_
    ))
  }
  
  y <- d$y_a
  p <- d[[prob_col]]
  
  out <- data.frame(
    n = nrow(d),
    logloss = log_loss(y, p),
    brier = brier_score(y, p),
    accuracy = accuracy_score(y, p),
    mean_predicted_prob_for_actual_winner = mean_prob_winner(y, p)
  )
  
  return(out)
}

evaluate_by_group <- function(data, group_col, prob_col) {
  groups <- sort(unique(data[[group_col]]))
  groups <- groups[!is.na(groups)]
  
  result_list <- list()
  
  for (g in groups) {
    d_g <- data[data[[group_col]] == g & !is.na(data[[group_col]]), ]
    metrics <- evaluate_predictions(d_g, prob_col)
    metrics[[group_col]] <- g
    result_list[[as.character(g)]] <- metrics
  }
  
  out <- do.call(rbind, result_list)
  rownames(out) <- NULL
  
  out <- out[, c(group_col, setdiff(names(out), group_col))]
  
  return(out)
}

############################################################
#Overall bookmaker baseline
############################################################

overall_metrics <- evaluate_predictions(df, "p_book_main_a")

write.csv(
  overall_metrics,
  file.path(table_dir, "bookmaker_overall_metrics.csv"),
  row.names = FALSE
)

cat("\nOverall bookmaker metrics:\n")
print(overall_metrics)

############################################################
#Compare available bookmaker probability sources
############################################################

prob_source_cols <- c(
  "p_book_main_a",
  "p_book_b365_a",
  "p_book_avgodds_a",
  "p_book_market_mean_a"
)

prob_source_cols <- prob_source_cols[prob_source_cols %in% names(df)]

source_results <- list()

for (prob_col in prob_source_cols) {
  metrics <- evaluate_predictions(df, prob_col)
  metrics$probability_source <- prob_col
  source_results[[prob_col]] <- metrics
}

source_comparison <- do.call(rbind, source_results)
rownames(source_comparison) <- NULL

source_comparison <- source_comparison[
  ,
  c(
    "probability_source",
    "n",
    "logloss",
    "brier",
    "accuracy",
    "mean_predicted_prob_for_actual_winner"
  )
]

write.csv(
  source_comparison,
  file.path(table_dir, "bookmaker_probability_source_comparison.csv"),
  row.names = FALSE
)

cat("\nProbability source comparison:\n")
print(source_comparison)

############################################################
#Metrics by split
############################################################

metrics_by_split <- evaluate_by_group(df, "split", "p_book_main_a")

write.csv(
  metrics_by_split,
  file.path(table_dir, "bookmaker_metrics_by_split.csv"),
  row.names = FALSE
)

cat("\nMetrics by split:\n")
print(metrics_by_split)

############################################################
#Metrics by year
############################################################

metrics_by_year <- evaluate_by_group(df, "year", "p_book_main_a")

write.csv(
  metrics_by_year,
  file.path(table_dir, "bookmaker_metrics_by_year.csv"),
  row.names = FALSE
)

cat("\nMetrics by year:\n")
print(metrics_by_year)

############################################################
#Metrics by surface, court, series, round
############################################################

if ("surface" %in% names(df)) {
  metrics_by_surface <- evaluate_by_group(df, "surface", "p_book_main_a")
  
  write.csv(
    metrics_by_surface,
    file.path(table_dir, "bookmaker_metrics_by_surface.csv"),
    row.names = FALSE
  )
}

if ("court" %in% names(df)) {
  metrics_by_court <- evaluate_by_group(df, "court", "p_book_main_a")
  
  write.csv(
    metrics_by_court,
    file.path(table_dir, "bookmaker_metrics_by_court.csv"),
    row.names = FALSE
  )
}

if ("series" %in% names(df)) {
  metrics_by_series <- evaluate_by_group(df, "series", "p_book_main_a")
  
  write.csv(
    metrics_by_series,
    file.path(table_dir, "bookmaker_metrics_by_series.csv"),
    row.names = FALSE
  )
}

if ("round" %in% names(df)) {
  metrics_by_round <- evaluate_by_group(df, "round", "p_book_main_a")
  
  write.csv(
    metrics_by_round,
    file.path(table_dir, "bookmaker_metrics_by_round.csv"),
    row.names = FALSE
  )
}

############################################################
#Calibration table
############################################################

calibration_bins <- seq(0, 1, by = 0.1)

df$book_bin <- cut(
  df$p_book_main_a,
  breaks = calibration_bins,
  include.lowest = TRUE,
  right = TRUE
)

cal_groups <- levels(df$book_bin)

calibration_list <- list()

for (b in cal_groups) {
  d_b <- df[df$book_bin == b & !is.na(df$book_bin), ]
  
  if (nrow(d_b) > 0) {
    calibration_list[[b]] <- data.frame(
      bin = b,
      n = nrow(d_b),
      mean_predicted_probability = mean(d_b$p_book_main_a, na.rm = TRUE),
      observed_win_rate = mean(d_b$y_a, na.rm = TRUE)
    )
  }
}

calibration_table <- do.call(rbind, calibration_list)
rownames(calibration_table) <- NULL

write.csv(
  calibration_table,
  file.path(table_dir, "bookmaker_calibration_bins.csv"),
  row.names = FALSE
)

cat("\nCalibration table:\n")
print(calibration_table)

############################################################
#Save modelling ready dataset
############################################################

write.csv(
  df,
  file.path(processed_dir, "atp_odds_modelling_ready.csv"),
  row.names = FALSE
)

cat("\nSaved modelling ready dataset:\n")
cat(file.path(processed_dir, "atp_odds_modelling_ready.csv"), "\n")

############################################################
#Figures
############################################################

# Figure 1. Bookmaker log loss by year

png(
  filename = file.path(figure_dir, "bookmaker_logloss_by_year.png"),
  width = 1100,
  height = 700
)

plot(
  metrics_by_year$year,
  metrics_by_year$logloss,
  type = "b",
  pch = 16,
  xlab = "Year",
  ylab = "Log loss",
  main = "Bookmaker log loss by year"
)

grid()

dev.off()

# Figure 2. Bookmaker accuracy by year

png(
  filename = file.path(figure_dir, "bookmaker_accuracy_by_year.png"),
  width = 1100,
  height = 700
)

plot(
  metrics_by_year$year,
  metrics_by_year$accuracy,
  type = "b",
  pch = 16,
  xlab = "Year",
  ylab = "Accuracy",
  main = "Bookmaker accuracy by year",
  ylim = c(0.5, 1)
)

grid()

dev.off()

# Figure 3. Calibration plot

png(
  filename = file.path(figure_dir, "bookmaker_calibration.png"),
  width = 900,
  height = 900
)

plot(
  calibration_table$mean_predicted_probability,
  calibration_table$observed_win_rate,
  type = "b",
  pch = 16,
  xlim = c(0, 1),
  ylim = c(0, 1),
  xlab = "Mean predicted probability",
  ylab = "Observed win rate",
  main = "Bookmaker calibration"
)

abline(0, 1, lty = 2)
grid()

dev.off()

############################################################
#Finish
############################################################

cat("\nFinished bookmaker baseline analysis.\n")
cat("Tables saved to:", table_dir, "\n")
cat("Figures saved to:", figure_dir, "\n")

