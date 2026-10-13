# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Evaluate final disagreement subsets and training-defined TTT uncertainty quartiles without fitting models.
# Source: 14_FinalDiagnostics.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 14.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 14 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.
rm(list = ls())

input_file <-
  "data/processed/atp_nn_primary_maxit1000_predictions_2010_2025.csv"

primary_nn_run_summary_file <- file.path(
  "outputs",
  "tables",
  "primary_nn_maxit1000",
  "nn_primary_maxit1000_run_summary.csv"
)

processed_dir <- "data/processed"
table_dir <- file.path(
  "outputs",
  "tables",
  "final_disagreement_maxit1000"
)

dir.create(
  processed_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  table_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

diagnostic_data_file <- file.path(
  processed_dir,
  "atp_final_disagreement_diagnostics_primary_nn_maxit1000_2010_2025.csv"
)

disagreement_summary_file <- file.path(
  table_dir,
  "final_disagreement_count_summary.csv"
)

performance_file <- file.path(
  table_dir,
  "final_model_disagreement_results_by_split.csv"
)

gap_recovery_file <- file.path(
  table_dir,
  "final_disagreement_gap_recovery.csv"
)

quartile_breaks_file <- file.path(
  table_dir,
  "final_ttt_uncertainty_training_quartile_breaks.csv"
)

quartile_counts_file <- file.path(
  table_dir,
  "final_disagreement_ttt_uncertainty_quartile_counts.csv"
)

quartile_results_file <- file.path(
  table_dir,
  "final_disagreement_by_ttt_uncertainty_quartile.csv"
)

############################################################
# Read data
############################################################

if (!file.exists(input_file)) {
  stop(
    "Input file not found: ",
    input_file
  )
}

if (!file.exists(primary_nn_run_summary_file)) {
  stop(
    "Primary-NN run summary not found: ",
    primary_nn_run_summary_file
  )
}

primary_nn_run_summary <- read.csv(
  primary_nn_run_summary_file,
  stringsAsFactors = FALSE
)

required_summary_cols <- c(
  "maxit",
  "validation_grid_nonconverged",
  "rolling_nonconverged",
  "test_matches",
  "primary_nn_maxit1000_test_logloss",
  "prediction_output_file"
)

missing_summary_cols <- required_summary_cols[
  !required_summary_cols %in% names(primary_nn_run_summary)
]

if (
  nrow(primary_nn_run_summary) != 1L ||
  length(missing_summary_cols) > 0L
) {
  stop(
    "The Primary-NN run summary is incomplete or has an unexpected structure."
  )
}

if (
  primary_nn_run_summary$maxit[1] != 1000L ||
  primary_nn_run_summary$validation_grid_nonconverged[1] != 0L ||
  primary_nn_run_summary$rolling_nonconverged[1] != 0L
) {
  stop(
    "The Primary-NN run summary does not describe the fully converged ",
    "maxit = 1000 run."
  )
}

if (
  basename(primary_nn_run_summary$prediction_output_file[1]) !=
    basename(input_file)
) {
  stop(
    "The Primary-NN run summary points to a different prediction file."
  )
}

df <- read.csv(
  input_file,
  stringsAsFactors = FALSE
)

names(df) <- tolower(
  names(df)
)

df$date <- as.Date(
  df$date
)

if (any(is.na(df$date))) {
  stop(
    "Some dates could not be converted to Date format."
  )
}

df$year <- as.integer(
  format(df$date, "%Y")
)

df$split <- tolower(
  trimws(df$split)
)

df$y_a <- as.integer(
  df$y_a
)

############################################################
# Models included in the diagnostics
############################################################

model_cols <- c(
  "Bookmaker" =
    "p_book_final_a",
  
  "TTT baseline" =
    "p_ttt_a",
  
  "Logistic full + short-term" =
    "p_logit_full_shortterm_a",
  
  "Logistic full + short-term + H2H" =
    "p_logit_full_shortterm_h2h_a",
  
  "Logistic full + short-term + H2H + common opponent" =
    "p_logit_full_shortterm_h2h_common_a",
  
  "NN + short-term" =
    "p_nn_shortterm_a",
  
  "NN + short-term + H2H" =
    "p_nn_shortterm_h2h_a",
  
  "NN + short-term + common opponent" =
    "p_nn_shortterm_common_a",
  
  "NN + short-term + H2H + common opponent" =
    "p_nn_shortterm_h2h_common_a"
)

model_roles <- c(
  "Bookmaker" =
    "External benchmark",
  
  "TTT baseline" =
    "Rating baseline",
  
  "Logistic full + short-term" =
    "Logistic candidate",
  
  "Logistic full + short-term + H2H" =
    "Primary logistic model",
  
  "Logistic full + short-term + H2H + common opponent" =
    "Logistic extension",
  
  "NN + short-term" =
    "Primary neural-network model",
  
  "NN + short-term + H2H" =
    "Neural-network extension",
  
  "NN + short-term + common opponent" =
    "Neural-network extension",
  
  "NN + short-term + H2H + common opponent" =
    "Neural-network extension"
)

primary_logistic_name <-
  "Logistic full + short-term + H2H"

primary_nn_name <-
  "NN + short-term"

############################################################
# Validate required columns
############################################################

required_cols <- c(
  "match_id",
  "date",
  "year",
  "split",
  "player_a",
  "player_b",
  "y_a",
  "ttt_uncertainty",
  "p_nn_shortterm_a_maxit300",
  unname(model_cols)
)

missing_cols <- required_cols[
  !required_cols %in% names(df)
]

if (length(missing_cols) > 0) {
  stop(
    "Missing required columns: ",
    paste(
      missing_cols,
      collapse = ", "
    )
  )
}

if (any(duplicated(df$match_id))) {
  stop(
    "Duplicate match_id values were found."
  )
}

if (any(!df$split %in% c(
  "train",
  "validation",
  "test"
))) {
  stop(
    "Unexpected split values were found."
  )
}

observed_split_counts <- table(
  factor(
    df$split,
    levels = c(
      "train",
      "validation",
      "test"
    )
  )
)

expected_split_counts <- c(
  train = 28890L,
  validation = 2539L,
  test = 7725L
)

if (
  !identical(
    as.integer(observed_split_counts),
    as.integer(expected_split_counts)
  )
) {
  stop(
    "Unexpected split counts. Expected train/validation/test = ",
    paste(expected_split_counts, collapse = "/"),
    "."
  )
}

if (
  primary_nn_run_summary$test_matches[1] !=
    expected_split_counts["test"]
) {
  stop(
    "The Primary-NN run summary contains an unexpected test-match count."
  )
}

if (
  any(is.na(df$y_a)) ||
  any(!df$y_a %in% c(0L, 1L))
) {
  stop(
    "y_a must contain only 0 and 1."
  )
}

if (
  any(is.na(df$ttt_uncertainty)) ||
  any(!is.finite(df$ttt_uncertainty)) ||
  any(df$ttt_uncertainty < 0)
) {
  stop(
    "ttt_uncertainty contains invalid values."
  )
}

############################################################
# Probability checks
############################################################

clip_prob <- function(
    p,
    eps = 1e-15
) {
  pmin(
    pmax(p, eps),
    1 - eps
  )
}

prediction_check <- data.frame(
  model = names(model_cols),
  variable = unname(model_cols),
  missing_n = NA_integer_,
  nonfinite_n = NA_integer_,
  outside_zero_one_n = NA_integer_,
  stringsAsFactors = FALSE
)

for (j in seq_along(model_cols)) {
  v <- unname(model_cols[j])
  
  prediction_check$missing_n[j] <-
    sum(is.na(df[[v]]))
  
  prediction_check$nonfinite_n[j] <-
    sum(
      !is.finite(df[[v]]) &
        !is.na(df[[v]])
    )
  
  prediction_check$outside_zero_one_n[j] <-
    sum(
      (
        df[[v]] < 0 |
          df[[v]] > 1
      ),
      na.rm = TRUE
    )
}

if (
  any(prediction_check$missing_n > 0) ||
  any(prediction_check$nonfinite_n > 0) ||
  any(prediction_check$outside_zero_one_n > 0)
) {
  print(prediction_check)
  
  stop(
    "At least one prediction column contains invalid values."
  )
}

for (v in unname(model_cols)) {
  df[[v]] <- clip_prob(
    df[[v]]
  )
}

if (
  any(!is.finite(df$p_nn_shortterm_a_maxit300)) ||
  any(
    df$p_nn_shortterm_a_maxit300 < 0 |
      df$p_nn_shortterm_a_maxit300 > 1
  )
) {
  stop(
    "The preserved maxit = 300 Primary-NN probabilities are invalid."
  )
}

if (
  max(
    abs(
      df$p_nn_shortterm_a -
        df$p_nn_shortterm_a_maxit300
    )
  ) <= 1e-15
) {
  stop(
    "The Primary-NN probabilities are identical to the preserved maxit = 300 ",
    "values. Check that the final maxit = 1000 prediction file is being used."
  )
}

############################################################
# Evaluation functions
############################################################

single_logloss <- function(
    y,
    p
) {
  p <- clip_prob(p)
  
  -(
    y * log(p) +
      (1 - y) * log(1 - p)
  )
}

log_loss <- function(
    y,
    p
) {
  mean(
    single_logloss(y, p),
    na.rm = TRUE
  )
}

brier_score <- function(
    y,
    p
) {
  mean(
    (y - p)^2,
    na.rm = TRUE
  )
}

accuracy_score <- function(
    y,
    p
) {
  predicted_outcome <- as.integer(
    p >= 0.5
  )
  
  mean(
    predicted_outcome == y,
    na.rm = TRUE
  )
}

mean_prob_winner <- function(
    y,
    p
) {
  mean(
    ifelse(
      y == 1,
      p,
      1 - p
    ),
    na.rm = TRUE
  )
}

evaluate_predictions <- function(
    data,
    prob_col
) {
  valid_rows <- (
    !is.na(data[[prob_col]]) &
      !is.na(data$y_a)
  )
  
  d <- data[
    valid_rows,
    ,
    drop = FALSE
  ]
  
  if (nrow(d) == 0) {
    return(
      data.frame(
        n = 0,
        logloss = NA_real_,
        brier = NA_real_,
        accuracy = NA_real_,
        mean_predicted_prob_for_actual_winner =
          NA_real_
      )
    )
  }
  
  data.frame(
    n = nrow(d),
    
    logloss = log_loss(
      d$y_a,
      d[[prob_col]]
    ),
    
    brier = brier_score(
      d$y_a,
      d[[prob_col]]
    ),
    
    accuracy = accuracy_score(
      d$y_a,
      d[[prob_col]]
    ),
    
    mean_predicted_prob_for_actual_winner =
      mean_prob_winner(
        d$y_a,
        d[[prob_col]]
      )
  )
}

evaluate_models <- function(
    data,
    subset_name,
    split_name
) {
  output_list <- vector(
    "list",
    length(model_cols)
  )
  
  for (j in seq_along(model_cols)) {
    model_name <- names(model_cols)[j]
    prob_col <- unname(model_cols[j])
    
    metrics <- evaluate_predictions(
      data,
      prob_col
    )
    
    metrics$model <- model_name
    metrics$model_role <-
      unname(model_roles[model_name])
    metrics$subset <- subset_name
    metrics$split <- split_name
    
    output_list[[j]] <- metrics
  }
  
  output <- do.call(
    rbind,
    output_list
  )
  
  rownames(output) <- NULL
  
  output[
    ,
    c(
      "subset",
      "split",
      "model",
      "model_role",
      "n",
      "logloss",
      "brier",
      "accuracy",
      "mean_predicted_prob_for_actual_winner"
    )
  ]
}

############################################################
#Define disagreement indicators
############################################################

df$book_pred_a <- as.integer(
  df$p_book_final_a >= 0.5
)

df$ttt_pred_a <- as.integer(
  df$p_ttt_a >= 0.5
)

df$book_correct <- as.integer(
  df$book_pred_a == df$y_a
)

df$ttt_correct <- as.integer(
  df$ttt_pred_a == df$y_a
)

df$direction_disagreement <- as.integer(
  df$book_pred_a != df$ttt_pred_a
)

df$bookmaker_correct_ttt_wrong <- as.integer(
  df$book_correct == 1 &
    df$ttt_correct == 0
)

df$ttt_correct_bookmaker_wrong <- as.integer(
  df$ttt_correct == 1 &
    df$book_correct == 0
)

df$both_correct <- as.integer(
  df$book_correct == 1 &
    df$ttt_correct == 1
)

df$both_wrong <- as.integer(
  df$book_correct == 0 &
    df$ttt_correct == 0
)

# In every direction-disagreement match, exactly one of the
# two forecasts must identify the actual winner.

invalid_disagreement_rows <- (
  df$direction_disagreement == 1 &
    (
      df$book_correct +
        df$ttt_correct
    ) != 1
)

if (any(invalid_disagreement_rows)) {
  stop(
    "Invalid direction-disagreement classification found."
  )
}

############################################################
# Disagreement count summary
############################################################

summarise_disagreement <- function(
    data,
    split_name
) {
  disagreement_n <- sum(
    data$direction_disagreement == 1
  )
  
  bookmaker_wins <- sum(
    data$bookmaker_correct_ttt_wrong == 1
  )
  
  ttt_wins <- sum(
    data$ttt_correct_bookmaker_wrong == 1
  )
  
  bookmaker_share <- if (
    disagreement_n > 0
  ) {
    bookmaker_wins / disagreement_n
  } else {
    NA_real_
  }
  
  ttt_share <- if (
    disagreement_n > 0
  ) {
    ttt_wins / disagreement_n
  } else {
    NA_real_
  }
  
  data.frame(
    split = split_name,
    n = nrow(data),
    
    direction_disagreement_n =
      disagreement_n,
    
    direction_disagreement_rate =
      mean(
        data$direction_disagreement == 1
      ),
    
    bookmaker_correct_ttt_wrong =
      bookmaker_wins,
    
    ttt_correct_bookmaker_wrong =
      ttt_wins,
    
    bookmaker_correct_share_within_disagreement =
      bookmaker_share,
    
    ttt_correct_share_within_disagreement =
      ttt_share,
    
    both_correct =
      sum(data$both_correct == 1),
    
    both_wrong =
      sum(data$both_wrong == 1)
  )
}

disagreement_summary <- rbind(
  summarise_disagreement(
    df,
    "all"
  ),
  
  summarise_disagreement(
    df[df$split == "train", ],
    "train"
  ),
  
  summarise_disagreement(
    df[df$split == "validation", ],
    "validation"
  ),
  
  summarise_disagreement(
    df[df$split == "test", ],
    "test"
  )
)

write.csv(
  disagreement_summary,
  disagreement_summary_file,
  row.names = FALSE
)

############################################################
# Performance on all and disagreement matches
############################################################

split_data <- list(
  all = df,
  train = df[df$split == "train", ],
  validation = df[df$split == "validation", ],
  test = df[df$split == "test", ]
)

results_list <- list()
result_index <- 1

for (split_name in names(split_data)) {
  current_data <- split_data[[
    split_name
  ]]
  
  results_list[[result_index]] <-
    evaluate_models(
      current_data,
      subset_name = "all_matches",
      split_name = split_name
    )
  
  result_index <- result_index + 1
  
  disagreement_data <- current_data[
    current_data$direction_disagreement == 1,
    ,
    drop = FALSE
  ]
  
  results_list[[result_index]] <-
    evaluate_models(
      disagreement_data,
      subset_name = "direction_disagreement",
      split_name = split_name
    )
  
  result_index <- result_index + 1
}

results <- do.call(
  rbind,
  results_list
)

rownames(results) <- NULL

primary_nn_test_row <- (
  results$split == "test" &
    results$subset == "all_matches" &
    results$model == primary_nn_name
)

if (sum(primary_nn_test_row) != 1L) {
  stop(
    "Could not identify the final Primary-NN test result."
  )
}

diagnostic_primary_nn_test_logloss <-
  results$logloss[primary_nn_test_row]

summary_primary_nn_test_logloss <-
  primary_nn_run_summary$primary_nn_maxit1000_test_logloss[1]

if (
  !isTRUE(
    all.equal(
      diagnostic_primary_nn_test_logloss,
      summary_primary_nn_test_logloss,
      tolerance = 1e-12
    )
  )
) {
  stop(
    "The Primary-NN test log loss does not match the maxit = 1000 run summary."
  )
}

write.csv(
  results,
  performance_file,
  row.names = FALSE
)

############################################################
# Gap recovery in disagreement matches
############################################################

make_gap_recovery_table <- function(
    result_data,
    split_name,
    subset_name
) {
  d <- result_data[
    result_data$split == split_name &
      result_data$subset == subset_name,
    ,
    drop = FALSE
  ]
  
  ttt_ll <- d$logloss[
    d$model == "TTT baseline"
  ][1]
  
  bookmaker_ll <- d$logloss[
    d$model == "Bookmaker"
  ][1]
  
  if (
    is.na(ttt_ll) ||
    is.na(bookmaker_ll)
  ) {
    stop(
      "Could not identify TTT or bookmaker log loss for ",
      split_name,
      "."
    )
  }
  
  ttt_to_bookmaker_gap <-
    ttt_ll - bookmaker_ll
  
  if (
    abs(ttt_to_bookmaker_gap) <
    .Machine$double.eps
  ) {
    stop(
      "The TTT-to-bookmaker log-loss gap is zero."
    )
  }
  
  d$ttt_baseline_logloss <-
    ttt_ll
  
  d$bookmaker_logloss <-
    bookmaker_ll
  
  d$ttt_minus_bookmaker_gap <-
    ttt_to_bookmaker_gap
  
  d$logloss_improvement_vs_ttt <-
    ttt_ll - d$logloss
  
  d$proportion_of_ttt_to_bookmaker_gap_closed <-
    (
      ttt_ll - d$logloss
    ) /
    ttt_to_bookmaker_gap
  
  d
}

gap_recovery <- rbind(
  make_gap_recovery_table(
    results,
    split_name = "all",
    subset_name = "direction_disagreement"
  ),
  
  make_gap_recovery_table(
    results,
    split_name = "test",
    subset_name = "direction_disagreement"
  )
)

write.csv(
  gap_recovery,
  gap_recovery_file,
  row.names = FALSE
)

############################################################
# Training-derived TTT uncertainty quartiles
############################################################

training_uncertainty <- df$ttt_uncertainty[
  df$split == "train"
]

internal_breaks <- as.numeric(
  quantile(
    training_uncertainty,
    probs = c(
      0.25,
      0.50,
      0.75
    ),
    na.rm = TRUE,
    type = 7,
    names = FALSE
  )
)

if (
  length(unique(internal_breaks)) < 3
) {
  stop(
    "The training-set TTT uncertainty quartile ",
    "boundaries are not unique."
  )
}

quartile_breaks <- c(
  -Inf,
  internal_breaks,
  Inf
)

quartile_labels <- c(
  "Q1",
  "Q2",
  "Q3",
  "Q4"
)

df$ttt_uncertainty_quartile <- cut(
  df$ttt_uncertainty,
  breaks = quartile_breaks,
  labels = quartile_labels,
  include.lowest = TRUE,
  right = TRUE,
  ordered_result = TRUE
)

if (
  any(is.na(
    df$ttt_uncertainty_quartile
  ))
) {
  stop(
    "Some observations could not be assigned to ",
    "a TTT uncertainty quartile."
  )
}

quartile_breaks_table <- data.frame(
  quartile = quartile_labels,
  
  lower_bound = quartile_breaks[
    1:4
  ],
  
  upper_bound = quartile_breaks[
    2:5
  ],
  
  boundary_source =
    "Training-set TTT uncertainty",
  
  stringsAsFactors = FALSE
)

write.csv(
  quartile_breaks_table,
  quartile_breaks_file,
  row.names = FALSE
)

############################################################
# Quartile counts and disagreement rates
############################################################

quartile_count_list <- list()
quartile_count_index <- 1

for (split_name in c(
  "all",
  "test"
)) {
  current_data <- if (
    split_name == "all"
  ) {
    df
  } else {
    df[df$split == "test", ]
  }
  
  for (quartile_name in quartile_labels) {
    d_q <- current_data[
      current_data$ttt_uncertainty_quartile ==
        quartile_name,
      ,
      drop = FALSE
    ]
    
    disagreement_n <- sum(
      d_q$direction_disagreement == 1
    )
    
    quartile_count_list[[
      quartile_count_index
    ]] <- data.frame(
      split = split_name,
      ttt_uncertainty_quartile =
        quartile_name,
      
      lower_bound =
        quartile_breaks_table$lower_bound[
          quartile_breaks_table$quartile ==
            quartile_name
        ],
      
      upper_bound =
        quartile_breaks_table$upper_bound[
          quartile_breaks_table$quartile ==
            quartile_name
        ],
      
      n_all_matches =
        nrow(d_q),
      
      direction_disagreement_n =
        disagreement_n,
      
      direction_disagreement_rate =
        if (nrow(d_q) > 0) {
          disagreement_n / nrow(d_q)
        } else {
          NA_real_
        }
    )
    
    quartile_count_index <-
      quartile_count_index + 1
  }
}

quartile_counts <- do.call(
  rbind,
  quartile_count_list
)

rownames(quartile_counts) <- NULL

write.csv(
  quartile_counts,
  quartile_counts_file,
  row.names = FALSE
)

############################################################
#  Model performance by uncertainty quartile
# within disagreement matches
############################################################

quartile_results_list <- list()
quartile_result_index <- 1

for (split_name in c(
  "all",
  "test"
)) {
  current_data <- if (
    split_name == "all"
  ) {
    df
  } else {
    df[df$split == "test", ]
  }
  
  for (quartile_name in quartile_labels) {
    d_q <- current_data[
      current_data$direction_disagreement == 1 &
        current_data$ttt_uncertainty_quartile ==
        quartile_name,
      ,
      drop = FALSE
    ]
    
    current_results <- evaluate_models(
      d_q,
      subset_name =
        "direction_disagreement",
      split_name =
        split_name
    )
    
    current_results$ttt_uncertainty_quartile <-
      quartile_name
    
    current_results$quartile_lower_bound <-
      quartile_breaks_table$lower_bound[
        quartile_breaks_table$quartile ==
          quartile_name
      ]
    
    current_results$quartile_upper_bound <-
      quartile_breaks_table$upper_bound[
        quartile_breaks_table$quartile ==
          quartile_name
      ]
    
    quartile_results_list[[
      quartile_result_index
    ]] <- current_results
    
    quartile_result_index <-
      quartile_result_index + 1
  }
}

quartile_results <- do.call(
  rbind,
  quartile_results_list
)

rownames(quartile_results) <- NULL

quartile_results <- quartile_results[
  ,
  c(
    "subset",
    "split",
    "ttt_uncertainty_quartile",
    "quartile_lower_bound",
    "quartile_upper_bound",
    "model",
    "model_role",
    "n",
    "logloss",
    "brier",
    "accuracy",
    "mean_predicted_prob_for_actual_winner"
  )
]

write.csv(
  quartile_results,
  quartile_results_file,
  row.names = FALSE
)

############################################################
#  Save diagnostic-level dataset
############################################################

write.csv(
  df,
  diagnostic_data_file,
  row.names = FALSE
)

############################################################
# Print outputs
############################################################

cat(
  "\nFinished final disagreement diagnostics.\n\n"
)

cat(
  "Verified Primary NN: fully converged maxit = 1000 run\n",
  "Verified test log loss: ",
  format(
    diagnostic_primary_nn_test_logloss,
    digits = 9
  ),
  "\n\n",
  sep = ""
)

cat(
  "Rows:",
  nrow(df),
  "\n\n"
)

cat(
  "Primary logistic model:\n",
  primary_logistic_name,
  "\n\n"
)

cat(
  "Primary neural-network model:\n",
  primary_nn_name,
  "\n\n"
)

cat(
  "Prediction-column checks:\n"
)

print(
  prediction_check
)

cat(
  "\nDisagreement count summary:\n"
)

print(
  disagreement_summary
)

cat(
  "\nTest set, all matches:\n"
)

print(
  results[
    results$split == "test" &
      results$subset == "all_matches",
    ,
    drop = FALSE
  ]
)

cat(
  "\nTest set, direction-disagreement matches:\n"
)

print(
  results[
    results$split == "test" &
      results$subset ==
      "direction_disagreement",
    ,
    drop = FALSE
  ]
)

cat(
  "\nGap recovery within direction-disagreement matches:\n"
)

print(
  gap_recovery
)

cat(
  "\nTraining-derived TTT uncertainty quartile boundaries:\n"
)

print(
  quartile_breaks_table
)

cat(
  "\nTTT uncertainty quartile counts:\n"
)

print(
  quartile_counts
)

cat(
  "\nDiagnostic dataset saved to:\n",
  diagnostic_data_file,
  "\n"
)

cat(
  "\nQuartile results saved to:\n",
  quartile_results_file,
  "\n"
)

