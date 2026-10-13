# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Compare four NN feature families at maxit 300 and generate daily rolling-origin test predictions.
# Source: 11_NeuralNetworkModels.R
# Working directory: repository root (not R/).
# Dependencies: nnet.
# Inputs: see reproducibility/dependencies.md, stage 11.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 11 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

rm(list = ls())

input_file <-
  "data/processed/atp_logistic_predictions_with_h2h_common_2010_2025.csv"

processed_dir <- "data/processed"
table_dir <- "outputs/tables"
figure_dir <- "outputs/figures"

############################################################
# Rolling-origin settings
############################################################

rolling_origin_unit <- "date"

resume_rolling_checkpoints <- TRUE
checkpoint_every_n_origins <- 10L

checkpoint_dir <- file.path(
  processed_dir,
  "rolling_checkpoints"
)

dir.create(
  checkpoint_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file)
}

if (!requireNamespace("nnet", quietly = TRUE)) {
  stop("Package 'nnet' is required. Please install it with install.packages('nnet').")
}

df <- read.csv(input_file, stringsAsFactors = FALSE)
names(df) <- tolower(names(df))

df$date <- as.Date(df$date)
df$year <- as.integer(format(df$date, "%Y"))

df$surface <- factor(df$surface)
df$series <- factor(df$series)
df$round <- factor(df$round)

df$y_a <- as.integer(df$y_a)

clip_prob <- function(p, eps = 1e-15) {
  p[p < eps] <- eps
  p[p > 1 - eps] <- 1 - eps
  return(p)
}

single_logloss <- function(y, p) {
  p <- clip_prob(p)
  return(-(y * log(p) + (1 - y) * log(1 - p)))
}

log_loss <- function(y, p) {
  return(mean(single_logloss(y, p), na.rm = TRUE))
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
  
  data.frame(
    n = nrow(d),
    logloss = log_loss(y, p),
    brier = brier_score(y, p),
    accuracy = accuracy_score(y, p),
    mean_predicted_prob_for_actual_winner = mean_prob_winner(y, p)
  )
}

evaluate_by_split <- function(data, prob_col, model_name) {
  splits <- c("train", "validation", "test")
  out_list <- list()
  
  for (s in splits) {
    d <- data[data$split == s, ]
    metrics <- evaluate_predictions(d, prob_col)
    metrics$model <- model_name
    metrics$split <- s
    out_list[[s]] <- metrics
  }
  
  out <- do.call(rbind, out_list)
  rownames(out) <- NULL
  
  out <- out[
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
  
  return(out)
}

############################################################
# Neural-network rolling-origin functions
############################################################

make_forecast_groups <- function(data, origin_unit = "date") {
  
  test_rows <- which(data$split == "test")
  
  if (length(test_rows) == 0L) {
    stop("No test observations were found.")
  }
  
  origin_key <- switch(
    origin_unit,
    date = format(data$date[test_rows], "%Y-%m-%d"),
    month = format(data$date[test_rows], "%Y-%m"),
    year = format(data$date[test_rows], "%Y"),
    stop("origin_unit must be 'date', 'month', or 'year'.")
  )
  
  groups <- split(test_rows, origin_key)
  
  origin_start <- vapply(
    groups,
    function(rows) {
      min(as.numeric(data$date[rows]))
    },
    numeric(1)
  )
  
  groups[order(origin_start, names(groups))]
}


rolling_nn_predict <- function(
    data,
    model_formula,
    best_hyperparameters,
    model_name,
    prob_col,
    origin_unit = "date",
    checkpoint_directory,
    resume_checkpoint = TRUE,
    checkpoint_every = 10L) {
  
  required_variables <- unique(
    all.vars(model_formula)
  )
  
  incomplete_rows <- !complete.cases(
    data[, required_variables, drop = FALSE]
  )
  
  if (any(incomplete_rows)) {
    stop(
      "Incomplete data found for ",
      model_name,
      ". First affected row: ",
      which(incomplete_rows)[1]
    )
  }
  
  x_all <- model.matrix(
    model_formula,
    data = data
  )
  
  x_all <- x_all[
    ,
    colnames(x_all) != "(Intercept)",
    drop = FALSE
  ]
  
  if (
    ncol(x_all) == 0L ||
    any(!is.finite(x_all))
  ) {
    stop(
      "Invalid design matrix for ",
      model_name
    )
  }
  
  selected_size <- as.integer(
    best_hyperparameters$size[1]
  )
  
  selected_decay <- as.numeric(
    best_hyperparameters$decay[1]
  )
  
  selected_seed <- as.integer(
    best_hyperparameters$seed[1]
  )
  
  if (
    is.na(selected_size) ||
    is.na(selected_decay) ||
    is.na(selected_seed)
  ) {
    stop(
      "Selected hyperparameters are incomplete for ",
      model_name
    )
  }
  
  forecast_groups <- make_forecast_groups(
    data = data,
    origin_unit = origin_unit
  )
  
  test_rows <- which(data$split == "test")
  
  predictions <- rep(NA_real_, nrow(data))
  completed_origins <- character()
  audit_rows <- list()
  
  formula_text <- paste(
    deparse(model_formula, width.cutoff = 500L),
    collapse = ""
  )
  
  signature <- list(
    version = 2L,
    model_name = model_name,
    probability_column = prob_col,
    formula = formula_text,
    design_columns = colnames(x_all),
    size = selected_size,
    decay = selected_decay,
    seed = selected_seed,
    origin_unit = origin_unit,
    match_id = as.character(data$match_id),
    date = as.character(data$date),
    split = as.character(data$split),
    input_md5 = unname(tools::md5sum(input_file))
  )
  
  checkpoint_file <- file.path(
    checkpoint_directory,
    paste0(
      "nnet_",
      prob_col,
      "_",
      origin_unit,
      ".rds"
    )
  )
  
  if (
    resume_checkpoint &&
    file.exists(checkpoint_file)
  ) {
    
    checkpoint <- readRDS(checkpoint_file)
    
    if (!identical(checkpoint$signature, signature)) {
      stop(
        "Checkpoint does not match the current model or data: ",
        checkpoint_file,
        "\nDelete the old checkpoint or set ",
        "resume_rolling_checkpoints <- FALSE."
      )
    }
    
    predictions <- checkpoint$predictions
    completed_origins <- checkpoint$completed_origins
    audit_rows <- checkpoint$audit_rows
    
    cat(
      "Resuming ",
      model_name,
      " after ",
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
    
    forecast_start_date <- min(
      data$date[forecast_rows]
    )
    
    forecast_end_date <- max(
      data$date[forecast_rows]
    )
    
    # Only matches from strictly earlier dates
    # may enter the estimation sample.
    history_rows <- which(
      data$date < forecast_start_date
    )
    
    if (length(history_rows) == 0L) {
      stop(
        "No historical observations before origin ",
        origin_key
      )
    }
    
    if (
      max(data$date[history_rows]) >=
      forecast_start_date
    ) {
      stop(
        "Temporal leakage detected at origin ",
        origin_key
      )
    }
    
    set.seed(selected_seed)
    
    fit <- tryCatch(
      nnet::nnet(
        x = x_all[
          history_rows,
          ,
          drop = FALSE
        ],
        y = data$y_a[history_rows],
        size = selected_size,
        decay = selected_decay,
        entropy = TRUE,
        maxit = 300,
        trace = FALSE,
        MaxNWts = 20000
      ),
      error = function(e) {
        stop(
          "Neural-network fitting failed for ",
          model_name,
          " at ",
          origin_key,
          ": ",
          conditionMessage(e)
        )
      }
    )
    
    current_predictions <- tryCatch(
      as.numeric(
        predict(
          fit,
          x_all[
            forecast_rows,
            ,
            drop = FALSE
          ],
          type = "raw"
        )
      ),
      error = function(e) {
        stop(
          "Neural-network prediction failed for ",
          model_name,
          " at ",
          origin_key,
          ": ",
          conditionMessage(e)
        )
      }
    )
    
    if (
      length(current_predictions) !=
      length(forecast_rows) ||
      any(!is.finite(current_predictions))
    ) {
      stop(
        "Invalid predictions for ",
        model_name,
        " at ",
        origin_key
      )
    }
    
    predictions[forecast_rows] <- clip_prob(
      current_predictions
    )
    
    convergence_code <- if (
      is.null(fit$convergence)
    ) {
      NA_integer_
    } else {
      as.integer(fit$convergence)
    }
    
    objective <- if (
      is.null(fit$value)
    ) {
      NA_real_
    } else {
      as.numeric(fit$value)
    }
    
    if (
      !is.na(convergence_code) &&
      convergence_code != 0L
    ) {
      warning(
        model_name,
        " returned convergence code ",
        convergence_code,
        " at ",
        origin_key
      )
    }
    
    audit_rows[[origin_key]] <- data.frame(
      model = model_name,
      probability_column = prob_col,
      origin_unit = origin_unit,
      origin_key = origin_key,
      forecast_start_date = forecast_start_date,
      forecast_end_date = forecast_end_date,
      n_history = length(history_rows),
      history_end_date = max(data$date[history_rows]),
      n_forecasts = length(forecast_rows),
      size = selected_size,
      decay = selected_decay,
      seed = selected_seed,
      convergence_code = convergence_code,
      objective = objective,
      stringsAsFactors = FALSE
    )
    
    completed_origins <- c(
      completed_origins,
      origin_key
    )
    
    if (
      k %% checkpoint_every == 0L ||
      k == length(forecast_groups)
    ) {
      saveRDS(
        list(
          signature = signature,
          predictions = predictions,
          completed_origins = completed_origins,
          audit_rows = audit_rows
        ),
        checkpoint_file
      )
    }
    
    if (
      k %% 10L == 0L ||
      k == length(forecast_groups)
    ) {
      cat(
        "Completed ",
        k,
        " of ",
        length(forecast_groups),
        " origins for ",
        model_name,
        ".\n",
        sep = ""
      )
    }
  }
  
  if (any(is.na(predictions[test_rows]))) {
    stop(
      "Some test predictions are missing for ",
      model_name
    )
  }
  
  audit <- do.call(
    rbind,
    unname(audit_rows)
  )
  
  rownames(audit) <- NULL
  
  list(
    predictions = predictions,
    audit = audit
  )
}

############################################################
# Define neural network covariates
############################################################

h2h_z_vars <- c(
  "z_h2h_exists",
  "z_log_h2h_matches_before",
  "z_h2h_winrate_diff_a"
)

common_z_vars <- c(
  "z_common_opp_exists",
  "z_log_common_opp_count",
  "z_common_opp_winrate_diff_a",
  "z_common_opp_games_diff_a"
)

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

model_formula_h2h <- update(
  model_formula_shortterm,
  . ~ . +
    z_h2h_exists +
    z_log_h2h_matches_before +
    z_h2h_winrate_diff_a
)

model_formula_common <- update(
  model_formula_shortterm,
  . ~ . +
    z_common_opp_exists +
    z_log_common_opp_count +
    z_common_opp_winrate_diff_a +
    z_common_opp_games_diff_a
)

model_formula_h2h_common <- update(
  model_formula_shortterm,
  . ~ . +
    z_h2h_exists +
    z_log_h2h_matches_before +
    z_h2h_winrate_diff_a +
    z_common_opp_exists +
    z_log_common_opp_count +
    z_common_opp_winrate_diff_a +
    z_common_opp_games_diff_a
)

############################################################
# Train validation test split
############################################################

y_all <- df$y_a

train_id <- which(df$split == "train")
val_id <- which(df$split == "validation")
test_id <- which(df$split == "test")

############################################################
# Hyperparameter grid
############################################################

size_grid <- c(3, 5, 8, 12)
decay_grid <- c(0.0001, 0.001, 0.01, 0.05)
seed_grid <- c(101, 202, 303)

grid <- expand.grid(
  size = size_grid,
  decay = decay_grid,
  seed = seed_grid
)

############################################################
# Function to fit one NN model family
############################################################

fit_nn_family <- function(model_name, prob_col, model_formula) {
  
  required_vars <- all.vars(model_formula)
  missing_vars <- required_vars[!required_vars %in% names(df)]
  
  if (length(missing_vars) > 0) {
    stop(
      "Missing variables for ",
      model_name,
      ": ",
      paste(missing_vars, collapse = ", ")
    )
  }
  
  x_all <- model.matrix(model_formula, data = df)
  x_all <- x_all[, colnames(x_all) != "(Intercept)", drop = FALSE]
  
  x_train <- x_all[train_id, , drop = FALSE]
  y_train <- y_all[train_id]
  
  x_val <- x_all[val_id, , drop = FALSE]
  y_val <- y_all[val_id]
  
  x_test <- x_all[test_id, , drop = FALSE]
  y_test <- y_all[test_id]
  
  hyper_results <- data.frame()
  
  best_model <- NULL
  best_val_logloss <- Inf
  best_row <- NULL
  
  cat("\n============================================================\n")
  cat("Fitting model family:", model_name, "\n")
  cat("Number of input columns:", ncol(x_all), "\n")
  cat("============================================================\n")
  
  for (g in seq_len(nrow(grid))) {
    
    current_size <- grid$size[g]
    current_decay <- grid$decay[g]
    current_seed <- grid$seed[g]
    
    set.seed(current_seed)
    
    fit <- nnet::nnet(
      x = x_train,
      y = y_train,
      size = current_size,
      decay = current_decay,
      entropy = TRUE,
      maxit = 300,
      trace = FALSE,
      MaxNWts = 20000
    )
    
    p_train <- as.numeric(predict(fit, x_train, type = "raw"))
    p_val <- as.numeric(predict(fit, x_val, type = "raw"))
    
    p_train <- clip_prob(p_train)
    p_val <- clip_prob(p_val)
    
    train_logloss <- log_loss(y_train, p_train)
    val_logloss <- log_loss(y_val, p_val)
    
    train_brier <- brier_score(y_train, p_train)
    val_brier <- brier_score(y_val, p_val)
    
    train_acc <- accuracy_score(y_train, p_train)
    val_acc <- accuracy_score(y_val, p_val)
    
    row_result <- data.frame(
      model = model_name,
      size = current_size,
      decay = current_decay,
      seed = current_seed,
      train_logloss = train_logloss,
      validation_logloss = val_logloss,
      train_brier = train_brier,
      validation_brier = val_brier,
      train_accuracy = train_acc,
      validation_accuracy = val_acc
    )
    
    hyper_results <- rbind(hyper_results, row_result)
    
    if (val_logloss < best_val_logloss) {
      best_val_logloss <- val_logloss
      best_model <- fit
      best_row <- row_result
    }
    
    cat(
      "Finished model",
      g,
      "of",
      nrow(grid),
      "| family =",
      model_name,
      "| size =",
      current_size,
      "| decay =",
      current_decay,
      "| seed =",
      current_seed,
      "| validation logloss =",
      round(val_logloss, 5),
      "\n"
    )
  }
  
  hyper_results <- hyper_results[order(hyper_results$validation_logloss), ]
  
  df[[prob_col]] <<- as.numeric(predict(best_model, x_all, type = "raw"))
  df[[prob_col]] <<- clip_prob(df[[prob_col]])
  
  return(list(
    hyper_results = hyper_results,
    best_row = best_row
  ))
}

############################################################
# Fit all NN families
############################################################

res_shortterm <- fit_nn_family(
  model_name = "Neural network + short-term",
  prob_col = "p_nn_shortterm_a",
  model_formula = model_formula_shortterm
)

res_h2h <- fit_nn_family(
  model_name = "Neural network + short-term + H2H",
  prob_col = "p_nn_shortterm_h2h_a",
  model_formula = model_formula_h2h
)

res_common <- fit_nn_family(
  model_name = "Neural network + short-term + common opponent",
  prob_col = "p_nn_shortterm_common_a",
  model_formula = model_formula_common
)

res_h2h_common <- fit_nn_family(
  model_name = "Neural network + short-term + H2H + common opponent",
  prob_col = "p_nn_shortterm_h2h_common_a",
  model_formula = model_formula_h2h_common
)

all_hyper_results <- rbind(
  res_shortterm$hyper_results,
  res_h2h$hyper_results,
  res_common$hyper_results,
  res_h2h_common$hyper_results
)

best_rows <- rbind(
  res_shortterm$best_row,
  res_h2h$best_row,
  res_common$best_row,
  res_h2h_common$best_row
)

write.csv(
  all_hyper_results,
  file.path(table_dir, "nn_h2h_common_hyperparameter_results.csv"),
  row.names = FALSE
)

write.csv(
  best_rows,
  file.path(table_dir, "nn_h2h_common_best_hyperparameters.csv"),
  row.names = FALSE
)


############################################################
# Rolling-origin NN predictions for test period
############################################################

rolling_nn_specs <- list(
  p_nn_shortterm_a = list(
    model_name = "Neural network + short-term",
    model_formula = model_formula_shortterm,
    best_hyperparameters = res_shortterm$best_row
  ),
  p_nn_shortterm_h2h_a = list(
    model_name =
      "Neural network + short-term + H2H",
    model_formula = model_formula_h2h,
    best_hyperparameters = res_h2h$best_row
  ),
  p_nn_shortterm_common_a = list(
    model_name =
      paste(
        "Neural network + short-term",
        "+ common opponent"
      ),
    model_formula = model_formula_common,
    best_hyperparameters = res_common$best_row
  ),
  p_nn_shortterm_h2h_common_a = list(
    model_name =
      paste(
        "Neural network + short-term",
        "+ H2H + common opponent"
      ),
    model_formula = model_formula_h2h_common,
    best_hyperparameters =
      res_h2h_common$best_row
  )
)

test_id <- which(df$split == "test")

rolling_nn_audits <- list()

for (prob_col in names(rolling_nn_specs)) {
  
  spec <- rolling_nn_specs[[prob_col]]
  
  rolling_result <- rolling_nn_predict(
    data = df,
    model_formula = spec$model_formula,
    best_hyperparameters =
      spec$best_hyperparameters,
    model_name = spec$model_name,
    prob_col = prob_col,
    origin_unit = rolling_origin_unit,
    checkpoint_directory = checkpoint_dir,
    resume_checkpoint =
      resume_rolling_checkpoints,
    checkpoint_every =
      checkpoint_every_n_origins
  )
  
  # Replace test predictions only.
  # Validation predictions remain those used
  # for hyperparameter selection.
  df[[prob_col]][test_id] <-
    rolling_result$predictions[test_id]
  
  df[[prob_col]] <- clip_prob(
    df[[prob_col]]
  )
  
  rolling_nn_audits[[prob_col]] <-
    rolling_result$audit
}

rolling_nn_audit <- do.call(
  rbind,
  rolling_nn_audits
)

rownames(rolling_nn_audit) <- NULL

write.csv(
  rolling_nn_audit,
  file.path(
    table_dir,
    "nn_rolling_origin_audit.csv"
  ),
  row.names = FALSE
)

nn_rolling_settings <- data.frame(
  setting = c(
    "origin_unit",
    "history_rule",
    "same_date_rule",
    "preprocessing_rule",
    "hyperparameter_rule"
  ),
  value = c(
    rolling_origin_unit,
    "all matches before forecast date",
    paste(
      "all matches on the same date are",
      "forecast before their outcomes are added"
    ),
    paste(
      "imputation and standardisation fixed",
      "from the initial training period"
    ),
    paste(
      "size decay and seed selected using",
      "validation and fixed during evaluation"
    )
  ),
  stringsAsFactors = FALSE
)

write.csv(
  nn_rolling_settings,
  file.path(
    table_dir,
    "nn_rolling_origin_settings.csv"
  ),
  row.names = FALSE
)

############################################################
#Evaluation
############################################################

comparison <- rbind(
  evaluate_by_split(df, "p_book_final_a", "Bookmaker"),
  evaluate_by_split(df, "p_ttt_a", "Raw TTT"),
  evaluate_by_split(df, "p_logit_full_a", "Logistic full covariates"),
  evaluate_by_split(df, "p_logit_full_shortterm_a", "Logistic full + short-term"),
  evaluate_by_split(df, "p_logit_full_shortterm_h2h_a", "Logistic full + short-term + H2H"),
  evaluate_by_split(df, "p_logit_full_shortterm_h2h_common_a", "Logistic full + short-term + H2H + common opponent"),
  evaluate_by_split(df, "p_nn_shortterm_a", "Neural network + short-term"),
  evaluate_by_split(df, "p_nn_shortterm_h2h_a", "Neural network + short-term + H2H"),
  evaluate_by_split(df, "p_nn_shortterm_common_a", "Neural network + short-term + common opponent"),
  evaluate_by_split(df, "p_nn_shortterm_h2h_common_a", "Neural network + short-term + H2H + common opponent")
)

write.csv(
  comparison,
  file.path(table_dir, "nn_model_comparison_by_split.csv"),
  row.names = FALSE
)

test_comparison <- comparison[comparison$split == "test", ]

write.csv(
  test_comparison,
  file.path(table_dir, "nn_model_comparison_test.csv"),
  row.names = FALSE
)

############################################################
# Gap reduction summary
############################################################

get_metric <- function(comp, model_name, split_name, metric_name) {
  comp[
    comp$model == model_name & comp$split == split_name,
    metric_name
  ][1]
}

raw_ttt_test_logloss <- get_metric(comparison, "Raw TTT", "test", "logloss")
book_test_logloss <- get_metric(comparison, "Bookmaker", "test", "logloss")

logit_shortterm_test_logloss <- get_metric(
  comparison,
  "Logistic full + short-term",
  "test",
  "logloss"
)

logit_h2h_test_logloss <- get_metric(
  comparison,
  "Logistic full + short-term + H2H",
  "test",
  "logloss"
)

nn_shortterm_test_logloss <- get_metric(
  comparison,
  "Neural network + short-term",
  "test",
  "logloss"
)

nn_h2h_test_logloss <- get_metric(
  comparison,
  "Neural network + short-term + H2H",
  "test",
  "logloss"
)

nn_common_test_logloss <- get_metric(
  comparison,
  "Neural network + short-term + common opponent",
  "test",
  "logloss"
)

nn_h2h_common_test_logloss <- get_metric(
  comparison,
  "Neural network + short-term + H2H + common opponent",
  "test",
  "logloss"
)

gap_raw_ttt_to_book <- raw_ttt_test_logloss - book_test_logloss

gap_logit_shortterm_to_book <- logit_shortterm_test_logloss - book_test_logloss
gap_logit_h2h_to_book <- logit_h2h_test_logloss - book_test_logloss

gap_nn_shortterm_to_book <- nn_shortterm_test_logloss - book_test_logloss
gap_nn_h2h_to_book <- nn_h2h_test_logloss - book_test_logloss
gap_nn_common_to_book <- nn_common_test_logloss - book_test_logloss
gap_nn_h2h_common_to_book <- nn_h2h_common_test_logloss - book_test_logloss

gap_reduction_logit_shortterm <- (
  gap_raw_ttt_to_book - gap_logit_shortterm_to_book
) / gap_raw_ttt_to_book

gap_reduction_logit_h2h <- (
  gap_raw_ttt_to_book - gap_logit_h2h_to_book
) / gap_raw_ttt_to_book

gap_reduction_nn_shortterm <- (
  gap_raw_ttt_to_book - gap_nn_shortterm_to_book
) / gap_raw_ttt_to_book

gap_reduction_nn_h2h <- (
  gap_raw_ttt_to_book - gap_nn_h2h_to_book
) / gap_raw_ttt_to_book

gap_reduction_nn_common <- (
  gap_raw_ttt_to_book - gap_nn_common_to_book
) / gap_raw_ttt_to_book

gap_reduction_nn_h2h_common <- (
  gap_raw_ttt_to_book - gap_nn_h2h_common_to_book
) / gap_raw_ttt_to_book

gap_summary <- data.frame(
  item = c(
    "raw_ttt_test_logloss",
    "bookmaker_test_logloss",
    "logistic_shortterm_test_logloss",
    "logistic_shortterm_h2h_test_logloss",
    "nn_shortterm_test_logloss",
    "nn_shortterm_h2h_test_logloss",
    "nn_shortterm_common_test_logloss",
    "nn_shortterm_h2h_common_test_logloss",
    "raw_ttt_minus_bookmaker_gap",
    "logistic_shortterm_gap_reduction",
    "logistic_shortterm_h2h_gap_reduction",
    "nn_shortterm_gap_reduction",
    "nn_shortterm_h2h_gap_reduction",
    "nn_shortterm_common_gap_reduction",
    "nn_shortterm_h2h_common_gap_reduction"
  ),
  value = c(
    raw_ttt_test_logloss,
    book_test_logloss,
    logit_shortterm_test_logloss,
    logit_h2h_test_logloss,
    nn_shortterm_test_logloss,
    nn_h2h_test_logloss,
    nn_common_test_logloss,
    nn_h2h_common_test_logloss,
    gap_raw_ttt_to_book,
    gap_reduction_logit_shortterm,
    gap_reduction_logit_h2h,
    gap_reduction_nn_shortterm,
    gap_reduction_nn_h2h,
    gap_reduction_nn_common,
    gap_reduction_nn_h2h_common
  )
)

write.csv(
  gap_summary,
  file.path(table_dir, "nn_h2h_common_gap_summary.csv"),
  row.names = FALSE
)

############################################################
#Figures
############################################################

test_logloss <- test_comparison$logloss
names(test_logloss) <- test_comparison$model

png(
  filename = file.path(figure_dir, "nn_test_logloss_comparison.png"),
  width = 1100,
  height = 700
)

barplot(
  test_logloss,
  las = 2,
  ylab = "Log loss",
  main = "Test set log loss by model"
)

grid()

dev.off()

test_accuracy <- test_comparison$accuracy
names(test_accuracy) <- test_comparison$model

png(
  filename = file.path(figure_dir, "nn_test_accuracy_comparison.png"),
  width = 1100,
  height = 700
)

barplot(
  test_accuracy,
  las = 2,
  ylim = c(0.5, 0.75),
  ylab = "Accuracy",
  main = "Test set accuracy by model"
)

grid()

dev.off()

write.csv(
  df,
  file.path(processed_dir, "atp_nn_shortterm_h2h_common_predictions_2010_2025.csv"),
  row.names = FALSE
)

cat("\nFinished neural network model.\n\n")

cat("Best hyperparameter settings selected by validation logloss:\n")
print(best_rows)

cat("\nTop 10 hyperparameter results across all NN families:\n")
all_hyper_results <- all_hyper_results[order(all_hyper_results$validation_logloss), ]
print(head(all_hyper_results, 10))

cat("\nModel comparison by split:\n")
print(comparison)

cat("\nTest set comparison:\n")
print(test_comparison)

cat("\nGap reduction summary:\n")
print(gap_summary)

cat("\nPredictions saved to:\n")
cat(file.path(processed_dir, "atp_nn_shortterm_h2h_common_predictions_2010_2025.csv"), "\n")

