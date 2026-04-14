#!/usr/bin/env Rscript
# 01_clean-data.R
# Read raw MEPS Stata files (2019-2023), drop excluded variables,
# harmonize column names across years, pool into one dataset,
# and write a single Parquet file for modeling.
#
# Usage (from repo root):
#   Rscript scripts/01_clean-data.R

library(haven)
library(arrow)
library(dplyr)

# ---- Resolve repo root & source helpers ------------------------------------

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "src", "exclusion_helpers.R"))

# ---- Year-to-file mapping -------------------------------------------------

year_map <- data.frame(
  year = c(2019L, 2020L, 2021L, 2022L, 2023L),
  yy   = c("19",  "20",  "21",  "22",  "23"),
  file = c("h216.dta", "h224.dta", "h233.dta", "h243.dta", "h251.dta"),
  stringsAsFactors = FALSE
)

# ---- Build exclusion list --------------------------------------------------

exclusions <- meps_expanded_exclusion_names()

# ---- Read, clean, and harmonize each year ----------------------------------

parts <- vector("list", nrow(year_map))

for (i in seq_len(nrow(year_map))) {
  yr   <- year_map$year[i]
  yy   <- year_map$yy[i]
  path <- file.path(root, "data", "raw", year_map$file[i])

  if (!file.exists(path)) stop("Missing raw file: ", path)
  message("Reading ", path, " ...")
  df <- as.data.frame(read_dta(path))

  target_name <- paste0("TOTEXP", yy)
  if (!target_name %in% names(df)) stop("Target column ", target_name, " not found in ", path)

  to_drop <- setdiff(intersect(names(df), exclusions), target_name)
  df <- df[, setdiff(names(df), to_drop), drop = FALSE]

  leaked <- meps_survey_design_present(names(df))
  if (length(leaked)) {
    stop("Survey design columns still present after dropping: ",
         paste(leaked, collapse = ", "))
  }

  df <- meps_harmonize_names(df, yy)
  if (!"TOTEXP" %in% names(df)) stop("TOTEXP missing after harmonization for year ", yr)

  df$FYC_YEAR <- yr
  df <- df[, c("FYC_YEAR", setdiff(names(df), "FYC_YEAR"))]

  message("  ", yr, ": ", nrow(df), " rows x ", ncol(df), " cols (dropped ", length(to_drop), " excluded columns)")
  parts[[i]] <- df
}

# ---- Pool all years --------------------------------------------------------

pooled <- bind_rows(parts)

# ---- Write output ----------------------------------------------------------

out_dir  <- file.path(root, "data", "processed")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_path <- file.path(out_dir, "meps_fyc_2019_2023_pooled_for_modeling.parquet")

write_parquet(pooled, out_path)

message("\nDone. Wrote ", out_path)
message("  Total rows:    ", nrow(pooled))
message("  Total columns: ", ncol(pooled))
message("  Years:         ", paste(sort(unique(pooled$FYC_YEAR)), collapse = ", "))
