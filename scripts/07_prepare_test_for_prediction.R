#!/usr/bin/env Rscript
# 07_prepare_test_for_prediction.R
#
# Prepare `test.xlsx` using the same transformation logic as training:
#   - 01_clean-data.R style: sentinel recode, drop IDs/strings, harmonize names
#   - 03_process-data.R style: one-hot nominal variables, recode categorical NA
#     levels, drop zero-variance columns, add TOTEXP_LOG1P
#
# Usage:
#   Rscript scripts/07_prepare_test_for_prediction.R
#
# Env vars:
#   TEST_XLSX      input xlsx path (default: test.xlsx)
#   OUT_PARQUET    output parquet path
#                  (default: data/processed/test_for_prediction_processed.parquet)
#   OUT_CSV        output csv path
#                  (default: data/processed/test_for_prediction_processed.csv)
#   FORCE_YEAR_YY  optional year suffix for harmonization: 19|20|21|22|23

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

  if (!is.null(script_path)) {
    parent <- normalizePath(file.path(dirname(script_path), ".."),
                            winslash = "/", mustWork = TRUE)
    if (file.exists(file.path(parent, "src", "exclude_variables.R"))) return(parent)
  }

  d <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  for (kk in seq_len(12L)) {
    if (file.exists(file.path(d, "src", "exclude_variables.R"))) return(d)
    nd <- dirname(d)
    if (identical(nd, d)) break
    d <- nd
  }
  stop("Cannot resolve repo root (need src/exclude_variables.R).")
}

root <- resolve_repo_root()
source(file.path(root, "src", "exclude_variables.R"))

TEST_XLSX <- Sys.getenv("TEST_XLSX", unset = file.path(root, "test.xlsx"))
OUT_PARQUET <- Sys.getenv(
  "OUT_PARQUET",
  unset = file.path(root, "data", "processed", "test_for_prediction_processed.parquet")
)
OUT_CSV <- Sys.getenv(
  "OUT_CSV",
  unset = file.path(root, "data", "processed", "test_for_prediction_processed.csv")
)
FORCE_YEAR_YY <- Sys.getenv("FORCE_YEAR_YY", unset = "")
N_UNIQUE_THRESH <- as.integer(Sys.getenv("N_UNIQUE_THRESH", unset = "20"))

if (!file.exists(TEST_XLSX)) stop("Input file not found: ", TEST_XLSX)

manifest_path <- file.path(dirname(OUT_PARQUET), "test_for_prediction_manifest.json")
manifest_yy <- NA_character_
if (!nzchar(FORCE_YEAR_YY) && file.exists(manifest_path) &&
    requireNamespace("jsonlite", quietly = TRUE)) {
  man <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  manifest_yy <- as.character(man$harmonize_year_suffix_used)
}

yy <- FORCE_YEAR_YY
if (!nzchar(yy) && !is.na(manifest_yy) && nzchar(manifest_yy)) yy <- manifest_yy
if (!nzchar(yy)) yy <- "19"
year_val <- as.integer(paste0("20", yy))

message("Using harmonization yy=", yy, " (FYC_YEAR=", year_val, ")")

df <- as.data.frame(read_excel(TEST_XLSX))
orig_ncols <- ncol(df)

if (!("TOTEXP" %in% names(df))) {
  warning("TOTEXP not found in test.xlsx. Creating TOTEXP=NA.")
  df$TOTEXP <- NA_real_
}

# ---- 01-style steps ---------------------------------------------------------
exclusions <- meps_expanded_exclusion_names()
df <- meps_recode_sentinels(df)
df[] <- lapply(df, function(x) {
  if (inherits(x, "labelled")) as.numeric(haven::zap_labels(x)) else x
})
df <- df[, setdiff(names(df), c("DUID", "PID")), drop = FALSE]

char_cols <- names(df)[vapply(df, is.character, logical(1L))]
if (length(char_cols)) df <- df[, setdiff(names(df), char_cols), drop = FALSE]

to_drop <- setdiff(intersect(names(df), exclusions), "TOTEXP")
if (length(to_drop)) df <- df[, setdiff(names(df), to_drop), drop = FALSE]

df <- meps_harmonize_names(df, yy)
if (anyDuplicated(names(df))) df <- df[, !duplicated(names(df)), drop = FALSE]
df$FYC_YEAR <- year_val

# ---- 03-style steps ---------------------------------------------------------
PROTECTED <- c("TOTEXP", "TOTEXP_LOG1P", "FYC_YEAR")
col_nuniq <- vapply(
  setdiff(names(df), PROTECTED),
  function(nm) length(unique(df[[nm]][!is.na(df[[nm]])])),
  integer(1L)
)
continuous_cols <- names(col_nuniq)[col_nuniq > N_UNIQUE_THRESH]
categorical_cols <- names(col_nuniq)[col_nuniq <= N_UNIQUE_THRESH]

cont_any_na <- continuous_cols[vapply(continuous_cols, function(nm) anyNA(df[[nm]]), logical(1L))]
if (length(cont_any_na)) df <- df[, setdiff(names(df), cont_any_na), drop = FALSE]

df$TOTEXP_LOG1P <- log1p(as.numeric(df$TOTEXP))

recode_na_to_new_level <- function(x) {
  if (!anyNA(x)) return(x)
  new_level <- max(x, na.rm = TRUE) + 1L
  x[is.na(x)] <- new_level
  x
}

nominal_present <- intersect(meps_nominal_vars(), categorical_cols)
if (length(nominal_present)) {
  dummy_frames <- list()
  for (nm in nominal_present) {
    x <- recode_na_to_new_level(df[[nm]])
    lvls <- sort(unique(x))
    if (length(lvls) < 2L) next
    fx <- factor(x, levels = lvls)
    mm <- model.matrix(~ fx - 1)
    colnames(mm) <- paste0(nm, "_", lvls)
    mm <- mm[, -1L, drop = FALSE]
    dummy_frames[[nm]] <- as.data.frame(mm, check.names = FALSE)
  }
  df <- df[, setdiff(names(df), nominal_present), drop = FALSE]
  if (length(dummy_frames)) df <- cbind(df, do.call(cbind, dummy_frames))
}

remaining_cat <- intersect(categorical_cols, names(df))
remaining_cat <- setdiff(remaining_cat, c(PROTECTED, nominal_present))
cat_with_na <- remaining_cat[vapply(remaining_cat, function(nm) anyNA(df[[nm]]), logical(1L))]
if (length(cat_with_na)) {
  for (nm in cat_with_na) df[[nm]] <- recode_na_to_new_level(df[[nm]])
}

num_mask <- vapply(df, is.numeric, logical(1L))
vars_num <- vapply(df[num_mask], var, numeric(1L), na.rm = TRUE)
zv_cols <- setdiff(names(vars_num)[vars_num == 0 | is.na(vars_num)], PROTECTED)
if (length(zv_cols)) df <- df[, setdiff(names(df), zv_cols), drop = FALSE]

dir.create(dirname(OUT_PARQUET), recursive = TRUE, showWarnings = FALSE)
write_parquet(df, OUT_PARQUET)
write.csv(df, OUT_CSV, row.names = FALSE)

manifest <- list(
  input_file = normalizePath(TEST_XLSX, winslash = "/", mustWork = TRUE),
  output_parquet = normalizePath(OUT_PARQUET, winslash = "/", mustWork = FALSE),
  output_csv = normalizePath(OUT_CSV, winslash = "/", mustWork = FALSE),
  harmonize_year_suffix_used = yy,
  input_columns = orig_ncols,
  output_columns = ncol(df),
  rows = nrow(df),
  processing = "01_clean + 03_process style"
)
if (requireNamespace("jsonlite", quietly = TRUE)) {
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)
}

message("\nDone.")
message("  Input columns: ", orig_ncols)
message("  Output columns: ", ncol(df))
message("  Rows: ", nrow(df))
message("  Wrote: ", OUT_PARQUET)
message("  Wrote: ", OUT_CSV)
if (file.exists(manifest_path)) message("  Wrote: ", manifest_path)
