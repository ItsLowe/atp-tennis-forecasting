# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Rerun the primary short-term NN validation grid and rolling test fits at maxit 1000.
# Source: 13_PrimaryNNFinalRerun.R
# Working directory: repository root (not R/).
# Dependencies: nnet.
# Inputs: see reproducibility/dependencies.md, stage 13.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 13 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.
rm(list = ls())

input_file <-
  "data/processed/atp_logistic_predictions_with_h2h_common_2010_2025.csv"

existing_nn_file <-
  "data/processed/atp_nn_shortterm_h2h_common_predictions_2010_2025.csv"

processed_dir <- "data/processed"
table_dir <- file.path(
  "outputs",
  "tables",
  "primary_nn_maxit1000"
)

checkpoint_dir <- file.path(
  processed_dir,
  "rolling_checkpoints_primary_nn_maxit1000"
)

prediction_output_file <- file.path(
  processed_dir,
  "atp_nn_primary_maxit1000_predictions_2010_2025.csv"
)

nn_maxit <- 1000L
resume_checkpoints <- TRUE
checkpoint_every_n_origins <- 10L

expected_split_counts <- c(
  train = 28890L,
  validation = 2539L,
  test = 7725L
)

expected_test_origins <- 876L

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

dir.create(
  checkpoint_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file)
}

if (!file.exists(existing_nn_file)) {
  stop(
    "Existing NN prediction file not found: ",
    existing_nn_file,
    "\nThis file is needed only to preserve the three extension-NN columns."
  )
}

if (!requireNamespace("nnet", quietly = TRUE)) {
  stop(
    "Package 'nnet' is required. Install it with ",
    "install.packages('nnet')."
  )
}

############################################################
# Utility functions
############################################################

clip_prob <- function(p, eps = 1e-15) {
  p[p < eps] <- eps
  p[p > 1 - eps] <- 1 - eps
  p
}

single_logloss <- function(y, p) {
  p <- clip_prob(p)
  -(y * log(p) + (1 - y) * log(1 - p))
}

log_loss <- function(y, p) {
  mean(single_logloss(y, p))
}

brier_score <- function(y, p) {
  mean((y - p)^2)
}

accuracy_score <- function(y, p) {
  mean(ifelse(p >= 0.5, 1L, 0L) == y)
}

mean_prob_winner <- function(y, p) {
  mean(ifelse(y == 1L, p, 1 - p))
}

md5_value <- function(path) {
  unname(tools::md5sum(path))
}

fit_nnet <- function(x, y, size, decay, seed, maxit) {
  set.seed(as.integer(seed))

  nnet::nnet(
    x = x,
    y = y,
    size = as.integer(size),
    decay = as.numeric(decay),
    entropy = TRUE,
    maxit = as.integer(maxit),
    trace = FALSE,
    MaxNWts = 20000
  )
}

fit_convergence <- function(fit) {
  if (is.null(fit$convergence)) {
    return(NA_integer_)
  }

  as.integer(fit$convergence)
}

fit_objective <- function(fit) {
  if (is.null(fit$value)) {
    return(NA_real_)
  }

  as.numeric(fit$value)
}

evaluate_one <- function(data, probability_column) {
  y <- as.integer(data$y_a)
  p <- as.numeric(data[[probability_column]])

  if (
    length(y) == 0L ||
    any(is.na(y)) ||
    any(!is.finite(p)) ||
    any(p < 0 | p > 1)
  ) {
    stop("Invalid data supplied to evaluate_one().")
  }

  data.frame(
    n = length(y),
    logloss = log_loss(y, p),
    brier = brier_score(y, p),
    accuracy = accuracy_score(y, p),
    mean_predicted_prob_for_actual_winner =
      mean_prob_winner(y, p),
    stringsAsFactors = FALSE
  )
}

evaluate_by_split <- function(data, probability_column, model_name) {
  split_names <- c("train", "validation", "test")
  rows <- vector("list", length(split_names))

  for (j in seq_along(split_names)) {
    split_name <- split_names[j]
    d <- data[data$split == split_name, , drop = FALSE]
    metrics <- evaluate_one(d, probability_column)
    metrics$model <- model_name
    metrics$split <- split_name

    rows[[j]] <- metrics[
      ,
      c(
        "model",
        "split",
        "n",
        "logloss",
        "brier",
        "accuracy",
        "mean_predicted_prob_for_actual_winner"
      )
    ]
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

############################################################
# Read and validate the modelling data
############################################################

df <- read.csv(
  input_file,
  stringsAsFactors = FALSE
)

names(df) <- tolower(names(df))

base_required_columns <- c(
  "match_id",
  "date",
  "split",
  "y_a",
  "surface",
  "series",
  "round"
)

missing_base_columns <- setdiff(
  base_required_columns,
  names(df)
)

if (length(missing_base_columns) > 0L) {
  stop(
    "Input data are missing: ",
    paste(missing_base_columns, collapse = ", ")
  )
}

df$date <- as.Date(df$date)
df$split <- tolower(trimws(df$split))
df$y_a <- as.integer(df$y_a)

if (any(is.na(df$date))) {
  stop("Some match dates could not be converted to Date format.")
}

if (any(duplicated(df$match_id))) {
  stop("Duplicate match_id values were found in the modelling input.")
}

if (any(!df$split %in% names(expected_split_counts))) {
  stop("Unexpected split values were found.")
}

if (any(is.na(df$y_a)) || any(!df$y_a %in% c(0L, 1L))) {
  stop("y_a must contain only 0 and 1.")
}

actual_split_counts <- table(
  factor(
    df$split,
    levels = names(expected_split_counts)
  )
)

if (
  !identical(
    as.integer(actual_split_counts),
    as.integer(expected_split_counts)
  )
) {
  stop(
    "Unexpected split counts. Expected train/validation/test = ",
    paste(expected_split_counts, collapse = "/"),
    "; found ",
    paste(as.integer(actual_split_counts), collapse = "/"),
    "."
  )
}

df$surface <- factor(df$surface)
df$series <- factor(df$series)
df$round <- factor(df$round)

############################################################
# Primary short-term NN specification
############################################################

model_formula_shortterm <- y_a ~
  z_ttt_prob_logit_a +
  z_ttt_uncertainty +
  z_rank_advantage_a +
  z_points_advantage_a +
  z_rank_gap_abs +
  z_points_gap_abs +
  z_career_winrate_diff_a +
  z_recent5_winrate_diff_a +
  z_recent10_winrate_diff_a +
  z_surface_winrate_diff_a +
  z_log_matches_played_diff_a +
  z_log_surface_matches_diff_a +
  z_rest_days_diff_a_filled +
  z_abs_rest_days_diff_filled +
  z_matches_last30_diff_a +
  z_new_player_a +
  z_new_player_b +
  z_played_yesterday_diff_a +
  z_last_match_games_diff_a_filled +
  z_abs_last_match_games_diff_filled +
  z_matches_last7_diff_a +
  z_wins_last7_diff_a +
  z_winrate_last7_diff_a +
  z_games_last7_diff_a +
  z_abs_games_last7_diff +
  surface +
  series +
  round

required_model_variables <- unique(
  all.vars(model_formula_shortterm)
)

missing_model_variables <- setdiff(
  required_model_variables,
  names(df)
)

if (length(missing_model_variables) > 0L) {
  stop(
    "Primary-NN variables are missing: ",
    paste(missing_model_variables, collapse = ", ")
  )
}

if (
  any(
    !complete.cases(
      df[, required_model_variables, drop = FALSE]
    )
  )
) {
  stop("Incomplete data were found in the primary-NN variables.")
}

x_all <- model.matrix(
  model_formula_shortterm,
  data = df
)

x_all <- x_all[
  ,
  colnames(x_all) != "(Intercept)",
  drop = FALSE
]

if (ncol(x_all) == 0L || any(!is.finite(x_all))) {
  stop("The primary-NN design matrix is invalid.")
}

y_all <- df$y_a
train_id <- which(df$split == "train")
validation_id <- which(df$split == "validation")
test_id <- which(df$split == "test")

x_train <- x_all[train_id, , drop = FALSE]
y_train <- y_all[train_id]
x_validation <- x_all[validation_id, , drop = FALSE]
y_validation <- y_all[validation_id]

formula_text <- paste(
  deparse(
    model_formula_shortterm,
    width.cutoff = 500L
  ),
  collapse = ""
)

############################################################
# Validation-only hyperparameter search at maxit = 1000
############################################################

size_grid <- c(3L, 5L, 8L, 12L)
decay_grid <- c(0.0001, 0.001, 0.01, 0.05)
seed_grid <- c(101L, 202L, 303L)

grid <- expand.grid(
  size = size_grid,
  decay = decay_grid,
  seed = seed_grid,
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)

grid$size <- as.integer(grid$size)
grid$decay <- as.numeric(grid$decay)
grid$seed <- as.integer(grid$seed)

grid$config_id <- paste(
  grid$size,
  format(grid$decay, scientific = FALSE, trim = TRUE),
  grid$seed,
  sep = "__"
)

grid_checkpoint_file <- file.path(
  checkpoint_dir,
  "primary_nn_validation_grid_checkpoint.rds"
)

grid_signature <- list(
  version = 1L,
  input_md5 = md5_value(input_file),
  formula = formula_text,
  design_columns = colnames(x_all),
  train_match_id = as.character(df$match_id[train_id]),
  validation_match_id = as.character(df$match_id[validation_id]),
  grid = grid,
  maxit = nn_maxit
)

hyperparameter_rows <- list()

if (
  resume_checkpoints &&
  file.exists(grid_checkpoint_file)
) {
  grid_checkpoint <- readRDS(grid_checkpoint_file)

  if (!identical(grid_checkpoint$signature, grid_signature)) {
    stop(
      "The validation-grid checkpoint does not match this run: ",
      grid_checkpoint_file,
      "\nDo not delete other checkpoints. Delete only this file if you ",
      "intend to restart the maxit-1000 primary run."
    )
  }

  hyperparameter_rows <- grid_checkpoint$rows

  cat(
    "Resuming the validation grid after ",
    length(hyperparameter_rows),
    " completed configurations.\n",
    sep = ""
  )
}

completed_configurations <- names(hyperparameter_rows)

for (g in seq_len(nrow(grid))) {
  config_id <- grid$config_id[g]

  if (config_id %in% completed_configurations) {
    next
  }

  started <- proc.time()[["elapsed"]]

  fit <- tryCatch(
    fit_nnet(
      x = x_train,
      y = y_train,
      size = grid$size[g],
      decay = grid$decay[g],
      seed = grid$seed[g],
      maxit = nn_maxit
    ),
    error = function(e) {
      stop(
        "Validation-grid fit failed for ",
        config_id,
        ": ",
        conditionMessage(e)
      )
    }
  )

  p_train <- clip_prob(
    as.numeric(
      predict(fit, x_train, type = "raw")
    )
  )

  p_validation <- clip_prob(
    as.numeric(
      predict(fit, x_validation, type = "raw")
    )
  )

  convergence_code <- fit_convergence(fit)

  hyperparameter_rows[[config_id]] <- data.frame(
    model = "Neural network + short-term",
    config_id = config_id,
    size = grid$size[g],
    decay = grid$decay[g],
    seed = grid$seed[g],
    maxit = nn_maxit,
    convergence_code = convergence_code,
    objective = fit_objective(fit),
    train_logloss = log_loss(y_train, p_train),
    validation_logloss =
      log_loss(y_validation, p_validation),
    train_brier = brier_score(y_train, p_train),
    validation_brier =
      brier_score(y_validation, p_validation),
    train_accuracy = accuracy_score(y_train, p_train),
    validation_accuracy =
      accuracy_score(y_validation, p_validation),
    elapsed_seconds =
      proc.time()[["elapsed"]] - started,
    stringsAsFactors = FALSE
  )

  saveRDS(
    list(
      signature = grid_signature,
      rows = hyperparameter_rows
    ),
    grid_checkpoint_file
  )

  cat(
    "Validation grid: ",
    length(hyperparameter_rows),
    "/",
    nrow(grid),
    " | size = ",
    grid$size[g],
    " | decay = ",
    grid$decay[g],
    " | seed = ",
    grid$seed[g],
    " | convergence = ",
    convergence_code,
    " | validation log loss = ",
    format(
      hyperparameter_rows[[config_id]]$validation_logloss,
      digits = 8
    ),
    "\n",
    sep = ""
  )
}

if (length(hyperparameter_rows) != nrow(grid)) {
  stop("The validation grid did not complete all configurations.")
}

hyperparameter_results <- do.call(
  rbind,
  unname(hyperparameter_rows)
)

rownames(hyperparameter_results) <- NULL

hyperparameter_results <- hyperparameter_results[
  order(hyperparameter_results$validation_logloss),
  ,
  drop = FALSE
]

converged_hyperparameters <- hyperparameter_results[
  !is.na(hyperparameter_results$convergence_code) &
    hyperparameter_results$convergence_code == 0L,
  ,
  drop = FALSE
]

if (nrow(converged_hyperparameters) == 0L) {
  stop(
    "No validation-grid configuration converged at maxit = ",
    nn_maxit,
    "."
  )
}

best_hyperparameters <- converged_hyperparameters[
  1L,
  ,
  drop = FALSE
]

write.csv(
  hyperparameter_results,
  file.path(
    table_dir,
    "nn_primary_maxit1000_hyperparameter_results.csv"
  ),
  row.names = FALSE
)

write.csv(
  best_hyperparameters,
  file.path(
    table_dir,
    "nn_primary_maxit1000_best_hyperparameters.csv"
  ),
  row.names = FALSE
)

selected_size <- as.integer(best_hyperparameters$size[1])
selected_decay <- as.numeric(best_hyperparameters$decay[1])
selected_seed <- as.integer(best_hyperparameters$seed[1])

cat("\nSelected primary-NN hyperparameters:\n")
print(best_hyperparameters)

############################################################
# Train/validation predictions for the selected model
############################################################

selected_initial_fit <- fit_nnet(
  x = x_train,
  y = y_train,
  size = selected_size,
  decay = selected_decay,
  seed = selected_seed,
  maxit = nn_maxit
)

selected_initial_convergence <-
  fit_convergence(selected_initial_fit)

if (
  is.na(selected_initial_convergence) ||
  selected_initial_convergence != 0L
) {
  stop(
    "The selected initial training fit did not converge when reproduced."
  )
}

primary_predictions <- clip_prob(
  as.numeric(
    predict(
      selected_initial_fit,
      x_all,
      type = "raw"
    )
  )
)

############################################################
# Full daily rolling-origin test rerun
############################################################

test_origin_keys <- format(df$date[test_id], "%Y-%m-%d")
forecast_groups <- split(test_id, test_origin_keys)

origin_dates <- as.Date(names(forecast_groups))
forecast_groups <- forecast_groups[order(origin_dates)]

if (length(forecast_groups) != expected_test_origins) {
  stop(
    "Unexpected number of test origins. Expected ",
    expected_test_origins,
    "; found ",
    length(forecast_groups),
    "."
  )
}

rolling_checkpoint_file <- file.path(
  checkpoint_dir,
  "primary_nn_rolling_origin_checkpoint.rds"
)

rolling_signature <- list(
  version = 1L,
  input_md5 = md5_value(input_file),
  formula = formula_text,
  design_columns = colnames(x_all),
  match_id = as.character(df$match_id),
  date = as.character(df$date),
  split = as.character(df$split),
  origin_unit = "date",
  maxit = nn_maxit,
  size = selected_size,
  decay = selected_decay,
  seed = selected_seed
)

rolling_predictions <- rep(NA_real_, nrow(df))
completed_origins <- character()
rolling_audit_rows <- list()

if (
  resume_checkpoints &&
  file.exists(rolling_checkpoint_file)
) {
  rolling_checkpoint <- readRDS(rolling_checkpoint_file)

  if (!identical(
    rolling_checkpoint$signature,
    rolling_signature
  )) {
    stop(
      "The rolling checkpoint does not match this run: ",
      rolling_checkpoint_file,
      "\nDo not delete other checkpoints. Delete only this file if you ",
      "intend to restart the maxit-1000 primary run."
    )
  }

  rolling_predictions <-
    rolling_checkpoint$predictions
  completed_origins <-
    rolling_checkpoint$completed_origins
  rolling_audit_rows <-
    rolling_checkpoint$audit_rows

  cat(
    "Resuming the primary rolling run after ",
    length(completed_origins),
    " completed origins.\n",
    sep = ""
  )
}

for (k in seq_along(forecast_groups)) {
  origin_key <- names(forecast_groups)[k]

  if (origin_key %in% completed_origins) {
    next
  }

  forecast_rows <- forecast_groups[[k]]
  forecast_date <- min(df$date[forecast_rows])
  history_rows <- which(df$date < forecast_date)

  if (length(history_rows) == 0L) {
    stop("No history exists before origin ", origin_key, ".")
  }

  history_end_date <- max(df$date[history_rows])

  if (history_end_date >= forecast_date) {
    stop("Temporal leakage detected at origin ", origin_key, ".")
  }

  started <- proc.time()[["elapsed"]]

  fit <- tryCatch(
    fit_nnet(
      x = x_all[history_rows, , drop = FALSE],
      y = y_all[history_rows],
      size = selected_size,
      decay = selected_decay,
      seed = selected_seed,
      maxit = nn_maxit
    ),
    error = function(e) {
      stop(
        "Rolling fit failed at ",
        origin_key,
        ": ",
        conditionMessage(e)
      )
    }
  )

  current_predictions <- clip_prob(
    as.numeric(
      predict(
        fit,
        x_all[forecast_rows, , drop = FALSE],
        type = "raw"
      )
    )
  )

  if (
    length(current_predictions) != length(forecast_rows) ||
    any(!is.finite(current_predictions))
  ) {
    stop("Invalid predictions at origin ", origin_key, ".")
  }

  rolling_predictions[forecast_rows] <- current_predictions

  convergence_code <- fit_convergence(fit)

  rolling_audit_rows[[origin_key]] <- data.frame(
    model = "Neural network + short-term",
    probability_column = "p_nn_shortterm_a",
    origin_unit = "date",
    origin_key = origin_key,
    forecast_start_date = forecast_date,
    forecast_end_date = max(df$date[forecast_rows]),
    n_history = length(history_rows),
    history_end_date = history_end_date,
    n_forecasts = length(forecast_rows),
    size = selected_size,
    decay = selected_decay,
    seed = selected_seed,
    maxit = nn_maxit,
    convergence_code = convergence_code,
    objective = fit_objective(fit),
    elapsed_seconds = proc.time()[["elapsed"]] - started,
    stringsAsFactors = FALSE
  )

  if (!is.na(convergence_code) && convergence_code != 0L) {
    warning(
      "Primary NN returned convergence code ",
      convergence_code,
      " at ",
      origin_key,
      "."
    )
  }

  completed_origins <- c(
    completed_origins,
    origin_key
  )

  if (
    k %% checkpoint_every_n_origins == 0L ||
    k == length(forecast_groups)
  ) {
    saveRDS(
      list(
        signature = rolling_signature,
        predictions = rolling_predictions,
        completed_origins = completed_origins,
        audit_rows = rolling_audit_rows
      ),
      rolling_checkpoint_file
    )
  }

  if (k %% 10L == 0L || k == length(forecast_groups)) {
    cat(
      "Primary rolling run: ",
      k,
      "/",
      length(forecast_groups),
      " origins completed | latest = ",
      origin_key,
      " | convergence = ",
      convergence_code,
      "\n",
      sep = ""
    )
  }
}

if (any(is.na(rolling_predictions[test_id]))) {
  stop("Some test-period primary-NN predictions are missing.")
}

primary_predictions[test_id] <-
  rolling_predictions[test_id]

audit_order <- names(forecast_groups)

if (!setequal(names(rolling_audit_rows), audit_order)) {
  stop("The rolling audit does not cover every test origin exactly once.")
}

rolling_audit <- do.call(
  rbind,
  rolling_audit_rows[audit_order]
)

rownames(rolling_audit) <- NULL

if (sum(rolling_audit$n_forecasts) != length(test_id)) {
  stop("Rolling audit forecast counts do not sum to the test size.")
}

write.csv(
  rolling_audit,
  file.path(
    table_dir,
    "nn_primary_maxit1000_rolling_origin_audit.csv"
  ),
  row.names = FALSE
)

############################################################
# Preserve extension predictions and write a new data file
############################################################

existing_nn <- read.csv(
  existing_nn_file,
  stringsAsFactors = FALSE
)

names(existing_nn) <- tolower(names(existing_nn))

if (
  !"match_id" %in% names(existing_nn) ||
  any(duplicated(existing_nn$match_id))
) {
  stop("The existing NN prediction file has invalid match_id values.")
}

existing_order <- match(
  df$match_id,
  existing_nn$match_id
)

if (
  any(is.na(existing_order)) ||
  nrow(existing_nn) != nrow(df)
) {
  stop(
    "The modelling input and existing NN prediction file do not contain ",
    "the same matches."
  )
}

output_data <- existing_nn[
  existing_order,
  ,
  drop = FALSE
]

if (
  !identical(
    as.character(output_data$match_id),
    as.character(df$match_id)
  )
) {
  stop("Match order could not be aligned across the two input files.")
}

# Use the already validated split and outcome fields from the modelling input.
output_data$split <- df$split
output_data$y_a <- df$y_a

required_existing_nn_columns <- c(
  "p_nn_shortterm_a",
  "p_nn_shortterm_h2h_a",
  "p_nn_shortterm_common_a",
  "p_nn_shortterm_h2h_common_a"
)

missing_existing_nn_columns <- setdiff(
  required_existing_nn_columns,
  names(output_data)
)

if (length(missing_existing_nn_columns) > 0L) {
  stop(
    "Existing NN prediction columns are missing: ",
    paste(missing_existing_nn_columns, collapse = ", ")
  )
}

output_data$p_nn_shortterm_a_maxit300 <-
  output_data$p_nn_shortterm_a

output_data$p_nn_shortterm_a <- primary_predictions

if (
  any(!is.finite(output_data$p_nn_shortterm_a)) ||
  any(
    output_data$p_nn_shortterm_a < 0 |
      output_data$p_nn_shortterm_a > 1
  )
) {
  stop("The final primary-NN probability column is invalid.")
}

write.csv(
  output_data,
  prediction_output_file,
  row.names = FALSE
)

############################################################
# Final metrics and run audit
############################################################

required_metric_columns <- c(
  "p_book_final_a",
  "p_ttt_a",
  "p_logit_full_shortterm_h2h_a",
  "p_nn_shortterm_a",
  "p_nn_shortterm_a_maxit300"
)

missing_metric_columns <- setdiff(
  required_metric_columns,
  names(output_data)
)

if (length(missing_metric_columns) > 0L) {
  stop(
    "Metric columns are missing from the output: ",
    paste(missing_metric_columns, collapse = ", ")
  )
}

model_columns <- c(
  "Bookmaker" = "p_book_final_a",
  "TTT baseline" = "p_ttt_a",
  "Primary logistic" = "p_logit_full_shortterm_h2h_a",
  "Primary NN maxit 300" = "p_nn_shortterm_a_maxit300",
  "Primary NN maxit 1000" = "p_nn_shortterm_a"
)

model_comparison_rows <- vector(
  "list",
  length(model_columns)
)

for (j in seq_along(model_columns)) {
  model_comparison_rows[[j]] <- evaluate_by_split(
    data = output_data,
    probability_column = unname(model_columns[j]),
    model_name = names(model_columns)[j]
  )
}

model_comparison <- do.call(
  rbind,
  model_comparison_rows
)

rownames(model_comparison) <- NULL

write.csv(
  model_comparison,
  file.path(
    table_dir,
    "nn_primary_maxit1000_model_comparison_by_split.csv"
  ),
  row.names = FALSE
)

test_comparison <- model_comparison[
  model_comparison$split == "test",
  ,
  drop = FALSE
]

metric_value <- function(model_name, metric_name) {
  rows <- test_comparison$model == model_name

  if (sum(rows) != 1L) {
    stop("Could not identify model: ", model_name)
  }

  as.numeric(test_comparison[[metric_name]][rows])
}

bookmaker_logloss <- metric_value("Bookmaker", "logloss")
ttt_logloss <- metric_value("TTT baseline", "logloss")
logistic_logloss <- metric_value("Primary logistic", "logloss")
old_nn_logloss <- metric_value("Primary NN maxit 300", "logloss")
new_nn_logloss <- metric_value("Primary NN maxit 1000", "logloss")

baseline_gap <- ttt_logloss - bookmaker_logloss

if (!is.finite(baseline_gap) || baseline_gap <= 0) {
  stop("The TTT-to-bookmaker test log-loss gap is invalid.")
}

old_nn_gap_closed <-
  100 * (ttt_logloss - old_nn_logloss) / baseline_gap

new_nn_gap_closed <-
  100 * (ttt_logloss - new_nn_logloss) / baseline_gap

run_summary <- data.frame(
  model_family = "Neural network + short-term",
  maxit = nn_maxit,
  selected_size = selected_size,
  selected_decay = selected_decay,
  selected_seed = selected_seed,
  validation_grid_fits = nrow(hyperparameter_results),
  validation_grid_nonconverged = sum(
    is.na(hyperparameter_results$convergence_code) |
      hyperparameter_results$convergence_code != 0L
  ),
  rolling_origins = nrow(rolling_audit),
  rolling_nonconverged = sum(
    is.na(rolling_audit$convergence_code) |
      rolling_audit$convergence_code != 0L
  ),
  test_matches = length(test_id),
  bookmaker_test_logloss = bookmaker_logloss,
  ttt_test_logloss = ttt_logloss,
  primary_logistic_test_logloss = logistic_logloss,
  primary_nn_maxit300_test_logloss = old_nn_logloss,
  primary_nn_maxit1000_test_logloss = new_nn_logloss,
  primary_nn_logloss_change = new_nn_logloss - old_nn_logloss,
  primary_nn_maxit300_gap_closed_percent =
    old_nn_gap_closed,
  primary_nn_maxit1000_gap_closed_percent =
    new_nn_gap_closed,
  nn1000_minus_logistic_test_logloss =
    new_nn_logloss - logistic_logloss,
  prediction_output_file = prediction_output_file,
  stringsAsFactors = FALSE
)

write.csv(
  run_summary,
  file.path(
    table_dir,
    "nn_primary_maxit1000_run_summary.csv"
  ),
  row.names = FALSE
)

run_settings <- data.frame(
  setting = c(
    "model_family",
    "validation_rule",
    "rolling_origin_unit",
    "history_rule",
    "same_date_rule",
    "preprocessing_rule",
    "maxit",
    "checkpoint_rule",
    "output_rule"
  ),
  value = c(
    "primary short-term neural network only",
    paste(
      "lowest validation log loss among converged fits over the",
      "prespecified size decay seed grid"
    ),
    "date",
    "all matches strictly before each forecast date",
    paste(
      "all matches on the same date are forecast before",
      "their outcomes enter the history"
    ),
    paste(
      "imputation and standardisation fixed from the",
      "initial training period"
    ),
    as.character(nn_maxit),
    paste(
      "separate maxit-1000 checkpoints saved every",
      checkpoint_every_n_origins,
      "origins"
    ),
    "new files only; original maxit-300 outputs preserved"
  ),
  stringsAsFactors = FALSE
)

write.csv(
  run_settings,
  file.path(
    table_dir,
    "nn_primary_maxit1000_run_settings.csv"
  ),
  row.names = FALSE
)

cat("\n============================================================\n")
cat("PRIMARY NN MAXIT-1000 RERUN COMPLETED\n")
cat("============================================================\n")
cat("Selected size: ", selected_size, "\n", sep = "")
cat("Selected decay: ", selected_decay, "\n", sep = "")
cat("Selected seed: ", selected_seed, "\n", sep = "")
cat(
  "Validation-grid nonconverged fits: ",
  run_summary$validation_grid_nonconverged,
  "/",
  run_summary$validation_grid_fits,
  "\n",
  sep = ""
)
cat(
  "Rolling-origin nonconverged fits: ",
  run_summary$rolling_nonconverged,
  "/",
  run_summary$rolling_origins,
  "\n",
  sep = ""
)
cat(
  "Old primary NN test log loss: ",
  format(old_nn_logloss, digits = 9),
  "\n",
  sep = ""
)
cat(
  "New primary NN test log loss: ",
  format(new_nn_logloss, digits = 9),
  "\n",
  sep = ""
)
cat(
  "Primary logistic test log loss: ",
  format(logistic_logloss, digits = 9),
  "\n",
  sep = ""
)
cat(
  "New primary NN gap closed: ",
  format(new_nn_gap_closed, digits = 7),
  "%\n",
  sep = ""
)
cat("\nNew prediction file:\n", prediction_output_file, "\n")
cat("\nNew result tables:\n", table_dir, "\n")

if (run_summary$rolling_nonconverged > 0L) {
  warning(
    "The run completed, but ",
    run_summary$rolling_nonconverged,
    " rolling fits still did not converge. Send the audit file for review."
  )
}

