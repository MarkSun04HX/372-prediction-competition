# ECN372 competition exclusions (MEPS Section 2.5.11 + survey design).
# Canonical R implementation; source this file from R scripts.

meps_default_yy <- function() c("19", "20", "21", "22", "23")

meps_excluded_stems_yy <- function() {
  c(
    "TOTTCH", "TOTEXP", "TOTSLF", "TOTMCR", "TOTMCD", "TOTPRV", "TOTVA", "TOTTRI",
    "TOTOFD", "TOTSTL", "TOTWCP", "TOTOPR", "TOTOPU", "TOTOSR",
    "OBTOTV", "OBDRV", "OBOTHV", "OBCHIR", "OBNURS", "OBOPTO", "OBASST", "OBTHER",
    "OBVTCH", "OBVEXP", "OBVSLF", "OBVMCR", "OBVMCD", "OBVPRV", "OBVVA", "OBVTRI",
    "OBVOFD", "OBVSTL", "OBVWCP", "OBVOPR", "OBVOPU", "OBVOSR",
    "OPTOTV", "OPDRV", "OPOTHV", "AMCHIR", "AMNURS", "AMOPT", "AMASST", "AMTHER",
    "OPFTCH", "OPFEXP", "OPFSLF", "OPFMCR", "OPFMCD", "OPFPRV", "OPFVA", "OPFTRI",
    "OPFOFD", "OPFSTL", "OPFWCP", "OPFOPR", "OPFOPU", "OPFOSR",
    "OPDTCH", "OPDEXP", "OPDSLF", "OPDMCR", "OPDMCD", "OPDPRV", "OPDVA", "OPDTRI",
    "OPDOFD", "OPDSTL", "OPDWCP", "OPDOPR", "OPDOPU", "OPDOSR",
    "OPVTCH", "OPVEXP", "OPVSLF", "OPVMCR", "OPVMCD", "OPVPRV", "OPVVA", "OPVTRI",
    "OPVOFD", "OPVSTL", "OPVWCP", "OPVOPR", "OPVOPU", "OPVOSR",
    "ERTOT", "ERFTCH", "ERFEXP", "ERFSLF", "ERFMCR", "ERFMCD", "ERFPRV", "ERFVA",
    "ERFTRI", "ERFOFD", "ERFSTL", "ERFWCP", "ERFOPR", "ERFOPU", "ERFOSR",
    "ERDTCH", "ERDEXP", "ERDSLF", "ERDMCR", "ERDMCD", "ERDPRV", "ERDVA", "ERDTRI",
    "ERDOFD", "ERDSTL", "ERDWCP", "ERDOPR", "ERDOPU", "ERDOSR",
    "ERVTCH", "ERVEXP", "ERVSLF", "ERVMCR", "ERVMCD", "ERVPRV", "ERVVA", "ERVTRI",
    "ERVOFD", "ERVSTL", "ERVWCP", "ERVOPR", "ERVOPU", "ERVOSR",
    "IPDIS", "IPNGTD", "IPZERO", "IPFTCH", "IPFEXP", "IPFSLF", "IPFMCR", "IPFMCD",
    "IPFPRV", "IPFVA", "IPFTRI", "IPFOFD", "IPFSTL", "IPFWCP", "IPFOPR", "IPFOPU",
    "IPFOSR", "IPDTCH", "IPDEXP", "IPDSLF", "IPDMCR", "IPDMCD", "IPDPRV", "IPDVA",
    "IPDTRI", "IPDOFD", "IPDSTL", "IPDWCP", "IPDOPR", "IPDOPU", "IPDOSR",
    "DVTOT", "DVGEN", "DVORTH", "DVVTCH", "DVVEXP", "DVVSLF", "DVVMCR", "DVVMCD",
    "DVVPRV", "DVVVA", "DVVTRI", "DVVOFD", "DVVSTL", "DVVWCP", "DVVOPR", "DVVOPU",
    "DVVOSR",
    "HHTOTD", "HHAGD", "HHINDD", "HHINFD", "HHATCH", "HHAEXP", "HHASLF", "HHAMCR",
    "HHAMCD", "HHAPRV", "HHAVA", "HHATRI", "HHAOFD", "HHASTL", "HHAWCP", "HHAOPR",
    "HHAOPU", "HHAOSR", "HHNTCH", "HHNEXP", "HHNSLF", "HHNMCR", "HHNMCD", "HHNPRV",
    "HHNVA", "HHNTRI", "HHNOFD", "HHNSTL", "HHNWCP", "HHNOPR", "HHNOPU", "HHNOSR",
    "OMETCH", "OMEEXP", "OMESLF", "OMEMCR", "OMEMCD", "OMEPRV", "OMEVA", "OMETRI",
    "OMEOFD", "OMESTL", "OMEWCP", "OMEOPR", "OMEOPU", "OMEOSR",
    "RXTOT", "RXEXP", "RXSLF", "RXMCR", "RXMCD", "RXPRV", "RXVA", "RXTRI", "RXOFD",
    "RXSTL", "RXWCP", "RXOPR", "RXOPU", "RXOSR"
  )
}

meps_brr_names <- function() sprintf("BRR%d", 1:128)

#' All physical column names to drop as predictors (for yy in 19..23).
meps_expanded_exclusion_names <- function(yy = meps_default_yy()) {
  stems <- meps_excluded_stems_yy()
  out <- c("VARSTR", "VARPSU", meps_brr_names())
  for (suf in yy) {
    out <- c(out, paste0("PERWT", suf, "F"))
    out <- c(out, paste0(stems, suf))
  }
  unique(out)
}

meps_survey_design_present <- function(nm) {
  exc <- intersect(nm, c("VARSTR", "VARPSU", meps_brr_names()))
  perwt <- grep("^PERWT[0-9]{2}F$", nm, value = TRUE)
  sort(unique(c(exc, perwt)))
}

meps_harmonize_names <- function(df, yy) {
  old <- names(df)
  new <- ifelse(
    endsWith(old, yy) & nchar(old) > nchar(yy),
    substring(old, 1L, nchar(old) - nchar(yy)),
    old
  )
  if (any(duplicated(new))) {
    dups <- new[duplicated(new) | duplicated(new, fromLast = TRUE)]
    stop("Harmonization produced duplicate names: ", paste(unique(head(dups, 20)), collapse = ", "))
  }
  names(df) <- new
  df
}
