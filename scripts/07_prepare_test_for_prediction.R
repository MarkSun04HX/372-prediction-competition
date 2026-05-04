#!/usr/bin/env Rscript
# 07_prepare_test_for_prediction.R
# Prepare test.xlsx into a harmonized, model-input-like table.
#
# Priority for feature reference (in order):
#   1) data/processed/meps_fyc_2019_2023_pooled_for_modeling_processed.parquet
#      -> exact predictor columns used by model training (best option)
#   2) Union of harmonized columns derived from raw 2019-2023 files after
#      01_clean-data.R style exclusion + ID dropping
#      -> useful fallback when processed parquet does not exist yet
#
# Usage:
#   Rscript scripts/07_prepare_test_for_prediction.R
#
# Env vars:
#   TEST_XLSX      input xlsx path (default: test.xlsx)
#   OUT_PARQUET    output parquet path
#                  (default: data/processed/test_for_prediction.parquet)
#   OUT_CSV        optional output csv path
#                  (default: data/processed/test_for_prediction.csv)
#   FORCE_YEAR_YY  optional year suffix for harmonization: 19|20|21|22|23
#                  If unset, script tries all and picks the best match.

suppressPackageStartupMessages({
  library(arrow)
  library(haven)
  library(readxl)
})

resolve_repo_root <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  file_flags <- grep("^--file=", cmd, value = TRUE)

  script_path <- NULL
  if (length(file_flags)) {
    cand <- normalizePath(sub("^--file=", "", file_flags[length(file_flags)]),
                          winslash = "/", mustWork = FALSE)
    if (!anyNA(cand) && nzchar(cand) && cand != "-" && file.exists(cand))
      script_path <- cand
  }

  from_script_parent <- NULL
  if (!is.null(script_path)) {
    from_script_parent <- normalizePath(file.path(dirname(script_path), ".."),
                                        winslash = "/", mustWork = TRUE)
    if (file.exists(file.path(from_script_parent, "src", "exclude_variables.R")))
      return(from_script_parent)
  }

  d <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  for (kk in seq_len(12L)) {
    if (file.exists(file.path(d, "src", "exclude_variables.R"))) {
      return(normalizePath(d, winslash = "/", mustWork = TRUE))
    }
    nd <- dirname(d)
    if (identical(nd, d))
      break
    d <- nd
  }

  stop(
    "Cannot resolve repo root (need src/exclude_variables.R).\n",
    "Run from repo root:\n",
    "  Rscript scripts/07_prepare_test_for_prediction.R\n",
    "Or set working directory so an ancestor folder contains ", encodeString("src/exclude_variables.R"), "."
  )
}

root <- resolve_repo_root()
source(file.path(root, "src", "exclude_variables.R"))

TEST_XLSX <- Sys.getenv("TEST_XLSX", unset = file.path(root, "test.xlsx"))
OUT_PARQUET <- Sys.getenv(
  "OUT_PARQUET",
  unset = file.path(root, "data", "processed", "test_for_prediction.parquet")
)
OUT_CSV <- Sys.getenv(
  "OUT_CSV",
  unset = file.path(root, "data", "processed", "test_for_prediction.csv")
)
FORCE_YEAR_YY <- Sys.getenv("FORCE_YEAR_YY", unset = "")

if (!file.exists(TEST_XLSX))
  stop("Input file not found: ", TEST_XLSX)

year_map <- data.frame(
  year = c(2019L, 2020L, 2021L, 2022L, 2023L),
  yy   = c("19", "20", "21", "22", "23"),
  file = c("h216.dta", "h224.dta", "h233.dta", "h243.dta", "h251.dta"),
  stringsAsFactors = FALSE
)

build_harmonized_union <- function(root_dir, ym) {
  exclusions <- meps_expanded_exclusion_names()
  out <- character(0)
  for (i in seq_len(nrow(ym))) {
    yy <- ym$yy[i]
    path <- file.path(root_dir, "data", "raw", ym$file[i])
    if (!file.exists(path)) next
    df <- as.data.frame(read_dta(path))

    target_name <- paste0("TOTEXP", yy)
    to_drop <- setdiff(intersect(names(df), exclusions), target_name)
    df <- df[, setdiff(names(df), to_drop), drop = FALSE]
    df <- df[, setdiff(names(df), c("DUID", "PID", "DUPERSID")), drop = FALSE]
    df <- meps_harmonize_names(df, yy)

    out <- union(out, names(df))
  }
  out
}

processed_path <- file.path(
  root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling_processed.parquet"
)

if (file.exists(processed_path)) {
  ref_cols <- names(read_parquet(processed_path, as_data_frame = TRUE))
  protected <- c("TOTEXP", "TOTEXP_LOG1P", "FYC_YEAR")
  ref_predictors <- setdiff(ref_cols, protected)
  ref_type <- "processed_predictor_schema"
  message("Reference features: processed predictor schema (", length(ref_predictors), " columns)")
} else {
  ref_predictors <- setdiff(build_harmonized_union(root, year_map), "TOTEXP")
  ref_type <- "harmonized_union_fallback"
  message("Reference features: harmonized union fallback (", length(ref_predictors), " columns)")
}

# Ensure person identifiers are not part of prediction features.
ref_predictors <- setdiff(ref_predictors, c("DUID", "PID", "DUPERSID"))

if (!length(ref_predictors))
  stop("Could not build reference feature set.")

test_df <- as.data.frame(read_excel(TEST_XLSX))
orig_names <- names(test_df)

if (!nzchar(FORCE_YEAR_YY)) {
  candidates <- year_map$yy
} else {
  if (!FORCE_YEAR_YY %in% year_map$yy)
    stop("FORCE_YEAR_YY must be one of: ", paste(year_map$yy, collapse = ", "))
  candidates <- FORCE_YEAR_YY
}

best <- list(yy = NA_character_, n_match = -1L, names = orig_names)
for (yy in candidates) {
  tmp <- test_df
  tmp <- meps_harmonize_names(tmp, yy)
  nm <- names(tmp)
  n_match <- sum(nm %in% ref_predictors)
  if (n_match > best$n_match) {
    best$yy <- yy
    best$n_match <- n_match
    best$names <- nm
  }
}

names(test_df) <- best$names

# Keep first occurrence if harmonization causes accidental duplicates.
if (anyDuplicated(names(test_df))) {
  keep <- !duplicated(names(test_df))
  test_df <- test_df[, keep, drop = FALSE]
}

match_mask <- names(test_df) %in% ref_predictors
matched_cols <- names(test_df)[match_mask]
missing_cols <- setdiff(ref_predictors, matched_cols)
extra_cols <- setdiff(names(test_df), ref_predictors)

pred_df <- test_df[, intersect(ref_predictors, names(test_df)), drop = FALSE]
if (length(missing_cols)) {
  for (nm in missing_cols) pred_df[[nm]] <- NA
}
pred_df <- pred_df[, ref_predictors, drop = FALSE]

dir.create(dirname(OUT_PARQUET), recursive = TRUE, showWarnings = FALSE)
write_parquet(pred_df, OUT_PARQUET)
write.csv(pred_df, OUT_CSV, row.names = FALSE)

manifest <- list(
  input_file = normalizePath(TEST_XLSX, winslash = "/", mustWork = TRUE),
  output_parquet = normalizePath(OUT_PARQUET, winslash = "/", mustWork = FALSE),
  output_csv = normalizePath(OUT_CSV, winslash = "/", mustWork = FALSE),
  harmonize_year_suffix_used = best$yy,
  reference_type = ref_type,
  input_columns = length(orig_names),
  matched_columns = length(matched_cols),
  unmatched_input_columns = length(extra_cols),
  missing_reference_columns_filled_na = length(missing_cols),
  output_columns = ncol(pred_df)
)

manifest_path <- file.path(dirname(OUT_PARQUET), "test_for_prediction_manifest.json")
jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)

message("\nDone.")
message("  Input columns:                ", length(orig_names))
message("  Matched reference columns:    ", length(matched_cols))
message("  Unmatched input columns:      ", length(extra_cols))
message("  Missing ref cols filled with NA: ", length(missing_cols))
message("  Harmonize suffix selected:    ", best$yy)
message("  Wrote: ", OUT_PARQUET)
message("  Wrote: ", OUT_CSV)
message("  Wrote: ", manifest_path)
