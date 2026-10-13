# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Fit eight predefined logistic candidates and generate daily rolling-origin test predictions.
# Source: 10_LogisticModels.R
# Working directory: repository root (not R/).
# Dependencies: base/distributed R packages only.
# Inputs: see reproducibility/dependencies.md, stage 10.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 10 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.

rm(list = ls())

input_file <- "data/processed/atp_covariates_with_identity_h2h_common_2010_2025.csv"

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

df <- read.csv(input_file, stringsAsFactors = FALSE)
names(df) <- tolower(names(df))

df$date <- as.Date(df$date)
df$year <- as.integer(format(df$date, "%Y"))

required_cols <- c(
  "split",
  "y_a",
  "p_ttt_a",
  "p_book_final_a",
  "ttt_prob_logit_a",
  "ttt_uncertainty",
  "rank_advantage_a",
  "points_advantage_a",
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
  "surface",
  "series",
  "round"
)

shortterm_vars <- c(
  "played_yesterday_diff_a",
  "last_match_games_diff_a_filled",
  "abs_last_match_games_diff_filled",
  "matches_last7_diff_a",
  "wins_last7_diff_a",
  "winrate_last7_diff_a",
  "games_last7_diff_a",
  "abs_games_last7_diff"
)

h2h_vars <- c(
  "h2h_exists",
  "log_h2h_matches_before",
  "h2h_winrate_diff_a"
)

common_vars <- c(
  "common_opp_exists",
  "log_common_opp_count",
  "common_opp_winrate_diff_a",
  "common_opp_games_diff_a"
)

extension_vars <- c(h2h_vars, common_vars)

required_cols <- c(required_cols, shortterm_vars, extension_vars)

missing_cols <- required_cols[!required_cols %in% names(df)]

if (length(missing_cols) > 0) {
  stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
}

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
# Rolling-origin helper functions
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


rolling_glm_predict <- function(
    data,
    model_formula,
    model_name,
    prob_col,
    origin_unit = "date",
    checkpoint_directory,
    resume_checkpoint = TRUE,
    checkpoint_every = 10L) {
  
  model_variables <- unique(all.vars(model_formula))
  
  incomplete_rows <- !complete.cases(
    data[, model_variables, drop = FALSE]
  )
  
  if (any(incomplete_rows)) {
    stop(
      "Incomplete data found for ",
      model_name,
      ". First affected row: ",
      which(incomplete_rows)[1]
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
    origin_unit = origin_unit,
    match_id = as.character(data$match_id),
    date = as.character(data$date),
    split = as.character(data$split),
    input_md5 = unname(tools::md5sum(input_file))
  )
  
  checkpoint_file <- file.path(
    checkpoint_directory,
    paste0(
      "glm_",
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
    
    # Strictly earlier dates only.
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
    
    fit <- tryCatch(
      glm(
        formula = model_formula,
        data = data[history_rows, , drop = FALSE],
        family = binomial(link = "logit"),
        control = glm.control(maxit = 100)
      ),
      error = function(e) {
        stop(
          "GLM fitting failed for ",
          model_name,
          " at ",
          origin_key,
          ": ",
          conditionMessage(e)
        )
      }
    )
    
    if (!isTRUE(fit$converged)) {
      warning(
        model_name,
        " did not converge at ",
        origin_key
      )
    }
    
    current_predictions <- tryCatch(
      as.numeric(
        predict(
          fit,
          newdata = data[
            forecast_rows,
            ,
            drop = FALSE
          ],
          type = "response"
        )
      ),
      error = function(e) {
        stop(
          "Prediction failed for ",
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
      converged = isTRUE(fit$converged),
      iterations = as.integer(fit$iter),
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
      k %% 25L == 0L ||
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
#Prepare variables
############################################################

df$p_ttt_a <- clip_prob(df$p_ttt_a)
df$p_book_final_a <- clip_prob(df$p_book_final_a)

df$y_a <- as.integer(df$y_a)

df$surface <- factor(df$surface)
df$series <- factor(df$series)
df$round <- factor(df$round)

############################################################
#Impute numeric missing values using training medians
############################################################

numeric_predictors <- c(
  "ttt_prob_logit_a",
  "ttt_uncertainty",
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
  shortterm_vars,
  extension_vars
)

numeric_predictors <- numeric_predictors[numeric_predictors %in% names(df)]

for (v in numeric_predictors) {
  miss_col <- paste0(v, "_missing")
  df[[miss_col]] <- as.integer(is.na(df[[v]]))
  
  train_median <- median(df[[v]][df$split == "train"], na.rm = TRUE)
  
  if (is.na(train_median)) {
    train_median <- 0
  }
  
  df[[v]][is.na(df[[v]])] <- train_median
}

############################################################
#Standardise numeric predictors using training set
############################################################

standardise_with_train <- function(x, split) {
  train_x <- x[split == "train"]
  
  m <- mean(train_x, na.rm = TRUE)
  s <- sd(train_x, na.rm = TRUE)
  
  if (is.na(s) || s == 0) {
    s <- 1
  }
  
  return((x - m) / s)
}

for (v in numeric_predictors) {
  z_name <- paste0("z_", v)
  df[[z_name]] <- standardise_with_train(df[[v]], df$split)
}

############################################################
#Define model formulas
############################################################

# Model 1:
# TTT calibration only

formula_ttt_calibrated <- y_a ~
  z_ttt_prob_logit_a

# Model 2:
# TTT plus ranking and points

formula_ttt_rank <- y_a ~
  z_ttt_prob_logit_a +
  z_ttt_uncertainty +
  z_rank_advantage_a +
  z_points_advantage_a +
  z_rank_gap_abs +
  z_points_gap_abs

# Model 3:
# TTT plus recent and surface form

formula_ttt_form <- y_a ~
  z_ttt_prob_logit_a +
  z_ttt_uncertainty +
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
  z_new_player_b

# Model 4:
# Full interpretable covariate model

formula_full <- y_a ~
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
  surface +
  series +
  round

# Model 5:
# Full interpretable covariate model plus short-term fatigue variables

formula_full_shortterm <- y_a ~
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

# Model 6:
# Full short-term model plus direct head-to-head features

formula_full_shortterm_h2h <- update(
  formula_full_shortterm,
  . ~ . +
    z_h2h_exists +
    z_log_h2h_matches_before +
    z_h2h_winrate_diff_a
)

# Model 7:
# Full short-term model plus common opponent features

formula_full_shortterm_common <- update(
  formula_full_shortterm,
  . ~ . +
    z_common_opp_exists +
    z_log_common_opp_count +
    z_common_opp_winrate_diff_a +
    z_common_opp_games_diff_a
)

# Model 8:
# Full short-term model plus H2H and common opponent features

formula_full_shortterm_h2h_common <- update(
  formula_full_shortterm,
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
#Fit models on training set
############################################################

train_df <- df[df$split == "train", ]

fit_ttt_calibrated <- glm(
  formula_ttt_calibrated,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

fit_ttt_rank <- glm(
  formula_ttt_rank,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

fit_ttt_form <- glm(
  formula_ttt_form,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

fit_full <- glm(
  formula_full,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

fit_full_shortterm <- glm(
  formula_full_shortterm,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

fit_full_shortterm_h2h <- glm(
  formula_full_shortterm_h2h,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

fit_full_shortterm_common <- glm(
  formula_full_shortterm_common,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

fit_full_shortterm_h2h_common <- glm(
  formula_full_shortterm_h2h_common,
  data = train_df,
  family = binomial(link = "logit"),
  control = glm.control(maxit = 100)
)

############################################################
#Predict probabilities for all splits
############################################################

df$p_logit_ttt_calibrated_a <- predict(
  fit_ttt_calibrated,
  newdata = df,
  type = "response"
)

df$p_logit_ttt_rank_a <- predict(
  fit_ttt_rank,
  newdata = df,
  type = "response"
)

df$p_logit_ttt_form_a <- predict(
  fit_ttt_form,
  newdata = df,
  type = "response"
)

df$p_logit_full_a <- predict(
  fit_full,
  newdata = df,
  type = "response"
)

df$p_logit_full_shortterm_a <- predict(
  fit_full_shortterm,
  newdata = df,
  type = "response"
)

df$p_logit_full_shortterm_h2h_a <- predict(
  fit_full_shortterm_h2h,
  newdata = df,
  type = "response"
)

df$p_logit_full_shortterm_common_a <- predict(
  fit_full_shortterm_common,
  newdata = df,
  type = "response"
)

df$p_logit_full_shortterm_h2h_common_a <- predict(
  fit_full_shortterm_h2h_common,
  newdata = df,
  type = "response"
)

df$p_logit_ttt_calibrated_a <- clip_prob(df$p_logit_ttt_calibrated_a)
df$p_logit_ttt_rank_a <- clip_prob(df$p_logit_ttt_rank_a)
df$p_logit_ttt_form_a <- clip_prob(df$p_logit_ttt_form_a)
df$p_logit_full_a <- clip_prob(df$p_logit_full_a)
df$p_logit_full_shortterm_a <- clip_prob(df$p_logit_full_shortterm_a)
df$p_logit_full_shortterm_h2h_a <- clip_prob(df$p_logit_full_shortterm_h2h_a)
df$p_logit_full_shortterm_common_a <- clip_prob(df$p_logit_full_shortterm_common_a)
df$p_logit_full_shortterm_h2h_common_a <- clip_prob(df$p_logit_full_shortterm_h2h_common_a)

############################################################
# Rolling-origin logistic predictions for test period
############################################################

rolling_logistic_specs <- list(
  p_logit_ttt_calibrated_a = list(
    model_name = "Logistic TTT calibration",
    model_formula = formula_ttt_calibrated
  ),
  p_logit_ttt_rank_a = list(
    model_name = "Logistic TTT + ranking",
    model_formula = formula_ttt_rank
  ),
  p_logit_ttt_form_a = list(
    model_name = "Logistic TTT + form",
    model_formula = formula_ttt_form
  ),
  p_logit_full_a = list(
    model_name = "Logistic full covariates",
    model_formula = formula_full
  ),
  p_logit_full_shortterm_a = list(
    model_name = "Logistic full + short-term",
    model_formula = formula_full_shortterm
  ),
  p_logit_full_shortterm_h2h_a = list(
    model_name =
      "Logistic full + short-term + H2H",
    model_formula =
      formula_full_shortterm_h2h
  ),
  p_logit_full_shortterm_common_a = list(
    model_name =
      "Logistic full + short-term + common opponent",
    model_formula =
      formula_full_shortterm_common
  ),
  p_logit_full_shortterm_h2h_common_a = list(
    model_name =
      paste(
        "Logistic full + short-term",
        "+ H2H + common opponent"
      ),
    model_formula =
      formula_full_shortterm_h2h_common
  )
)

test_id <- which(df$split == "test")

rolling_logistic_audits <- list()

for (prob_col in names(rolling_logistic_specs)) {
  
  spec <- rolling_logistic_specs[[prob_col]]
  
  rolling_result <- rolling_glm_predict(
    data = df,
    model_formula = spec$model_formula,
    model_name = spec$model_name,
    prob_col = prob_col,
    origin_unit = rolling_origin_unit,
    checkpoint_directory = checkpoint_dir,
    resume_checkpoint =
      resume_rolling_checkpoints,
    checkpoint_every =
      checkpoint_every_n_origins
  )
  
  # Only replace test-period predictions.
  # Train and validation predictions remain based
  # on the initial training model.
  df[[prob_col]][test_id] <-
    rolling_result$predictions[test_id]
  
  df[[prob_col]] <- clip_prob(
    df[[prob_col]]
  )
  
  rolling_logistic_audits[[prob_col]] <-
    rolling_result$audit
}

rolling_logistic_audit <- do.call(
  rbind,
  rolling_logistic_audits
)

rownames(rolling_logistic_audit) <- NULL

write.csv(
  rolling_logistic_audit,
  file.path(
    table_dir,
    "logistic_rolling_origin_audit.csv"
  ),
  row.names = FALSE
)

rolling_settings <- data.frame(
  setting = c(
    "origin_unit",
    "history_rule",
    "same_date_rule",
    "preprocessing_rule",
    "validation_role"
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
      "model specifications selected using",
      "validation and fixed during evaluation"
    )
  ),
  stringsAsFactors = FALSE
)

write.csv(
  rolling_settings,
  file.path(
    table_dir,
    "logistic_rolling_origin_settings.csv"
  ),
  row.names = FALSE
)


############################################################
#Compare models by split
############################################################

comparison <- rbind(
  evaluate_by_split(df, "p_book_final_a", "Bookmaker"),
  evaluate_by_split(df, "p_ttt_a", "Raw TTT"),
  evaluate_by_split(df, "p_logit_ttt_calibrated_a", "Logistic TTT calibration"),
  evaluate_by_split(df, "p_logit_ttt_rank_a", "Logistic TTT + ranking"),
  evaluate_by_split(df, "p_logit_ttt_form_a", "Logistic TTT + form"),
  evaluate_by_split(df, "p_logit_full_a", "Logistic full covariates"),
  evaluate_by_split(df, "p_logit_full_shortterm_a", "Logistic full + short-term"),
  evaluate_by_split(df, "p_logit_full_shortterm_h2h_a", "Logistic full + short-term + H2H"),
  evaluate_by_split(df, "p_logit_full_shortterm_common_a", "Logistic full + short-term + common opponent"),
  evaluate_by_split(df, "p_logit_full_shortterm_h2h_common_a", "Logistic full + short-term + H2H + common opponent")
)

write.csv(
  comparison,
  file.path(table_dir, "logistic_model_comparison_by_split.csv"),
  row.names = FALSE
)

test_comparison <- comparison[comparison$split == "test", ]

write.csv(
  test_comparison,
  file.path(table_dir, "logistic_model_comparison_test.csv"),
  row.names = FALSE
)

############################################################
#Coefficient table for full model
############################################################

coef_table <- summary(fit_full_shortterm)$coefficients

coef_df <- data.frame(
  term = rownames(coef_table),
  estimate = coef_table[, "Estimate"],
  std_error = coef_table[, "Std. Error"],
  z_value = coef_table[, "z value"],
  p_value = coef_table[, "Pr(>|z|)"],
  stringsAsFactors = FALSE
)

coef_df$abs_estimate <- abs(coef_df$estimate)

coef_df <- coef_df[order(-coef_df$abs_estimate), ]

write.csv(
  coef_df,
  file.path(table_dir, "logistic_full_shortterm_model_coefficients.csv"),
  row.names = FALSE
)

############################################################
#Improvement over raw TTT on test set
############################################################

get_metric <- function(comp, model_name, split_name, metric_name) {
  comp[
    comp$model == model_name & comp$split == split_name,
    metric_name
  ][1]
}

raw_ttt_test_logloss <- get_metric(comparison, "Raw TTT", "test", "logloss")
book_test_logloss <- get_metric(comparison, "Bookmaker", "test", "logloss")
full_test_logloss <- get_metric(comparison, "Logistic full + short-term", "test", "logloss")

h2h_test_logloss <- get_metric(
  comparison,
  "Logistic full + short-term + H2H",
  "test",
  "logloss"
)

common_test_logloss <- get_metric(
  comparison,
  "Logistic full + short-term + common opponent",
  "test",
  "logloss"
)

h2h_common_test_logloss <- get_metric(
  comparison,
  "Logistic full + short-term + H2H + common opponent",
  "test",
  "logloss"
)

gap_raw_ttt_to_book <- raw_ttt_test_logloss - book_test_logloss

gap_full_to_book <- full_test_logloss - book_test_logloss
gap_h2h_to_book <- h2h_test_logloss - book_test_logloss
gap_common_to_book <- common_test_logloss - book_test_logloss
gap_h2h_common_to_book <- h2h_common_test_logloss - book_test_logloss

gap_reduction_full <- (gap_raw_ttt_to_book - gap_full_to_book) / gap_raw_ttt_to_book
gap_reduction_h2h <- (gap_raw_ttt_to_book - gap_h2h_to_book) / gap_raw_ttt_to_book
gap_reduction_common <- (gap_raw_ttt_to_book - gap_common_to_book) / gap_raw_ttt_to_book
gap_reduction_h2h_common <- (gap_raw_ttt_to_book - gap_h2h_common_to_book) / gap_raw_ttt_to_book

improvement_table <- data.frame(
  item = c(
    "raw_ttt_test_logloss",
    "bookmaker_test_logloss",
    "full_shortterm_model_test_logloss",
    "full_shortterm_h2h_test_logloss",
    "full_shortterm_common_opponent_test_logloss",
    "full_shortterm_h2h_common_test_logloss",
    "raw_ttt_minus_bookmaker_gap",
    "full_shortterm_gap_reduction_proportion",
    "full_shortterm_h2h_gap_reduction_proportion",
    "full_shortterm_common_opponent_gap_reduction_proportion",
    "full_shortterm_h2h_common_gap_reduction_proportion"
  ),
  value = c(
    raw_ttt_test_logloss,
    book_test_logloss,
    full_test_logloss,
    h2h_test_logloss,
    common_test_logloss,
    h2h_common_test_logloss,
    gap_raw_ttt_to_book,
    gap_reduction_full,
    gap_reduction_h2h,
    gap_reduction_common,
    gap_reduction_h2h_common
  )
)

write.csv(
  improvement_table,
  file.path(table_dir, "logistic_h2h_common_gap_reduction_summary.csv"),
  row.names = FALSE
)

############################################################
#Figures
############################################################

# Test-set logloss comparison

test_logloss <- test_comparison$logloss
names(test_logloss) <- test_comparison$model

png(
  filename = file.path(figure_dir, "test_logloss_model_comparison.png"),
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

# Test-set accuracy comparison

test_accuracy <- test_comparison$accuracy
names(test_accuracy) <- test_comparison$model

png(
  filename = file.path(figure_dir, "test_accuracy_model_comparison.png"),
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
  file.path(processed_dir, "atp_logistic_predictions_with_h2h_common_2010_2025.csv"),
  row.names = FALSE
)

cat("Finished logistic covariate models.\n\n")

cat("Model comparison by split:\n")
print(comparison)

cat("\nTest set comparison:\n")
print(test_comparison)

cat("\nGap reduction summary:\n")
print(improvement_table)

cat("\nTop 30 full short-term model coefficients by absolute estimate:\n")

cat("\nPredictions saved to:\n")
cat(file.path(processed_dir, "atp_logistic_predictions_with_h2h_common_2010_2025.csv"), "\n")

