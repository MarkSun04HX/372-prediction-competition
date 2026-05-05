#!/usr/bin/env Rscript
# 03_process-data.R
# Transform pooled modeling parquet (output of 01_clean-data.R) into a fully
# encoded, NA-free dataset ready for 04_model-comparison.R.
#
# Steps applied in order (decisions informed by 02_eda.R findings):
#   1. Drop all continuous columns (n_unique > N_UNIQUE_THRESH) that have any NA.
#      No imputation — EDA revealed missingness is structural (tied to survey year)
#      and too pervasive to impute reliably.
#   2. Add TOTEXP_LOG1P = log1p(TOTEXP) as the model target.
#   3. One-hot encode nominal variables (meps_nominal_vars()):
#        a. Replace NA with max_non_NA + 1 so NA becomes its own integer level.
#        b. Expand via model.matrix (drop one reference level per var).
#        c. Remove original column; attach named dummy columns.
#   4. For all remaining categorical columns (n_unique <= N_UNIQUE_THRESH, not
#      already one-hot encoded): replace NA with max_non_NA + 1 in place.
#      EDA confirmed NA is structural/informative, not random — it becomes a
#      distinct integer the model can learn from.
#   5. Drop zero-variance columns.
#   6. Write processed parquet and print a column-count summary.
#
# Note: haven_labelled coercion and DUID/PID removal happen in 01_clean-data.R.
#
# Usage (from repo root):
#   Rscript scripts/03_process-data.R
#
# Environment variables:
#   N_UNIQUE_THRESH   integer threshold separating "continuous" from
#                     "categorical"; default 20

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
})

# ---- Resolve repo root -------------------------------------------------------

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "src", "exclude_variables.R"))

# ---- Config ------------------------------------------------------------------

N_UNIQUE_THRESH <- as.integer(Sys.getenv("N_UNIQUE_THRESH", unset = "20"))

in_path  <- file.path(root, "data", "processed",
                      "meps_fyc_2019_2023_pooled_for_modeling.parquet")
out_path <- file.path(root, "data", "processed",
                      "meps_fyc_2019_2023_pooled_for_modeling_processed.parquet")

if (!file.exists(in_path))
  stop("Missing pooled file — run scripts/01_clean-data.R first:\n  ", in_path)

# ---- 1. Read ----------------------------------------------------------------
# haven_labelled coercion and DUID/PID removal are done in 01_clean-data.R.

message("Reading ", in_path, " ...")
df <- arrow::read_parquet(in_path, as_data_frame = TRUE)
message("  ", nrow(df), " rows x ", ncol(df), " cols")

# ---- Classify columns --------------------------------------------------------

PROTECTED <- c("TOTEXP", "TOTEXP_LOG1P", "FYC_YEAR")

# Determine n_unique (excluding NA) for every non-protected column
col_nuniq <- vapply(
  setdiff(names(df), PROTECTED),
  function(nm) length(unique(df[[nm]][!is.na(df[[nm]])])),
  integer(1L)
)

continuous_cols  <- names(col_nuniq)[col_nuniq >  N_UNIQUE_THRESH]
categorical_cols <- names(col_nuniq)[col_nuniq <= N_UNIQUE_THRESH]

# ---- 3. Drop continuous columns with any NA ----------------------------------

cont_any_na <- continuous_cols[
  vapply(continuous_cols, function(nm) anyNA(df[[nm]]), logical(1L))
]

if (length(cont_any_na)) {
  df <- df[, setdiff(names(df), cont_any_na), drop = FALSE]
  message("Dropped ", length(cont_any_na),
          " continuous column(s) with any NA (no imputation).")
}

# Refresh the kept continuous list
continuous_kept <- setdiff(continuous_cols, cont_any_na)
message("  Continuous columns kept (zero NA): ", length(continuous_kept))

# ---- 4. Add log(1 + TOTEXP) --------------------------------------------------

if (!"TOTEXP" %in% names(df)) stop("TOTEXP column missing — check 01_clean-data.R output.")
df$TOTEXP_LOG1P <- log1p(as.numeric(df$TOTEXP))
message("Added TOTEXP_LOG1P = log1p(TOTEXP).")

# ---- 5. One-hot encode nominal variables -------------------------------------

nominal_list <- meps_nominal_vars()
nominal_present <- intersect(nominal_list, categorical_cols)  # only those in data

if (length(nominal_present)) {
  message("One-hot encoding ", length(nominal_present), " nominal variable(s) ...")
  dummy_frames <- vector("list", length(nominal_present))

  for (i in seq_along(nominal_present)) {
    nm <- nominal_present[i]
    x  <- recode_na_to_new_level(df[[nm]])

    # Build model matrix: one column per level, then drop the first (reference).
    # Suppress the "(Intercept)" column and use explicit factor levels for safety.
    lvls <- sort(unique(x))
    fx   <- factor(x, levels = lvls)
    mm   <- model.matrix(~ fx - 1)
    colnames(mm) <- paste0(nm, "_", lvls)
    # Drop the first level (reference category) to avoid perfect collinearity.
    mm <- mm[, -1L, drop = FALSE]

    dummy_frames[[i]] <- as.data.frame(mm, check.names = FALSE)
    message("  ", nm, ": ", length(lvls), " levels -> ",
            ncol(mm), " dummy column(s) (reference dropped)")
  }

  # Remove original nominal columns; append all dummy frames at once.
  df <- df[, setdiff(names(df), nominal_present), drop = FALSE]
  df <- cbind(df, do.call(cbind, dummy_frames))
  total_dummies <- sum(vapply(dummy_frames, ncol, integer(1L)))
  message("  Total dummy columns added: ", total_dummies)
} else {
  message("No nominal variables found in dataset (all may be absent after exclusions).")
}

# ---- 6. Recode NA in remaining categorical columns ---------------------------

# Refresh categorical list: exclude nominal vars (already removed) and protected cols
remaining_cat <- intersect(categorical_cols, names(df))
remaining_cat <- setdiff(remaining_cat, PROTECTED)

cat_with_na <- remaining_cat[
  vapply(remaining_cat, function(nm) anyNA(df[[nm]]), logical(1L))
]

if (length(cat_with_na)) {
  for (nm in cat_with_na) {
    df[[nm]] <- recode_na_to_new_level(df[[nm]])
  }
  message("Recoded NA to max+1 in ", length(cat_with_na),
          " non-nominal categorical column(s) (NA is now a distinct integer level).")
}

# Verify no NA remains (outside protected columns which may legitimately be NA
# only if TOTEXP_LOG1P could be NA — it cannot since TOTEXP has no NA).
all_preds <- setdiff(names(df), PROTECTED)
na_remaining <- all_preds[vapply(all_preds, function(nm) anyNA(df[[nm]]), logical(1L))]
if (length(na_remaining)) {
  warning("Unexpected NA remaining in ", length(na_remaining), " column(s): ",
          paste(head(na_remaining, 10), collapse = ", "))
}

# ---- 7. Drop zero-variance columns -------------------------------------------

num_mask <- vapply(df, is.numeric, logical(1L))
vars_num  <- vapply(df[num_mask], var, numeric(1L), na.rm = TRUE)
zv_cols   <- names(vars_num)[vars_num == 0 | is.na(vars_num)]
zv_cols   <- setdiff(zv_cols, PROTECTED)
if (length(zv_cols)) {
  df <- df[, setdiff(names(df), zv_cols), drop = FALSE]
  message("Dropped ", length(zv_cols), " zero-variance column(s).")
}

# ---- 8. Write output ---------------------------------------------------------

arrow::write_parquet(df, out_path)

pred_count <- length(setdiff(names(df), PROTECTED))
message("\nDone. Wrote ", out_path)
message("  Rows:              ", nrow(df))
message("  Total columns:     ", ncol(df))
message("  Predictor columns: ", pred_count,
        "  (excludes TOTEXP, TOTEXP_LOG1P, FYC_YEAR)")
message("  NA remaining:      ", length(na_remaining))
