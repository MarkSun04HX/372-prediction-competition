#!/usr/bin/env Rscript
# Stack yearly modeling Parquets; harmonize names; add FYC_YEAR; target -> TOTEXP.

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("install.packages('dplyr')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
setwd(root)

source(file.path(root, "R", "meps_competition_exclusions.R"))

year_map <- data.frame(
  calendar_year = c(2019, 2020, 2021, 2022, 2023),
  yy = c("19", "20", "21", "22", "23"),
  fname = sprintf("meps_fyc_%s_for_modeling.parquet", c(2019, 2020, 2021, 2022, 2023)),
  stringsAsFactors = FALSE
)

proc_dir <- file.path(root, "data", "processed")
parts <- vector("list", nrow(year_map))
meta <- vector("list", nrow(year_map))

for (i in seq_len(nrow(year_map))) {
  path <- file.path(proc_dir, year_map$fname[i])
  if (!file.exists(path)) stop("Missing ", path, " — run process_meps_for_modeling.R first.")
  df <- arrow::read_parquet(path, as_data_frame = TRUE)
  yy <- year_map$yy[i]
  tgt <- paste0("TOTEXP", yy)
  if (!tgt %in% names(df)) stop("Missing ", tgt)

  df <- meps_harmonize_names(df, yy)
  if (!"TOTEXP" %in% names(df)) stop("Harmonized file missing TOTEXP")

  df$FYC_YEAR <- year_map$calendar_year[i]
  df <- df[, c("FYC_YEAR", setdiff(names(df), "FYC_YEAR"))]
  parts[[i]] <- df
  meta[[i]] <- list(
    FYC_YEAR = year_map$calendar_year[i],
    yy = yy,
    source_parquet = file.path("data", "processed", year_map$fname[i]),
    n_rows = nrow(df),
    n_columns = ncol(df)
  )
}

pooled <- dplyr::bind_rows(parts)
out_path <- file.path(proc_dir, "meps_fyc_2019_2023_pooled_for_modeling.parquet")
arrow::write_parquet(pooled, out_path)
message("Wrote ", out_path, " (", nrow(pooled), " x ", ncol(pooled), ")")

pool_manifest <- list(
  pooled_parquet = file.path("data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet"),
  n_rows = nrow(pooled),
  n_columns = ncol(pooled),
  target_column = "TOTEXP",
  year_indicator_column = "FYC_YEAR",
  sources = meta
)
jsonlite::write_json(
  pool_manifest,
  file.path(proc_dir, "pooling_manifest.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
message("Wrote pooling_manifest.json")
