#!/usr/bin/env Rscript
# Write config/excluded_columns_expanded.txt (one name per line).

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
setwd(root)
source(file.path(root, "R", "meps_competition_exclusions.R"))

out_path <- file.path(root, "config", "excluded_columns_expanded.txt")
lines <- sort(meps_expanded_exclusion_names())
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
con <- file(out_path, open = "wt", encoding = "UTF-8")
writeLines(
  c(
    "# Expanded competition-excluded MEPS-style names (physical PUF columns).",
    "# Includes PERWTyyF, VARSTR, VARPSU, BRR1..BRR128, Section 2.5.11 stems + yy.",
    ""
  ),
  con
)
writeLines(lines, con)
close(con)
message("Wrote ", out_path, " (", length(lines), " names)")
