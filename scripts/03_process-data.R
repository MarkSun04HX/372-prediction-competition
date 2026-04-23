#!/usr/bin/env Rscript
# 03_process-data.R
# Read pooled modeling Parquet from 01_clean-data.R; add log(1+TOTEXP) column
# for downstream training while keeping dollar-scale TOTEXP for RMSLE/submission.
#
# Usage (from repo root):
#   Rscript scripts/03_process-data.R

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("haven", quietly = TRUE)) stop("install.packages('haven')")
})

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
setwd(root)

in_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
if (!file.exists(in_path)) stop("Missing pooled file — run scripts/01_clean-data.R first:\n  ", in_path)

out_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling_processed.parquet")

message("Reading ", in_path, " ...")
df <- arrow::read_parquet(in_path, as_data_frame = TRUE)

if (!"TOTEXP" %in% names(df)) stop("Column TOTEXP not found.")

tot <- df$TOTEXP
if (inherits(tot, "labelled")) {
  tot <- as.numeric(haven::zap_labels(tot))
} else {
  tot <- as.numeric(tot)
}

if ("TOTEXP_LOG1P" %in% names(df)) {
  message("Column TOTEXP_LOG1P already present — overwriting with log1p(TOTEXP).")
}

df$TOTEXP_LOG1P <- log1p(tot)

# ---- Drop all character columns (IDs and any other non-numeric strings) ----

char_cols <- names(df)[vapply(df, is.character, logical(1L))]
if (length(char_cols)) {
  df <- df[, setdiff(names(df), char_cols), drop = FALSE]
  message("Dropped ", length(char_cols), " character columns: ", paste(char_cols, collapse = ", "))
}

# ---- Drop zero-variance numeric columns (constant across full pooled dataset) ----

num_mask <- vapply(df, is.numeric, logical(1L))
num_vars <- vapply(df[num_mask], var, numeric(1L), na.rm = TRUE)
zv_cols  <- names(num_vars)[num_vars == 0 | is.na(num_vars)]
if (length(zv_cols)) {
  df <- df[, setdiff(names(df), zv_cols), drop = FALSE]
  message("Dropped ", length(zv_cols), " zero-variance columns: ", paste(zv_cols, collapse = ", "))
}

arrow::write_parquet(df, out_path)

message("\nDone. Wrote ", out_path)
message("  Rows:    ", nrow(df))
message("  Columns: ", ncol(df))
message("  Added:   TOTEXP_LOG1P (= log1p(TOTEXP)); TOTEXP unchanged (dollars).")
