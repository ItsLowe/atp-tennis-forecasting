# Phase 1 repository preparation; analysis NOT RUN.
# Author: Zhiheng Huang
# Purpose: Generate annual-refit TTT forecasts with same-date predictions before daily updates.
# Source: 05_TTTBaseline.R
# Working directory: repository root (not R/).
# Dependencies: TrueSkillThroughTime, hash.
# Inputs: see reproducibility/dependencies.md, stage 05.
# Outputs: see reproducibility/dependencies.md; generated data stay private.
# Order: 05 of 14; see reproducibility/pipeline.md.
# Phase 1 edits: see reproducibility/code_edits.md and code_edits.patch.
rm(list = ls())


required_packages <- c(
  "TrueSkillThroughTime",
  "hash"
)

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0) {
  stop(
    "Install the following packages before running this script: ",
    paste(missing_packages, collapse = ", "),
    "\nRun:\ninstall.packages(c(",
    paste(
      paste0('"', missing_packages, '"'),
      collapse = ", "
    ),
    "))"
  )
}

############################################################
# File paths
############################################################

input_file <- "data/processed/atp_ttt_input_2010_2025.csv"

processed_dir <- "data/processed"
table_dir <- "outputs/tables"
log_dir <- "outputs/logs"

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
  log_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

# New annual TTT output.
# The old sequential TrueSkill output is not overwritten.

output_file <- file.path(
  processed_dir,
  "atp_ttt_genuine_yearly_predictions_2010_2025.csv"
)

checkpoint_file <- file.path(
  processed_dir,
  "atp_ttt_genuine_yearly_predictions_checkpoint.csv"
)

metrics_file <- file.path(
  table_dir,
  "ttt_genuine_yearly_metrics_by_split.csv"
)

comparison_file <- file.path(
  table_dir,
  "ttt_genuine_yearly_vs_bookmaker_by_split.csv"
)

settings_file <- file.path(
  table_dir,
  "ttt_genuine_yearly_model_settings.csv"
)

run_log_file <- file.path(
  log_dir,
  "ttt_genuine_yearly_run_log.txt"
)

session_file <- file.path(
  log_dir,
  "ttt_genuine_yearly_sessionInfo.txt"
)

############################################################
# Run settings
############################################################

# TRUE:
# - use an existing annual checkpoint if available;
# - skip years that have already been completed.
#
# FALSE:
# - ignore any existing checkpoint and start from 2010.
#
# The checkpoint filename is annual-specific, so it will not
# read the previous monthly checkpoint.

RESUME_FROM_CHECKPOINT <- TRUE

# Save the complete working dataset after each completed year.

SAVE_CHECKPOINTS <- TRUE

############################################################
# TTT model parameters
############################################################

# These retain the same scale as the previous baseline.
# Parameter tuning, if later conducted, must use training and
# validation data only.

MU0 <- 0
SIGMA0 <- 6
BETA <- 1
GAMMA <- 0.03
P_DRAW <- 0

# Full-history TTT convergence at the start of each year.

CONVERGENCE_EPSILON <- 0.01
CONVERGENCE_ITERATIONS <- 10

# Updating all matches from one day.
#
# Dynamic uncertainty between dates is added manually before
# constructing the daily History object. Gamma is therefore
# set to zero inside each daily object.

DAY_EPSILON <- 0.001
DAY_ITERATIONS <- 10

# Numerical protection for probability evaluation.

PROB_EPS <- 1e-15

############################################################
# Read input data
############################################################

if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file)
}

df <- read.csv(
  input_file,
  stringsAsFactors = FALSE
)

names(df) <- tolower(names(df))

required_cols <- c(
  "match_id",
  "date",
  "split",
  "player_a",
  "player_b",
  "player_a_id",
  "player_b_id",
  "y_a",
  "p_book_final_a"
)

missing_cols <- required_cols[
  !required_cols %in% names(df)
]

if (length(missing_cols) > 0) {
  stop(
    "Missing required columns: ",
    paste(missing_cols, collapse = ", ")
  )
}

############################################################
# Validate and order the data
############################################################

df$date <- as.Date(df$date)

if (any(is.na(df$date))) {
  stop(
    "Some dates could not be converted to Date format."
  )
}

df$date_num <- as.integer(df$date)

if (!"year" %in% names(df)) {
  df$year <- as.integer(
    format(df$date, "%Y")
  )
}

df$split <- tolower(df$split)
df$y_a <- as.integer(df$y_a)

if (any(is.na(df$y_a))) {
  stop("y_a contains missing values.")
}

if (any(!df$y_a %in% c(0L, 1L))) {
  stop("y_a must contain only 0 and 1.")
}

if (
  any(is.na(df$player_a_id)) ||
  any(is.na(df$player_b_id))
) {
  stop("Player IDs contain missing values.")
}

if (any(df$player_a_id == df$player_b_id)) {
  stop(
    "At least one match has the same player on both sides."
  )
}

if (any(duplicated(df$match_id))) {
  stop("Duplicate match_id values were found.")
}

df <- df[
  order(
    df$date_num,
    df$match_id
  ),
]

rownames(df) <- NULL

# TTT package uses names or character identifiers.

df$player_a_key <- as.character(
  df$player_a_id
)

df$player_b_key <- as.character(
  df$player_b_id
)

all_player_keys <- sort(
  unique(
    c(
      df$player_a_key,
      df$player_b_key
    )
  )
)

analysis_years <- sort(
  unique(df$year)
)

cat(
  "Rows:",
  nrow(df),
  "\n"
)

cat(
  "Players:",
  length(all_player_keys),
  "\n"
)

cat(
  "Years:",
  min(analysis_years),
  "to",
  max(analysis_years),
  "\n\n"
)

############################################################
# Initialise prediction columns
############################################################

numeric_prediction_cols <- c(
  "p_ttt_a",
  "ttt_mu_a_pre",
  "ttt_sigma_a_pre",
  "ttt_mu_b_pre",
  "ttt_sigma_b_pre",
  "ttt_mu_diff_a_minus_b",
  "ttt_combined_uncertainty",
  "ttt_refit_past_matches",
  "ttt_refit_year"
)

for (v in numeric_prediction_cols) {
  df[[v]] <- NA_real_
}

df$ttt_refit_frequency <- NA_character_

prediction_cols <- c(
  numeric_prediction_cols,
  "ttt_refit_frequency"
)

############################################################
# Recover annual checkpoint
############################################################

if (
  RESUME_FROM_CHECKPOINT &&
  file.exists(checkpoint_file)
) {
  checkpoint <- read.csv(
    checkpoint_file,
    stringsAsFactors = FALSE
  )
  
  names(checkpoint) <- tolower(
    names(checkpoint)
  )
  
  if (!"match_id" %in% names(checkpoint)) {
    stop(
      "The checkpoint file does not contain match_id."
    )
  }
  
  if (any(duplicated(checkpoint$match_id))) {
    stop(
      "The checkpoint contains duplicate match_id values."
    )
  }
  
  if (
    "ttt_refit_frequency" %in% names(checkpoint)
  ) {
    checkpoint_frequencies <- unique(
      checkpoint$ttt_refit_frequency[
        !is.na(
          checkpoint$ttt_refit_frequency
        )
      ]
    )
    
    if (
      length(checkpoint_frequencies) > 0 &&
      any(checkpoint_frequencies != "year")
    ) {
      stop(
        "The checkpoint was not produced by the annual ",
        "TTT procedure. Delete or rename it before running."
      )
    }
  }
  
  checkpoint_index <- match(
    df$match_id,
    checkpoint$match_id
  )
  
  for (v in prediction_cols) {
    if (v %in% names(checkpoint)) {
      df[[v]] <- checkpoint[[v]][
        checkpoint_index
      ]
    }
  }
  
  cat(
    "Recovered",
    sum(!is.na(df$p_ttt_a)),
    "predictions from annual checkpoint.\n\n"
  )
}

############################################################
# Probability and evaluation functions
############################################################

clip_prob <- function(
    p,
    eps = PROB_EPS
) {
  pmin(
    pmax(p, eps),
    1 - eps
  )
}

predict_win_prob <- function(
    mu_a,
    sigma_a,
    mu_b,
    sigma_b,
    beta
) {
  denominator <- sqrt(
    sigma_a^2 +
      sigma_b^2 +
      2 * beta^2
  )
  
  p <- stats::pnorm(
    (mu_a - mu_b) /
      denominator
  )
  
  clip_prob(p)
}

log_loss <- function(y, p) {
  p <- clip_prob(p)
  
  -mean(
    y * log(p) +
      (1 - y) * log(1 - p),
    na.rm = TRUE
  )
}

brier_score <- function(y, p) {
  mean(
    (y - p)^2,
    na.rm = TRUE
  )
}

accuracy_score <- function(y, p) {
  predicted_outcome <- as.integer(
    p >= 0.5
  )
  
  mean(
    predicted_outcome == y,
    na.rm = TRUE
  )
}

mean_prob_winner <- function(y, p) {
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

evaluate_by_split <- function(
    data,
    prob_col,
    model_name
) {
  split_names <- c(
    "train",
    "validation",
    "test"
  )
  
  result_list <- vector(
    "list",
    length(split_names)
  )
  
  for (j in seq_along(split_names)) {
    split_name <- split_names[j]
    
    d <- data[
      data$split == split_name,
      ,
      drop = FALSE
    ]
    
    metrics <- evaluate_predictions(
      d,
      prob_col
    )
    
    metrics$model <- model_name
    metrics$split <- split_name
    
    result_list[[j]] <- metrics
  }
  
  result <- do.call(
    rbind,
    result_list
  )
  
  rownames(result) <- NULL
  
  result[
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

############################################################
# Run log function
############################################################

append_log <- function(...) {
  text <- paste0(...)
  
  cat(
    text,
    "\n"
  )
  
  cat(
    format(
      Sys.time(),
      "%Y-%m-%d %H:%M:%S"
    ),
    " | ",
    text,
    "\n",
    file = run_log_file,
    append = TRUE,
    sep = ""
  )
}

############################################################
# Convert match data to TTT input structure
############################################################

make_composition <- function(data) {
  lapply(
    seq_len(nrow(data)),
    function(i) {
      list(
        c(data$player_a_key[i]),
        c(data$player_b_key[i])
      )
    }
  )
}

make_results <- function(data) {
  lapply(
    data$y_a,
    function(y) {
      c(
        as.numeric(y),
        as.numeric(1L - y)
      )
    }
  )
}

############################################################
# Extract final player distributions from TTT history
############################################################

extract_endpoint_states <- function(
    history_object
) {
  curves <- history_object$learning_curves()
  
  if (length(curves) == 0) {
    return(
      data.frame(
        player_key = character(0),
        mu = numeric(0),
        sigma = numeric(0),
        last_time = numeric(0),
        stringsAsFactors = FALSE
      )
    )
  }
  
  player_keys <- names(curves)
  
  result_list <- vector(
    "list",
    length(player_keys)
  )
  
  for (j in seq_along(player_keys)) {
    player_key <- player_keys[j]
    curve <- curves[[player_key]]
    
    if (length(curve) == 0) {
      next
    }
    
    curve_times <- vapply(
      curve,
      function(point) {
        as.numeric(point$t)
      },
      numeric(1)
    )
    
    final_time <- max(
      curve_times
    )
    
    final_indices <- which(
      curve_times == final_time
    )
    
    final_index <- tail(
      final_indices,
      1
    )
    
    final_point <- curve[[
      final_index
    ]]
    
    final_distribution <- final_point$N
    
    result_list[[j]] <- data.frame(
      player_key = player_key,
      mu = final_distribution@mu,
      sigma = final_distribution@sigma,
      last_time = as.numeric(
        final_point$t
      ),
      stringsAsFactors = FALSE
    )
  }
  
  result_list <- result_list[
    !vapply(
      result_list,
      is.null,
      logical(1)
    )
  ]
  
  if (length(result_list) == 0) {
    return(
      data.frame(
        player_key = character(0),
        mu = numeric(0),
        sigma = numeric(0),
        last_time = numeric(0),
        stringsAsFactors = FALSE
      )
    )
  }
  
  result <- do.call(
    rbind,
    result_list
  )
  
  rownames(result) <- NULL
  
  result
}

############################################################
# Fit genuine TTT to all matches before one year
############################################################

fit_past_history <- function(
    past_data
) {
  if (nrow(past_data) == 0) {
    return(NULL)
  }
  
  composition <- make_composition(
    past_data
  )
  
  results <- make_results(
    past_data
  )
  
  times <- past_data$date_num
  
  history_object <-
    TrueSkillThroughTime::History(
      composition = composition,
      results = results,
      times = times,
      mu = MU0,
      sigma = SIGMA0,
      beta = BETA,
      gamma = GAMMA,
      p_draw = P_DRAW
    )
  
  history_object$convergence(
    epsilon = CONVERGENCE_EPSILON,
    iterations = CONVERGENCE_ITERATIONS,
    verbose = FALSE
  )
  
  history_object
}

############################################################
# Player state functions
############################################################

new_default_state <- function() {
  list(
    mu = stats::setNames(
      rep(
        MU0,
        length(all_player_keys)
      ),
      all_player_keys
    ),
    sigma = stats::setNames(
      rep(
        SIGMA0,
        length(all_player_keys)
      ),
      all_player_keys
    ),
    last_time = stats::setNames(
      rep(
        NA_real_,
        length(all_player_keys)
      ),
      all_player_keys
    )
  )
}

state_from_past_history <- function(
    past_history
) {
  state <- new_default_state()
  
  if (is.null(past_history)) {
    return(state)
  }
  
  endpoints <- extract_endpoint_states(
    past_history
  )
  
  if (nrow(endpoints) == 0) {
    return(state)
  }
  
  player_keys <- endpoints$player_key
  
  state$mu[player_keys] <-
    endpoints$mu
  
  state$sigma[player_keys] <-
    endpoints$sigma
  
  state$last_time[player_keys] <-
    endpoints$last_time
  
  state
}

state_prior_at_time <- function(
    state,
    player_key,
    current_time
) {
  mu <- unname(
    state$mu[player_key]
  )
  
  sigma <- unname(
    state$sigma[player_key]
  )
  
  last_time <- unname(
    state$last_time[player_key]
  )
  
  if (is.na(mu)) {
    mu <- MU0
  }
  
  if (is.na(sigma)) {
    sigma <- SIGMA0
  }
  
  if (
    !is.na(last_time) &&
    current_time > last_time
  ) {
    elapsed_time <-
      current_time - last_time
    
    sigma <- sqrt(
      sigma^2 +
        GAMMA^2 *
        elapsed_time
    )
  }
  
  list(
    mu = mu,
    sigma = sigma
  )
}

############################################################
# Update player states after one complete day
############################################################

update_state_with_day <- function(
    state,
    day_data,
    current_day
) {
  players_today <- sort(
    unique(
      c(
        day_data$player_a_key,
        day_data$player_b_key
      )
    )
  )
  
  priors <- hash::hash()
  
  for (player_key in players_today) {
    current_prior <- state_prior_at_time(
      state = state,
      player_key = player_key,
      current_time = current_day
    )
    
    priors[[player_key]] <-
      TrueSkillThroughTime::Player(
        prior =
          TrueSkillThroughTime::Gaussian(
            mu = current_prior$mu,
            sigma = current_prior$sigma
          ),
        beta = BETA,
        gamma = 0
      )
  }
  
  # Every match on the date receives the same internal
  # timestamp. No match from that date is treated as occurring
  # before another match from the same date.
  
  daily_history <-
    TrueSkillThroughTime::History(
      composition =
        make_composition(day_data),
      results =
        make_results(day_data),
      times =
        rep(1, nrow(day_data)),
      priors = priors,
      mu = MU0,
      sigma = SIGMA0,
      beta = BETA,
      gamma = 0,
      p_draw = P_DRAW
    )
  
  daily_history$convergence(
    epsilon = DAY_EPSILON,
    iterations = DAY_ITERATIONS,
    verbose = FALSE
  )
  
  endpoints <- extract_endpoint_states(
    daily_history
  )
  
  if (nrow(endpoints) > 0) {
    player_keys <- endpoints$player_key
    
    state$mu[player_keys] <-
      endpoints$mu
    
    state$sigma[player_keys] <-
      endpoints$sigma
    
    # Replace the internal timestamp of 1 with the actual
    # calendar date used by the main history.
    
    state$last_time[player_keys] <-
      current_day
  }
  
  state
}

############################################################
# Annual rolling-origin predictions
############################################################

append_log(
  "Starting annual rolling-origin TTT run. ",
  "Years = ",
  min(analysis_years),
  "-",
  max(analysis_years),
  "; package version = ",
  as.character(
    utils::packageVersion(
      "TrueSkillThroughTime"
    )
  ),
  "."
)

for (
  year_index in seq_along(
    analysis_years
  )
) {
  target_year <- analysis_years[
    year_index
  ]
  
  year_rows <- which(
    df$year == target_year
  )
  
  if (length(year_rows) == 0) {
    next
  }
  
  # Skip a year recovered completely from the annual
  # checkpoint.
  
  if (
    all(
      !is.na(
        df$p_ttt_a[year_rows]
      )
    )
  ) {
    append_log(
      "Skipping completed year ",
      target_year,
      " (",
      year_index,
      "/",
      length(analysis_years),
      ")."
    )
    
    next
  }
  
  year_start_day <- min(
    df$date_num[year_rows]
  )
  
  # Strictly past matches only.
  
  past_data <- df[
    df$date_num < year_start_day,
    ,
    drop = FALSE
  ]
  
  append_log(
    "Fitting year ",
    target_year,
    " (",
    year_index,
    "/",
    length(analysis_years),
    ")",
    "; past matches = ",
    nrow(past_data),
    "; target matches = ",
    length(year_rows),
    "."
  )
  
  convergence_start <- Sys.time()
  
  # Genuine TTT forward-backward convergence using all
  # information available before the target year.
  
  past_history <- fit_past_history(
    past_data
  )
  
  state <- state_from_past_history(
    past_history
  )
  
  convergence_minutes <- as.numeric(
    difftime(
      Sys.time(),
      convergence_start,
      units = "mins"
    )
  )
  
  append_log(
    "Past-history convergence finished for ",
    target_year,
    " in ",
    round(
      convergence_minutes,
      2
    ),
    " minutes."
  )
  
  year_days <- sort(
    unique(
      df$date_num[year_rows]
    )
  )
  
  for (current_day in year_days) {
    day_rows <- year_rows[
      df$date_num[year_rows] ==
        current_day
    ]
    
    day_data <- df[
      day_rows,
      ,
      drop = FALSE
    ]
    
    players_today <- sort(
      unique(
        c(
          day_data$player_a_key,
          day_data$player_b_key
        )
      )
    )
    
    # Calculate each player's prior once for the date.
    
    prior_cache <- vector(
      "list",
      length(players_today)
    )
    
    names(prior_cache) <-
      players_today
    
    for (player_key in players_today) {
      prior_cache[[player_key]] <-
        state_prior_at_time(
          state = state,
          player_key = player_key,
          current_time = current_day
        )
    }
    
    ########################################################
    # Generate all predictions for the date
    ########################################################
    
    for (row_id in day_rows) {
      player_a_key <-
        df$player_a_key[row_id]
      
      player_b_key <-
        df$player_b_key[row_id]
      
      prior_a <-
        prior_cache[[player_a_key]]
      
      prior_b <-
        prior_cache[[player_b_key]]
      
      df$ttt_mu_a_pre[row_id] <-
        prior_a$mu
      
      df$ttt_sigma_a_pre[row_id] <-
        prior_a$sigma
      
      df$ttt_mu_b_pre[row_id] <-
        prior_b$mu
      
      df$ttt_sigma_b_pre[row_id] <-
        prior_b$sigma
      
      df$ttt_mu_diff_a_minus_b[row_id] <-
        prior_a$mu - prior_b$mu
      
      df$ttt_combined_uncertainty[row_id] <-
        sqrt(
          prior_a$sigma^2 +
            prior_b$sigma^2
        )
      
      df$p_ttt_a[row_id] <-
        predict_win_prob(
          mu_a = prior_a$mu,
          sigma_a = prior_a$sigma,
          mu_b = prior_b$mu,
          sigma_b = prior_b$sigma,
          beta = BETA
        )
      
      df$ttt_refit_past_matches[row_id] <-
        nrow(past_data)
      
      df$ttt_refit_year[row_id] <-
        target_year
      
      df$ttt_refit_frequency[row_id] <-
        "year"
    }
    
    ########################################################
    # Update after all predictions for the date
    ########################################################
    
    state <- update_state_with_day(
      state = state,
      day_data = day_data,
      current_day = current_day
    )
  }
  
  ##########################################################
  # Save checkpoint after completed year
  ##########################################################
  
  if (SAVE_CHECKPOINTS) {
    write.csv(
      df,
      checkpoint_file,
      row.names = FALSE
    )
  }
  
  append_log(
    "Completed year ",
    target_year,
    "; cumulative predictions = ",
    sum(!is.na(df$p_ttt_a)),
    "."
  )
  
  rm(
    past_history,
    state
  )
  
  invisible(gc())
}

############################################################
# Final checks
############################################################

missing_predictions <- sum(
  is.na(df$p_ttt_a)
)

cat(
  "\nMissing TTT predictions:",
  missing_predictions,
  "\n"
)

if (missing_predictions > 0) {
  stop(
    "The final dataset contains ",
    missing_predictions,
    " missing TTT predictions."
  )
}

if (
  any(
    df$p_ttt_a <= 0 |
    df$p_ttt_a >= 1
  )
) {
  stop(
    "At least one TTT probability is outside (0, 1)."
  )
}

if (
  any(
    is.na(
      df$ttt_combined_uncertainty
    )
  )
) {
  stop(
    "Some matches have missing TTT uncertainty."
  )
}

if (
  any(
    is.na(
      df$ttt_mu_diff_a_minus_b
    )
  )
) {
  stop(
    "Some matches have missing TTT mean differences."
  )
}

############################################################
# Save final prediction data
############################################################

df_output <- df

# Remove internal helper columns.

df_output$player_a_key <- NULL
df_output$player_b_key <- NULL

write.csv(
  df_output,
  output_file,
  row.names = FALSE
)

############################################################
# Evaluate genuine TTT and bookmaker benchmark
############################################################

ttt_metrics <- evaluate_by_split(
  df_output,
  "p_ttt_a",
  "TrueSkill Through Time"
)

bookmaker_metrics <- evaluate_by_split(
  df_output,
  "p_book_final_a",
  "Bookmaker"
)

comparison <- rbind(
  ttt_metrics,
  bookmaker_metrics
)

write.csv(
  ttt_metrics,
  metrics_file,
  row.names = FALSE
)

write.csv(
  comparison,
  comparison_file,
  row.names = FALSE
)

############################################################
# Save model and software settings
############################################################

settings <- data.frame(
  setting = c(
    "input_file",
    "output_file",
    "refit_frequency",
    "within_year_update",
    "same_day_handling",
    "mu",
    "sigma",
    "beta",
    "gamma",
    "p_draw",
    "convergence_epsilon",
    "convergence_iterations",
    "daily_epsilon",
    "daily_iterations",
    "r_version",
    "ttt_package_version",
    "first_year",
    "last_year",
    "number_of_matches",
    "number_of_players",
    "completed_at"
  ),
  value = c(
    input_file,
    output_file,
    "annual",
    "sequential daily updating",
    "predict all matches before daily update",
    MU0,
    SIGMA0,
    BETA,
    GAMMA,
    P_DRAW,
    CONVERGENCE_EPSILON,
    CONVERGENCE_ITERATIONS,
    DAY_EPSILON,
    DAY_ITERATIONS,
    paste(
      R.version$major,
      R.version$minor,
      sep = "."
    ),
    as.character(
      utils::packageVersion(
        "TrueSkillThroughTime"
      )
    ),
    min(df_output$year),
    max(df_output$year),
    nrow(df_output),
    length(all_player_keys),
    format(
      Sys.time(),
      "%Y-%m-%d %H:%M:%S"
    )
  ),
  stringsAsFactors = FALSE
)

write.csv(
  settings,
  settings_file,
  row.names = FALSE
)

capture.output(
  sessionInfo(),
  file = session_file
)

############################################################
# Print final results
############################################################

append_log(
  "Finished annual rolling-origin TTT run. ",
  "Predictions saved to: ",
  output_file,
  "."
)

cat(
  "\nFinished annual rolling-origin ",
  "TrueSkill Through Time baseline.\n\n"
)

cat(
  "Model comparison by split:\n"
)

print(comparison)

cat(
  "\nPredictions saved to:\n",
  output_file,
  "\n"
)

cat(
  "\nCheckpoint saved to:\n",
  checkpoint_file,
  "\n"
)

cat(
  "\nSettings saved to:\n",
  settings_file,
  "\n"
)

cat(
  "\nRun log saved to:\n",
  run_log_file,
  "\n"
)

