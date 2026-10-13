# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Compare maxit 300 and 1000 at sampled test dates using the already selected family configurations.
# Source: 12_NNConvergenceSensitivity.R
# Working directory: repository root (not R/).
# Dependencies: nnet.
# Inputs: see reproducibility/dependencies.md, stage 12.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 12 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.
rm(list = ls())

############################################################
# Purpose
############################################################

# This script checks whether increasing nnet's iteration limit changes the
# rolling-origin predictions materially. It is independent of 11_neural_network_models.R:
# it does not alter the existing NN prediction file or rolling checkpoints.

input_file <-
  "data/processed/atp_logistic_predictions_with_h2h_common_2010_2025.csv"

best_hyperparameter_file <-
  "outputs/tables/nn_h2h_common_best_hyperparameters.csv"

rolling_audit_file <-
  "outputs/tables/nn_rolling_origin_audit.csv"

existing_nn_prediction_file <-
  "data/processed/atp_nn_shortterm_h2h_common_predictions_2010_2025.csv"

model_comparison_file <-
  "outputs/tables/nn_model_comparison_by_split.csv"

output_dir <- "outputs/sensitivity"

maxit_values <- c(300L, 1000L)
dates_per_year <- 4L
converged_dates_per_year <- 2L

# This checkpoint is separate from the checkpoints used by 11_neural_network_models.R.
resume_sensitivity_checkpoint <- TRUE

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

required_files <- c(
  input_file,
  best_hyperparameter_file,
  rolling_audit_file
)

missing_files <- required_files[!file.exists(required_files)]

if (length(missing_files) > 0L) {
  stop(
    "Required file(s) not found: ",
    paste(missing_files, collapse = ", ")
  )
}

if (!requireNamespace("nnet", quietly = TRUE)) {
  stop(
    "Package 'nnet' is required. Install it with install.packages('nnet')."
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
  mean(single_logloss(y, p), na.rm = TRUE)
}

brier_score <- function(y, p) {
  mean((y - p)^2, na.rm = TRUE)
}

accuracy_score <- function(y, p) {
  mean(ifelse(p >= 0.5, 1L, 0L) == y, na.rm = TRUE)
}

convergence_label <- function(code) {
  if (length(code) == 0L || is.na(code[1])) {
    return("unknown")
  }

  if (as.integer(code[1]) == 0L) {
    return("converged")
  }

  if (as.integer(code[1]) == 1L) {
    return("maximum iterations reached")
  }

  paste("code", as.integer(code[1]))
}

pick_spread <- function(values, n) {
  values <- sort(unique(as.Date(as.character(values))))
  values <- values[!is.na(values)]
  n <- min(as.integer(n), length(values))

  if (n <= 0L) {
    return(as.Date(character()))
  }

  if (length(values) == n) {
    return(values)
  }

  positions <- unique(
    as.integer(round(seq(1, length(values), length.out = n)))
  )

  if (length(positions) < n) {
    extra_positions <- setdiff(seq_along(values), positions)
    positions <- c(
      positions,
      extra_positions[seq_len(n - length(positions))]
    )
  }

  sort(values[positions[seq_len(n)]])
}

one_value <- function(x, default = NA_real_) {
  if (length(x) == 0L) {
    return(default)
  }

  x[1]
}

############################################################
# Read and validate data
############################################################

df <- read.csv(input_file, stringsAsFactors = FALSE)
names(df) <- tolower(names(df))

required_base_columns <- c(
  "match_id",
  "date",
  "split",
  "y_a",
  "surface",
  "series",
  "round"
)

missing_base_columns <- setdiff(required_base_columns, names(df))

if (length(missing_base_columns) > 0L) {
  stop(
    "Input data are missing required columns: ",
    paste(missing_base_columns, collapse = ", ")
  )
}

df$match_id <- as.character(df$match_id)
df$date <- as.Date(df$date)

if (any(is.na(df$date))) {
  stop("The input data contain invalid dates.")
}

df$year <- as.integer(format(df$date, "%Y"))
df$surface <- factor(df$surface)
df$series <- factor(df$series)
df$round <- factor(df$round)
df$y_a <- as.integer(df$y_a)

if (any(!df$y_a %in% c(0L, 1L))) {
  stop("y_a must contain only 0 and 1.")
}

best_hyperparameters <- read.csv(
  best_hyperparameter_file,
  stringsAsFactors = FALSE
)

names(best_hyperparameters) <- tolower(names(best_hyperparameters))

required_hyperparameter_columns <- c(
  "model",
  "size",
  "decay",
  "seed"
)

missing_hyperparameter_columns <- setdiff(
  required_hyperparameter_columns,
  names(best_hyperparameters)
)

if (length(missing_hyperparameter_columns) > 0L) {
  stop(
    "Best-hyperparameter table is missing: ",
    paste(missing_hyperparameter_columns, collapse = ", ")
  )
}

rolling_audit <- read.csv(
  rolling_audit_file,
  stringsAsFactors = FALSE
)

names(rolling_audit) <- tolower(names(rolling_audit))

required_audit_columns <- c(
  "probability_column",
  "convergence_code"
)

missing_audit_columns <- setdiff(
  required_audit_columns,
  names(rolling_audit)
)

if (length(missing_audit_columns) > 0L) {
  stop(
    "Rolling audit is missing: ",
    paste(missing_audit_columns, collapse = ", ")
  )
}

if ("origin_key" %in% names(rolling_audit)) {
  rolling_audit$origin_date <- as.Date(rolling_audit$origin_key)
} else if ("forecast_start_date" %in% names(rolling_audit)) {
  rolling_audit$origin_date <- as.Date(
    rolling_audit$forecast_start_date
  )
} else {
  stop(
    "Rolling audit must contain origin_key or forecast_start_date."
  )
}

if (any(is.na(rolling_audit$origin_date))) {
  stop("The rolling audit contains invalid origin dates.")
}

rolling_audit$convergence_code <- as.integer(
  rolling_audit$convergence_code
)

############################################################
# Define the same four NN specifications as 11_neural_network_models.R
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

model_specs <- list(
  p_nn_shortterm_a = list(
    model_name = "Neural network + short-term",
    model_formula = model_formula_shortterm
  ),
  p_nn_shortterm_h2h_a = list(
    model_name = "Neural network + short-term + H2H",
    model_formula = model_formula_h2h
  ),
  p_nn_shortterm_common_a = list(
    model_name =
      "Neural network + short-term + common opponent",
    model_formula = model_formula_common
  ),
  p_nn_shortterm_h2h_common_a = list(
    model_name = paste(
      "Neural network + short-term",
      "+ H2H + common opponent"
    ),
    model_formula = model_formula_h2h_common
  )
)

for (prob_col in names(model_specs)) {
  spec <- model_specs[[prob_col]]
  hyper_rows <- best_hyperparameters[
    best_hyperparameters$model == spec$model_name,
    ,
    drop = FALSE
  ]

  if (nrow(hyper_rows) == 0L) {
    stop(
      "No selected hyperparameters were found for ",
      spec$model_name
    )
  }

  if (
    nrow(hyper_rows) > 1L &&
    "validation_logloss" %in% names(hyper_rows)
  ) {
    hyper_rows <- hyper_rows[
      order(hyper_rows$validation_logloss),
      ,
      drop = FALSE
    ]
  }

  selected_row <- hyper_rows[1, , drop = FALSE]

  model_specs[[prob_col]]$size <- as.integer(
    selected_row$size[1]
  )
  model_specs[[prob_col]]$decay <- as.numeric(
    selected_row$decay[1]
  )
  model_specs[[prob_col]]$seed <- as.integer(
    selected_row$seed[1]
  )

  selected_values <- c(
    model_specs[[prob_col]]$size,
    model_specs[[prob_col]]$decay,
    model_specs[[prob_col]]$seed
  )

  if (any(!is.finite(selected_values))) {
    stop(
      "Selected hyperparameters are invalid for ",
      spec$model_name
    )
  }
}

############################################################
# Select 12 representative forecasting dates
############################################################

primary_probability_column <- "p_nn_shortterm_a"

primary_audit <- rolling_audit[
  rolling_audit$probability_column == primary_probability_column,
  ,
  drop = FALSE
]

if (nrow(primary_audit) == 0L) {
  stop("Primary short-term NN rows were not found in the audit file.")
}

test_years <- sort(unique(df$year[df$split == "test"]))

selected_by_year <- vector("list", length(test_years))
names(selected_by_year) <- as.character(test_years)

for (year_value in test_years) {
  year_test_dates <- sort(unique(
    df$date[df$split == "test" & df$year == year_value]
  ))

  audit_year <- primary_audit[
    as.integer(format(primary_audit$origin_date, "%Y")) ==
      year_value,
    ,
    drop = FALSE
  ]

  converged_dates <- audit_year$origin_date[
    !is.na(audit_year$convergence_code) &
      audit_year$convergence_code == 0L
  ]

  limit_dates <- audit_year$origin_date[
    !is.na(audit_year$convergence_code) &
      audit_year$convergence_code != 0L
  ]

  selected_dates <- unique(c(
    pick_spread(
      converged_dates,
      converged_dates_per_year
    ),
    pick_spread(
      limit_dates,
      dates_per_year - converged_dates_per_year
    )
  ))

  if (length(selected_dates) < dates_per_year) {
    remaining_dates <- setdiff(
      year_test_dates,
      selected_dates
    )

    selected_dates <- unique(c(
      selected_dates,
      pick_spread(
        remaining_dates,
        dates_per_year - length(selected_dates)
      )
    ))
  }

  if (length(selected_dates) < dates_per_year) {
    stop(
      "Could not select ",
      dates_per_year,
      " dates for test year ",
      year_value
    )
  }

  selected_by_year[[as.character(year_value)]] <- sort(
    selected_dates[seq_len(dates_per_year)]
  )
}

selected_dates <- sort(unique(do.call(c, selected_by_year)))

selected_origin_rows <- lapply(
  selected_dates,
  function(origin_date) {
    original_row <- primary_audit[
      primary_audit$origin_date == origin_date,
      ,
      drop = FALSE
    ]

    original_code <- if (nrow(original_row) == 0L) {
      NA_integer_
    } else {
      as.integer(original_row$convergence_code[1])
    }

    data.frame(
      origin_date = origin_date,
      year = as.integer(format(origin_date, "%Y")),
      n_test_matches = sum(
        df$split == "test" & df$date == origin_date
      ),
      original_primary_convergence_code = original_code,
      original_primary_status = convergence_label(original_code),
      stringsAsFactors = FALSE
    )
  }
)

selected_origins <- do.call(rbind, selected_origin_rows)
rownames(selected_origins) <- NULL

selected_origin_audit <- rolling_audit[
  rolling_audit$origin_date %in% selected_dates &
    rolling_audit$probability_column %in% names(model_specs),
  ,
  drop = FALSE
]

selected_origin_audit <- selected_origin_audit[
  order(
    selected_origin_audit$origin_date,
    selected_origin_audit$probability_column
  ),
  ,
  drop = FALSE
]

write.csv(
  selected_origins,
  file.path(
    output_dir,
    "nn_convergence_sensitivity_selected_origins.csv"
  ),
  row.names = FALSE
)

write.csv(
  selected_origin_audit,
  file.path(
    output_dir,
    "nn_convergence_sensitivity_original_audit.csv"
  ),
  row.names = FALSE
)

cat("Selected forecasting dates:\n")
print(selected_origins)

############################################################
# Optional reproduction check against existing NN predictions
############################################################

existing_nn_predictions <- NULL
existing_match_index <- NULL

if (file.exists(existing_nn_prediction_file)) {
  existing_nn_predictions <- read.csv(
    existing_nn_prediction_file,
    stringsAsFactors = FALSE
  )
  names(existing_nn_predictions) <- tolower(
    names(existing_nn_predictions)
  )

  required_existing_columns <- c(
    "match_id",
    names(model_specs)
  )

  if (
    all(required_existing_columns %in%
        names(existing_nn_predictions))
  ) {
    existing_nn_predictions$match_id <- as.character(
      existing_nn_predictions$match_id
    )

    existing_match_index <- match(
      df$match_id,
      existing_nn_predictions$match_id
    )

    if (any(is.na(existing_match_index))) {
      warning(
        "Some matches were not found in the existing NN prediction file; ",
        "the reproduction check will be skipped."
      )
      existing_nn_predictions <- NULL
      existing_match_index <- NULL
    }
  } else {
    warning(
      "The existing NN prediction file lacks required columns; ",
      "the reproduction check will be skipped."
    )
    existing_nn_predictions <- NULL
  }
} else {
  warning(
    "Existing NN prediction file not found; ",
    "the maxit = 300 reproduction check will be skipped."
  )
}

############################################################
# Independent sensitivity checkpoint
############################################################

selected_hyperparameter_signature <- do.call(
  rbind,
  lapply(
    names(model_specs),
    function(prob_col) {
      spec <- model_specs[[prob_col]]
      data.frame(
        probability_column = prob_col,
        model = spec$model_name,
        size = spec$size,
        decay = spec$decay,
        seed = spec$seed,
        formula = paste(
          deparse(spec$model_formula, width.cutoff = 500L),
          collapse = ""
        ),
        stringsAsFactors = FALSE
      )
    }
  )
)

checkpoint_signature <- list(
  version = 1L,
  input_md5 = unname(tools::md5sum(input_file)),
  best_hyperparameter_md5 =
    unname(tools::md5sum(best_hyperparameter_file)),
  rolling_audit_md5 =
    unname(tools::md5sum(rolling_audit_file)),
  selected_dates = as.character(selected_dates),
  maxit_values = as.integer(maxit_values),
  selected_hyperparameters = selected_hyperparameter_signature
)

checkpoint_file <- file.path(
  output_dir,
  "nn_convergence_sensitivity_checkpoint.rds"
)

completed_keys <- character()
fit_summary_rows <- list()
prediction_rows <- list()

if (
  resume_sensitivity_checkpoint &&
  file.exists(checkpoint_file)
) {
  checkpoint <- readRDS(checkpoint_file)

  if (!identical(checkpoint$signature, checkpoint_signature)) {
    stop(
      "The sensitivity checkpoint does not match the current files or ",
      "settings. Delete only this file or set ",
      "resume_sensitivity_checkpoint <- FALSE: ",
      checkpoint_file
    )
  }

  completed_keys <- checkpoint$completed_keys
  fit_summary_rows <- checkpoint$fit_summary_rows
  prediction_rows <- checkpoint$prediction_rows

  cat(
    "Resuming after ",
    length(completed_keys),
    " completed sensitivity fits.\n",
    sep = ""
  )
}

############################################################
# Refit sampled origins with maxit 300 and 1000
############################################################

total_fits <-
  length(model_specs) *
  length(selected_dates) *
  length(maxit_values)

for (prob_col in names(model_specs)) {
  spec <- model_specs[[prob_col]]
  required_variables <- unique(all.vars(spec$model_formula))

  missing_variables <- setdiff(required_variables, names(df))

  if (length(missing_variables) > 0L) {
    stop(
      "Missing variables for ",
      spec$model_name,
      ": ",
      paste(missing_variables, collapse = ", ")
    )
  }

  incomplete_rows <- !complete.cases(
    df[, required_variables, drop = FALSE]
  )

  if (any(incomplete_rows)) {
    stop(
      "Incomplete model data for ",
      spec$model_name,
      ". First affected row: ",
      which(incomplete_rows)[1]
    )
  }

  x_all <- model.matrix(
    spec$model_formula,
    data = df
  )

  x_all <- x_all[
    ,
    colnames(x_all) != "(Intercept)",
    drop = FALSE
  ]

  if (ncol(x_all) == 0L || any(!is.finite(x_all))) {
    stop("Invalid design matrix for ", spec$model_name)
  }

  for (origin_date in selected_dates) {
    origin_date <- as.Date(origin_date, origin = "1970-01-01")

    history_rows <- which(df$date < origin_date)
    forecast_rows <- which(
      df$split == "test" & df$date == origin_date
    )

    if (length(history_rows) == 0L) {
      stop("No history before ", origin_date)
    }

    if (length(forecast_rows) == 0L) {
      stop("No test matches on selected date ", origin_date)
    }

    history_end_date <- max(df$date[history_rows])

    if (history_end_date >= origin_date) {
      stop("Temporal leakage detected at ", origin_date)
    }

    original_audit_row <- rolling_audit[
      rolling_audit$probability_column == prob_col &
        rolling_audit$origin_date == origin_date,
      ,
      drop = FALSE
    ]

    original_convergence_code <- if (
      nrow(original_audit_row) == 0L
    ) {
      NA_integer_
    } else {
      as.integer(original_audit_row$convergence_code[1])
    }

    for (current_maxit in maxit_values) {
      fit_key <- paste(
        prob_col,
        format(origin_date, "%Y-%m-%d"),
        current_maxit,
        sep = "|"
      )

      if (fit_key %in% completed_keys) {
        next
      }

      set.seed(spec$seed)

      fit <- NULL
      elapsed_seconds <- system.time({
        fit <- tryCatch(
          nnet::nnet(
            x = x_all[history_rows, , drop = FALSE],
            y = df$y_a[history_rows],
            size = spec$size,
            decay = spec$decay,
            entropy = TRUE,
            maxit = current_maxit,
            trace = FALSE,
            MaxNWts = 20000
          ),
          error = function(e) {
            stop(
              "NN fitting failed for ",
              spec$model_name,
              " at ",
              origin_date,
              " with maxit = ",
              current_maxit,
              ": ",
              conditionMessage(e)
            )
          }
        )
      })[["elapsed"]]

      current_predictions <- tryCatch(
        as.numeric(
          predict(
            fit,
            x_all[forecast_rows, , drop = FALSE],
            type = "raw"
          )
        ),
        error = function(e) {
          stop(
            "NN prediction failed for ",
            spec$model_name,
            " at ",
            origin_date,
            " with maxit = ",
            current_maxit,
            ": ",
            conditionMessage(e)
          )
        }
      )

      if (
        length(current_predictions) != length(forecast_rows) ||
        any(!is.finite(current_predictions))
      ) {
        stop(
          "Invalid predictions for ",
          spec$model_name,
          " at ",
          origin_date,
          " with maxit = ",
          current_maxit
        )
      }

      current_predictions <- clip_prob(current_predictions)
      current_y <- df$y_a[forecast_rows]

      convergence_code <- if (is.null(fit$convergence)) {
        NA_integer_
      } else {
        as.integer(fit$convergence)
      }

      objective <- if (is.null(fit$value)) {
        NA_real_
      } else {
        as.numeric(fit$value)
      }

      existing_probabilities <- rep(
        NA_real_,
        length(forecast_rows)
      )

      if (!is.null(existing_nn_predictions)) {
        existing_probabilities <- as.numeric(
          existing_nn_predictions[[prob_col]][
            existing_match_index[forecast_rows]
          ]
        )
      }

      reproduction_difference <- if (
        current_maxit == 300L &&
        all(is.finite(existing_probabilities))
      ) {
        abs(current_predictions - existing_probabilities)
      } else {
        rep(NA_real_, length(current_predictions))
      }

      fit_summary_rows[[fit_key]] <- data.frame(
        model = spec$model_name,
        probability_column = prob_col,
        origin_date = origin_date,
        maxit = as.integer(current_maxit),
        size = spec$size,
        decay = spec$decay,
        seed = spec$seed,
        n_history = length(history_rows),
        history_end_date = history_end_date,
        n_forecasts = length(forecast_rows),
        convergence_code = convergence_code,
        convergence_status = convergence_label(convergence_code),
        original_convergence_code = original_convergence_code,
        objective = objective,
        elapsed_seconds = as.numeric(elapsed_seconds),
        logloss = log_loss(current_y, current_predictions),
        brier = brier_score(current_y, current_predictions),
        accuracy = accuracy_score(current_y, current_predictions),
        mean_abs_difference_from_existing = if (
          all(is.na(reproduction_difference))
        ) {
          NA_real_
        } else {
          mean(reproduction_difference, na.rm = TRUE)
        },
        max_abs_difference_from_existing = if (
          all(is.na(reproduction_difference))
        ) {
          NA_real_
        } else {
          max(reproduction_difference, na.rm = TRUE)
        },
        stringsAsFactors = FALSE
      )

      prediction_rows[[fit_key]] <- data.frame(
        model = spec$model_name,
        probability_column = prob_col,
        origin_date = origin_date,
        match_id = df$match_id[forecast_rows],
        y_a = current_y,
        maxit = as.integer(current_maxit),
        probability = current_predictions,
        predicted_class = ifelse(
          current_predictions >= 0.5,
          1L,
          0L
        ),
        single_logloss = single_logloss(
          current_y,
          current_predictions
        ),
        existing_probability = if (
          current_maxit == 300L
        ) {
          existing_probabilities
        } else {
          NA_real_
        },
        stringsAsFactors = FALSE
      )

      completed_keys <- c(completed_keys, fit_key)

      saveRDS(
        list(
          signature = checkpoint_signature,
          completed_keys = completed_keys,
          fit_summary_rows = fit_summary_rows,
          prediction_rows = prediction_rows
        ),
        checkpoint_file
      )

      cat(
        "Completed ",
        length(completed_keys),
        " of ",
        total_fits,
        " | ",
        spec$model_name,
        " | ",
        format(origin_date, "%Y-%m-%d"),
        " | maxit = ",
        current_maxit,
        " | convergence = ",
        convergence_code,
        " | log loss = ",
        round(log_loss(current_y, current_predictions), 6),
        "\n",
        sep = ""
      )
    }
  }
}

fit_summary <- do.call(rbind, unname(fit_summary_rows))
prediction_detail <- do.call(rbind, unname(prediction_rows))

rownames(fit_summary) <- NULL
rownames(prediction_detail) <- NULL

fit_summary <- fit_summary[
  order(
    fit_summary$probability_column,
    fit_summary$origin_date,
    fit_summary$maxit
  ),
  ,
  drop = FALSE
]

prediction_detail <- prediction_detail[
  order(
    prediction_detail$probability_column,
    prediction_detail$origin_date,
    prediction_detail$match_id,
    prediction_detail$maxit
  ),
  ,
  drop = FALSE
]

write.csv(
  fit_summary,
  file.path(
    output_dir,
    "nn_convergence_sensitivity_fit_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  prediction_detail,
  file.path(
    output_dir,
    "nn_convergence_sensitivity_predictions.csv"
  ),
  row.names = FALSE
)

############################################################
# Compare maxit = 300 and maxit = 1000
############################################################

compare_prediction_sets <- function(data_300, data_1000) {
  keep_columns <- c(
    "match_id",
    "y_a",
    "probability",
    "predicted_class"
  )

  d300 <- data_300[, keep_columns, drop = FALSE]
  d1000 <- data_1000[, keep_columns, drop = FALSE]

  names(d300) <- c(
    "match_id",
    "y_a_300",
    "probability_300",
    "predicted_class_300"
  )

  names(d1000) <- c(
    "match_id",
    "y_a_1000",
    "probability_1000",
    "predicted_class_1000"
  )

  merged <- merge(
    d300,
    d1000,
    by = "match_id",
    all = FALSE,
    sort = TRUE
  )

  if (
    nrow(merged) != nrow(d300) ||
    nrow(merged) != nrow(d1000)
  ) {
    stop("The maxit prediction sets do not contain the same matches.")
  }

  if (any(merged$y_a_300 != merged$y_a_1000)) {
    stop("Outcome mismatch between maxit prediction sets.")
  }

  merged
}

by_origin_rows <- list()

for (prob_col in names(model_specs)) {
  spec <- model_specs[[prob_col]]

  for (origin_date in selected_dates) {
    origin_date <- as.Date(origin_date, origin = "1970-01-01")

    d300 <- prediction_detail[
      prediction_detail$probability_column == prob_col &
        prediction_detail$origin_date == origin_date &
        prediction_detail$maxit == 300L,
      ,
      drop = FALSE
    ]

    d1000 <- prediction_detail[
      prediction_detail$probability_column == prob_col &
        prediction_detail$origin_date == origin_date &
        prediction_detail$maxit == 1000L,
      ,
      drop = FALSE
    ]

    merged <- compare_prediction_sets(d300, d1000)
    probability_change <-
      merged$probability_1000 - merged$probability_300

    fit_300 <- fit_summary[
      fit_summary$probability_column == prob_col &
        fit_summary$origin_date == origin_date &
        fit_summary$maxit == 300L,
      ,
      drop = FALSE
    ]

    fit_1000 <- fit_summary[
      fit_summary$probability_column == prob_col &
        fit_summary$origin_date == origin_date &
        fit_summary$maxit == 1000L,
      ,
      drop = FALSE
    ]

    y <- merged$y_a_300

    by_origin_rows[[paste(prob_col, origin_date)]] <- data.frame(
      model = spec$model_name,
      probability_column = prob_col,
      origin_date = origin_date,
      n_matches = nrow(merged),
      convergence_code_300 = one_value(
        fit_300$convergence_code,
        NA_integer_
      ),
      convergence_code_1000 = one_value(
        fit_1000$convergence_code,
        NA_integer_
      ),
      objective_300 = one_value(fit_300$objective),
      objective_1000 = one_value(fit_1000$objective),
      mean_abs_probability_change = mean(
        abs(probability_change)
      ),
      max_abs_probability_change = max(
        abs(probability_change)
      ),
      rmse_probability_change = sqrt(
        mean(probability_change^2)
      ),
      direction_changes = sum(
        merged$predicted_class_300 !=
          merged$predicted_class_1000
      ),
      direction_change_rate = mean(
        merged$predicted_class_300 !=
          merged$predicted_class_1000
      ),
      logloss_300 = log_loss(y, merged$probability_300),
      logloss_1000 = log_loss(y, merged$probability_1000),
      logloss_change_1000_minus_300 =
        log_loss(y, merged$probability_1000) -
        log_loss(y, merged$probability_300),
      brier_300 = brier_score(y, merged$probability_300),
      brier_1000 = brier_score(y, merged$probability_1000),
      accuracy_300 = accuracy_score(y, merged$probability_300),
      accuracy_1000 = accuracy_score(y, merged$probability_1000),
      stringsAsFactors = FALSE
    )
  }
}

by_origin_comparison <- do.call(rbind, unname(by_origin_rows))
rownames(by_origin_comparison) <- NULL

by_origin_comparison <- by_origin_comparison[
  order(
    by_origin_comparison$probability_column,
    by_origin_comparison$origin_date
  ),
  ,
  drop = FALSE
]

write.csv(
  by_origin_comparison,
  file.path(
    output_dir,
    "nn_convergence_sensitivity_by_origin.csv"
  ),
  row.names = FALSE
)

############################################################
# Aggregate sensitivity summary by model
############################################################

reference_primary_advantage <- NA_real_

if (file.exists(model_comparison_file)) {
  model_comparison <- read.csv(
    model_comparison_file,
    stringsAsFactors = FALSE
  )
  names(model_comparison) <- tolower(names(model_comparison))

  required_comparison_columns <- c(
    "model",
    "split",
    "logloss"
  )

  if (
    all(required_comparison_columns %in%
        names(model_comparison))
  ) {
    primary_logistic_logloss <- model_comparison$logloss[
      model_comparison$model ==
        "Logistic full + short-term + H2H" &
        model_comparison$split == "test"
    ]

    primary_nn_logloss <- model_comparison$logloss[
      model_comparison$model ==
        "Neural network + short-term" &
        model_comparison$split == "test"
    ]

    if (
      length(primary_logistic_logloss) > 0L &&
      length(primary_nn_logloss) > 0L
    ) {
      reference_primary_advantage <-
        primary_logistic_logloss[1] - primary_nn_logloss[1]
    }
  }
}

summary_rows <- list()

for (prob_col in names(model_specs)) {
  spec <- model_specs[[prob_col]]

  d300 <- prediction_detail[
    prediction_detail$probability_column == prob_col &
      prediction_detail$maxit == 300L,
    ,
    drop = FALSE
  ]

  d1000 <- prediction_detail[
    prediction_detail$probability_column == prob_col &
      prediction_detail$maxit == 1000L,
    ,
    drop = FALSE
  ]

  merged <- compare_prediction_sets(d300, d1000)
  probability_change <-
    merged$probability_1000 - merged$probability_300

  model_fits <- fit_summary[
    fit_summary$probability_column == prob_col,
    ,
    drop = FALSE
  ]

  fits_300 <- model_fits[model_fits$maxit == 300L, , drop = FALSE]
  fits_1000 <- model_fits[model_fits$maxit == 1000L, , drop = FALSE]

  convergence_pair <- merge(
    fits_300[, c("origin_date", "convergence_code")],
    fits_1000[, c("origin_date", "convergence_code")],
    by = "origin_date",
    suffixes = c("_300", "_1000"),
    all = FALSE
  )

  y <- merged$y_a_300
  pooled_logloss_300 <- log_loss(y, merged$probability_300)
  pooled_logloss_1000 <- log_loss(y, merged$probability_1000)
  pooled_logloss_change <-
    pooled_logloss_1000 - pooled_logloss_300

  reproduction_values <- fits_300$max_abs_difference_from_existing
  reproduction_values <- reproduction_values[
    is.finite(reproduction_values)
  ]

  original_code_available <- !is.na(
    fits_300$original_convergence_code
  ) & !is.na(fits_300$convergence_code)

  original_code_match_rate <- if (
    any(original_code_available)
  ) {
    mean(
      fits_300$original_convergence_code[original_code_available] ==
        fits_300$convergence_code[original_code_available]
    )
  } else {
    NA_real_
  }

  is_primary <- prob_col == primary_probability_column

  reference_value <- if (is_primary) {
    reference_primary_advantage
  } else {
    NA_real_
  }

  change_to_reference_ratio <- if (
    is_primary &&
    is.finite(reference_value) &&
    reference_value > 0
  ) {
    abs(pooled_logloss_change) / reference_value
  } else {
    NA_real_
  }

  summary_rows[[prob_col]] <- data.frame(
    model = spec$model_name,
    probability_column = prob_col,
    n_sampled_origins = nrow(convergence_pair),
    n_sampled_matches = nrow(merged),
    converged_origins_300 = sum(
      convergence_pair$convergence_code_300 == 0L,
      na.rm = TRUE
    ),
    converged_origins_1000 = sum(
      convergence_pair$convergence_code_1000 == 0L,
      na.rm = TRUE
    ),
    improved_to_converged_origins = sum(
      convergence_pair$convergence_code_300 != 0L &
        convergence_pair$convergence_code_1000 == 0L,
      na.rm = TRUE
    ),
    still_not_converged_origins_1000 = sum(
      convergence_pair$convergence_code_1000 != 0L,
      na.rm = TRUE
    ),
    mean_abs_probability_change = mean(
      abs(probability_change)
    ),
    max_abs_probability_change = max(
      abs(probability_change)
    ),
    rmse_probability_change = sqrt(
      mean(probability_change^2)
    ),
    direction_changes = sum(
      merged$predicted_class_300 !=
        merged$predicted_class_1000
    ),
    direction_change_rate = mean(
      merged$predicted_class_300 !=
        merged$predicted_class_1000
    ),
    pooled_logloss_300 = pooled_logloss_300,
    pooled_logloss_1000 = pooled_logloss_1000,
    logloss_change_1000_minus_300 = pooled_logloss_change,
    pooled_brier_300 = brier_score(y, merged$probability_300),
    pooled_brier_1000 = brier_score(y, merged$probability_1000),
    pooled_accuracy_300 = accuracy_score(
      y,
      merged$probability_300
    ),
    pooled_accuracy_1000 = accuracy_score(
      y,
      merged$probability_1000
    ),
    max_abs_difference_from_existing_300 = if (
      length(reproduction_values) == 0L
    ) {
      NA_real_
    } else {
      max(reproduction_values)
    },
    original_convergence_code_match_rate =
      original_code_match_rate,
    reference_primary_nn_advantage = reference_value,
    abs_logloss_change_to_reference_ratio =
      change_to_reference_ratio,
    change_at_least_as_large_as_reference = if (
      is_primary &&
      is.finite(reference_value) &&
      reference_value > 0
    ) {
      abs(pooled_logloss_change) >= reference_value
    } else {
      NA
    },
    stringsAsFactors = FALSE
  )
}

sensitivity_summary <- do.call(rbind, unname(summary_rows))
rownames(sensitivity_summary) <- NULL

write.csv(
  sensitivity_summary,
  file.path(
    output_dir,
    "nn_convergence_sensitivity_summary.csv"
  ),
  row.names = FALSE
)

############################################################
# Console summary
############################################################

cat("\n============================================================\n")
cat("NN convergence sensitivity check completed\n")
cat("============================================================\n\n")

print(sensitivity_summary)

primary_summary <- sensitivity_summary[
  sensitivity_summary$probability_column ==
    primary_probability_column,
  ,
  drop = FALSE
]

if (nrow(primary_summary) == 1L) {
  cat("\nPrimary short-term NN screening result:\n")
  cat(
    "Pooled sampled-date log-loss change (1000 minus 300): ",
    format(
      primary_summary$logloss_change_1000_minus_300,
      digits = 8
    ),
    "\n",
    sep = ""
  )
  cat(
    "Mean absolute probability change: ",
    format(
      primary_summary$mean_abs_probability_change,
      digits = 8
    ),
    "\n",
    sep = ""
  )
  cat(
    "Direction-change rate: ",
    format(
      primary_summary$direction_change_rate,
      digits = 6
    ),
    "\n",
    sep = ""
  )
  cat(
    "Converged sampled origins at maxit 300 / 1000: ",
    primary_summary$converged_origins_300,
    " / ",
    primary_summary$converged_origins_1000,
    "\n",
    sep = ""
  )

  if (
    is.finite(primary_summary$reference_primary_nn_advantage)
  ) {
    cat(
      "Current full-test NN advantage over primary logistic: ",
      format(
        primary_summary$reference_primary_nn_advantage,
        digits = 8
      ),
      "\n",
      sep = ""
    )
    cat(
      "Absolute sensitivity change / current advantage: ",
      format(
        primary_summary$abs_logloss_change_to_reference_ratio,
        digits = 6
      ),
      "\n",
      sep = ""
    )
  }

  if (
    is.finite(
      primary_summary$max_abs_difference_from_existing_300
    ) &&
    primary_summary$max_abs_difference_from_existing_300 > 1e-10
  ) {
    warning(
      "The refitted maxit = 300 predictions did not reproduce the ",
      "existing sampled predictions within 1e-10. Check the files ",
      "before interpreting the maxit comparison."
    )
  }

  if (
    is.finite(
      primary_summary$original_convergence_code_match_rate
    ) &&
    primary_summary$original_convergence_code_match_rate < 1
  ) {
    warning(
      "Some maxit = 300 convergence codes did not match the original ",
      "audit. Check reproducibility before interpreting the results."
    )
  }
}

cat("\nResults saved in:\n")
cat(output_dir, "\n")
cat(
  "Send nn_convergence_sensitivity_summary.csv and ",
  "nn_convergence_sensitivity_by_origin.csv for interpretation.\n"
)

