#!/usr/bin/env Rscript
# Download MEPS Stata FYC zips, drop competition exclusions, keep TOTEXPyy, write Parquet.
# Usage (from repo root):  Rscript scripts/process_meps_for_modeling.R [--download]

suppressPackageStartupMessages({
  if (!requireNamespace("haven", quietly = TRUE)) stop("install.packages('haven')")
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("install.packages('dplyr')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
setwd(root)

source(file.path(root, "R", "meps_competition_exclusions.R"))

do_download <- "--download" %in% commandArgs(trailingOnly = TRUE)

year_map <- data.frame(
  calendar_year = c(2019, 2020, 2021, 2022, 2023),
  yy = c("19", "20", "21", "22", "23"),
  puf = c("h216", "h224", "h233", "h243", "h251"),
  stringsAsFactors = FALSE
)

base_url <- "https://meps.ahrq.gov/data_files/pufs/%s/%sdta.zip"

zip_dir <- file.path(root, "data", "raw", "stata_zips")
ex_dir <- file.path(root, "data", "raw", "stata")
out_dir <- file.path(root, "data", "processed")
dir.create(zip_dir, FALSE, TRUE)
dir.create(ex_dir, FALSE, TRUE)
dir.create(out_dir, FALSE, TRUE)

exc_all <- meps_expanded_exclusion_names()

rel_from_root <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  sub(paste0("^", root, "/"), "", path)
}

manifest <- vector("list", nrow(year_map))

for (i in seq_len(nrow(year_map))) {
  yr <- year_map$calendar_year[i]
  yy <- year_map$yy[i]
  puf <- year_map$puf[i]
  zipf <- file.path(zip_dir, paste0(puf, "dta.zip"))
  url <- sprintf(base_url, puf, puf)

  if (do_download || !file.exists(zipf)) {
    message("Downloading ", url)
    download.file(url, zipf, method = "libcurl", mode = "wb")
  }

  ex_sub <- file.path(ex_dir, puf)
  dir.create(ex_sub, FALSE, TRUE)
  unzip(zipf, exdir = ex_sub)
  dta <- list.files(ex_sub, pattern = "\\.dta$", ignore.case = TRUE, full.names = TRUE)
  if (!length(dta)) stop("No .dta in ", ex_sub)
  dta_path <- dta[[1]]

  message("Reading ", dta_path)
  df <- haven::read_dta(dta_path)
  df <- as.data.frame(df)

  target <- paste0("TOTEXP", yy)
  if (!target %in% names(df)) stop("Missing ", target)

  drop <- setdiff(intersect(names(df), exc_all), target)
  df <- df[, setdiff(names(df), drop), drop = FALSE]

  leaked <- meps_survey_design_present(names(df))
  if (length(leaked)) {
    stop("Survey design columns still present: ", paste(leaked, collapse = ", "))
  }

  outf <- file.path(out_dir, sprintf("meps_fyc_%s_for_modeling.parquet", yr))
  arrow::write_parquet(df, outf)

  manifest[[i]] <- list(
    calendar_year = as.character(yr),
    yy = yy,
    source_dta = rel_from_root(dta_path),
    out_parquet = rel_from_root(outf),
    n_rows = nrow(df),
    n_columns = ncol(df),
    n_columns_dropped = length(drop),
    target_column = target
  )
  message("Wrote ", outf, " (", nrow(df), " x ", ncol(df), ")")
}

jsonlite::write_json(
  manifest,
  file.path(out_dir, "processing_manifest.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
message("Wrote processing_manifest.json")
