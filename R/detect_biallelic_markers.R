# Detect if markers are biallelic

#' @name detect_biallelic_markers

#' @title Detect biallelic data

#' @description Detect if markers in tidy dataset are biallelic.
#' Used internally in \href{https://github.com/thierrygosselin/radiator}{radiator}
#' and might be of interest for users.

#' @param data A tidy data frame object in the global environment or
#' a tidy data frame in wide or long format in the working directory.
#' \emph{How to get a tidy data frame ?}
#' Look into \pkg{radiator} \code{\link{tidy_genomic_data}}.

#' @param verbose (optional, logical) \code{verbose = TRUE} to be chatty
#' during execution.
#' Default: \code{verbose = FALSE}.

#' @return A logical character string (TRUE/FALSE). That answer the question if
#' the data set is biallelic or not.

#' @export
#' @rdname detect_biallelic_markers
#' @importFrom dplyr select mutate group_by ungroup rename tally filter
#' @importFrom stringi stri_replace_all_fixed stri_sub
#' @importFrom tibble has_name
#' @importFrom tidyr gather
#' @importFrom purrr flatten_chr

#' @author Thierry Gosselin \email{thierrygosselin@@icloud.com}

detect_biallelic_markers <- function(data, verbose = FALSE) {

  # Checking for missing and/or default arguments ------------------------------
  if (missing(data)) stop("Input file missing")

  # Import data ---------------------------------------------------------------
  if (is.vector(data)) {
    data <- radiator::tidy_wide(data = data, import.metadata = TRUE)
  }

  if (tibble::has_name(data, "GT_BIN")) {
    biallelic <- TRUE
    if (verbose) message("    Data is bi-allelic")
  } else {
    # necessary steps to make sure we work with unique markers and not duplicated LOCUS
    if (tibble::has_name(data, "LOCUS") && !tibble::has_name(data, "MARKERS")) {
      data <- dplyr::rename(.data = data, MARKERS = LOCUS)
    }

    # markers with all missing... yes I've seen it... breaks code...
    # data <- detect_all_missing(data = data)
    marker.problem <- radiator::detect_all_missing(data = data)
    if (marker.problem$marker.problem) {
      data <- marker.problem$data
    }
    marker.problem <- NULL

    # Detecting biallelic markers-------------------------------------------------
    if (verbose) message("Scanning for number of alleles per marker...")
    if (tibble::has_name(data, "ALT")) {
      alt.num <- max(unique(
        stringi::stri_count_fixed(str = unique(data$ALT), pattern = ","))) + 1

      if (alt.num > 1) {
        biallelic <- FALSE
        if (verbose) message("    Data is multi-allelic")
      } else {
        biallelic <- TRUE
        if (verbose) message("    Data is bi-allelic")
      }
      alt.num <- NULL
    } else {
      # If there are less than 100 markers, sample all of them
      sampled.markers <- unique(data$MARKERS)
      n.markers <- length(sampled.markers)
      if (n.markers < 100) {
        small.panel <- TRUE
      } else {
        # otherwise 30% of the markers are randomly sampled
        small.panel <- FALSE
        sampled.markers <- sample(x = sampled.markers,
                                  size = length(sampled.markers) * 0.30,
                                  replace = FALSE)
      }

      biallelic <- dplyr::select(.data = data, MARKERS, GT) %>%
        dplyr::filter(GT != "000000") %>%
        dplyr::filter(MARKERS %in% sampled.markers) %>%
        dplyr::distinct(MARKERS, GT) %>%
        dplyr::mutate(A1 = stringi::stri_sub(GT, 1, 3), A2 = stringi::stri_sub(GT, 4,6)) %>%
        dplyr::select(-GT) %>%
        tidyr::gather(data = ., key = ALLELES_GROUP, value = ALLELES, -MARKERS) %>%
        dplyr::distinct(MARKERS, ALLELES) %>%
        dplyr::count(x = ., MARKERS) %>%
        dplyr::select(n)

      if (small.panel) {
        n.allele <- dplyr::filter(biallelic, n > 2)
        if (nrow(n.allele) == n.markers) {
          biallelic <- FALSE
          if (verbose) message("    Data is multi-allelic")
        } else {
          biallelic <- TRUE
          if (verbose) message("    Data is bi-allelic")
        }
      } else {
        biallelic <- max(biallelic$n)
        if (biallelic > 4) {
          biallelic <- FALSE
          if (verbose) message("    Data is multi-allelic")
        } else {
          biallelic <- TRUE
          if (verbose) message("    Data is bi-allelic")
        }
      }
    }
  }
    return(biallelic)
  } # End detect_biallelic_markers
