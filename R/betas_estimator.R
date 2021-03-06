#' @name betas_estimator
#' @title Estimate \eqn{\beta}s per population
#' @description Estimate \eqn{\beta}s per population.

#' @inheritParams tidy_genomic_data

#' @param monomorphic.out (optional) Set by default to remove
#' monomorphic markers that might have avoided filters.
#' Default: \code{monomorphic.out = TRUE}.

#' @param common.markers (optional) Logical. The argument for common markers
#' between populations is set by default to keep markers in common between all populations.
#' Default: \code{common.markers = TRUE}

#' @return A list is created with 3 objects:
#' betaiovl: Average \eqn{\beta_i} over loci,
#' Hw: Within population gene diversities
#' Hb: Between populations gene diversities


#' @examples
#' \dontrun{
#' # Using a  VCF file, the simplest for of the function:
#' fh <- ibdg_fh(
#' data = "batch_1.vcf",
#' strata = "strata.panda.tsv"
#' )
#' # To see what's inside the list
#' names(fh)
#' # To view the manhattan plot:
#' fh$fh.manhattan.plot
#' # To view the distribution of FH values:
#' fh$fh.distribution.plot
#' }

#' @export
#' @rdname betas_estimator

#' @import ggplot2

#' @importFrom dplyr select distinct n_distinct group_by ungroup rename arrange tally filter if_else mutate summarise left_join inner_join right_join anti_join semi_join full_join summarise_at funs
#' @importFrom stringi stri_join stri_replace_all_fixed stri_extract_all_fixed stri_replace_all_regex stri_sub stri_pad_left stri_count_fixed stri_replace_na
#' @importFrom utils combn
#' @importFrom readr read_tsv write_tsv
#' @importFrom tibble data_frame has_name

#' @author Thierry Gosselin \email{thierrygosselin@@icloud.com}

betas_estimator <- function(
  data,
  strata = NULL,
  monomorphic.out = TRUE,
  common.markers = TRUE,
  pop.levels = NULL,
  pop.labels = NULL,
  pop.select = NULL,
  blacklist.id = NULL,
  blacklist.genotype = NULL,
  whitelist.markers = NULL,
  max.marker = NULL,
  snp.ld = NULL,
  filename = NULL,
  verbose = FALSE
) {
  if (verbose) {
    cat("#######################################################################\n")
    cat("############################ radiator::betas ############################\n")
    cat("#######################################################################\n")
    timing <- proc.time()
  }
  # manage missing arguments -----------------------------------------------------
  if (missing(data)) stop("Input file missing")
  if (!is.null(pop.levels) & is.null(pop.labels)) pop.labels <- pop.levels
  if (!is.null(pop.labels) & is.null(pop.levels)) stop("pop.levels is required if you use pop.labels")

  # import data ----------------------------------------------------------------
  # if (is.vector(data)) {
  input <- radiator::tidy_genomic_data(
    data = data,
    vcf.metadata = FALSE,
    blacklist.id = blacklist.id,
    blacklist.genotype = blacklist.genotype,
    whitelist.markers = whitelist.markers,
    monomorphic.out = monomorphic.out,
    max.marker = max.marker,
    snp.ld = snp.ld,
    common.markers = common.markers,
    strata = strata,
    pop.select = pop.select,
    filename = filename
  )

  # necessary steps to make sure we work with unique markers and not duplicated LOCUS
  if (tibble::has_name(input, "LOCUS") && !tibble::has_name(input, "MARKERS")) {
    input <- dplyr::rename(.data = input, MARKERS = LOCUS)
  }

  # population names if pop.levels/pop.labels were request
  input <- radiator::change_pop_names(data = input, pop.levels = pop.labels, pop.labels = pop.labels)

  # Detect if biallelic --------------------------------------------------------
  # biallelic <- radiator::detect_biallelic_markers(input)

  # BETAS computations ----------------------------------------------------------
  message("Beta computation ...")
  if (tibble::has_name(input, "GT_VCF")) {
    message("Warning: implementation is not working yet for haplotype vcf file")
    # option 2 using list-columns
    betas.prep <- dplyr::filter(.data = input, GT_VCF != "./.") %>%
      dplyr::group_by(MARKERS, POP_ID) %>%
      dplyr::summarise(
        N = n(),
        HOM_ALT = length(GT_VCF[GT_VCF == "1/1"]),
        HET = length(GT_VCF[GT_VCF == "1/0" | GT_VCF == "0/1"])
      ) %>%
      dplyr::mutate(
        NN = N * 2,
        FREQ_ALT = ((HOM_ALT * 2) + HET) / NN,
        FREQ_REF = 1 - FREQ_ALT,
        HW = (NN / (NN - 1)) * (1 - ((FREQ_REF^2) + (FREQ_ALT^2)))
      ) %>%
      dplyr::group_by(MARKERS) %>%
      dplyr::mutate(
        N_POP_C = n(), # number of pop per markers
        N_POP_C = 1/(N_POP_C * (N_POP_C - 1)) # corrected number of pop per markers
      ) %>%
      dplyr::ungroup(.)

    gene_diversity_between <- function(x) {
      new_sum <- purrr::lift(sum, na.rm = TRUE)
      res <- utils::combn(x, m = 2, FUN = function(y) y[1]*y[2], simplify = FALSE)
      res <- new_sum(res)
      return(res)
    }

    betas <- dplyr::select(.data = betas.prep, MARKERS, POP_ID, FREQ_ALT, FREQ_REF) %>%
      dplyr::group_by(MARKERS) %>%
      dplyr::summarise_at(.tbl = ., .vars = c("FREQ_ALT", "FREQ_REF"), .funs = list) %>%
      dplyr::mutate(
        FREQ_ALT = purrr::map(.x = FREQ_ALT, .f = gene_diversity_between),
        FREQ_REF = purrr::map(.x = FREQ_REF, .f = gene_diversity_between)
      ) %>%
      dplyr::mutate(HB = (unlist(FREQ_ALT) + unlist(FREQ_REF)) * 2) %>%
      dplyr::select(MARKERS, HB) %>%
      dplyr::full_join(
        dplyr::select(.data = betas.prep, MARKERS, POP_ID, HW, N_POP_C), by = "MARKERS"
      ) %>%
      dplyr::mutate(HB = 1 - N_POP_C * HB) %>%
      dplyr::group_by(POP_ID) %>%
      dplyr::mutate(BETAI = 1 - (sum(HW, na.rm = TRUE)/sum(HB, na.rm = TRUE))) %>%
      dplyr::select(POP_ID, MARKERS, HW, HB, BETAI) %>%
      dplyr::ungroup(.)

    betas.prep <- NULL
  } else {
    betas.prep <- dplyr::select(.data = input, MARKERS, POP_ID, INDIVIDUALS, GT) %>%
      dplyr::filter(GT != "000000") %>%
      dplyr::mutate(
        A1 = stringi::stri_sub(GT, 1, 3),
        A2 = stringi::stri_sub(GT, 4,6)
      ) %>%
      dplyr::select(MARKERS, POP_ID, INDIVIDUALS, A1, A2) %>%
      tidyr::gather(data = ., key = ALLELES, value = GT, -c(MARKERS, INDIVIDUALS, POP_ID)) %>%
      dplyr::group_by(MARKERS, GT, POP_ID) %>%
      dplyr::tally(.) %>%
      dplyr::ungroup() %>%
      tidyr::complete(data = ., POP_ID, tidyr::nesting(MARKERS, GT), fill = list(n = 0)) %>%
      dplyr::group_by(MARKERS, POP_ID) %>%
      dplyr::mutate(
        NN = sum(n),
        HOM_O = n / NN,
        HW = (NN / (NN - 1)) * (1 - sum(HOM_O^2))
      ) %>%
      dplyr::group_by(MARKERS) %>%
      dplyr::mutate(
        N_POP = length(unique(POP_ID)), # number of pop per markers
        N_POP_C = 1/(N_POP * (N_POP - 1)) # corrected number of pop per markers
      ) %>%
      dplyr::ungroup(.)

    gene_diversity_between <- function(x) {
      res <- utils::combn(x, m = 2, FUN = function(y) y[1]*y[2], simplify = FALSE)
      new_sum <- purrr::lift(sum, na.rm = TRUE)
      res <- new_sum(res)
      return(res)
    }

    betas <- dplyr::select(.data = betas.prep, MARKERS, POP_ID, GT, HOM_O) %>%
      dplyr::group_by(MARKERS, GT) %>%
      dplyr::summarise_at(.tbl = ., .vars = "HOM_O", .funs = list) %>%
      dplyr::mutate(
        FREQ = unlist(purrr::map(.x = HOM_O, .f = gene_diversity_between))
      ) %>%
      dplyr::group_by(MARKERS) %>%
      dplyr::summarise(HB = sum(FREQ) * 2) %>%
      dplyr::full_join(
        dplyr::distinct(.data = betas.prep, MARKERS, POP_ID, HW, N_POP_C), by = "MARKERS"
      ) %>%
      dplyr::mutate(HB = 1 - N_POP_C * HB) %>%
      dplyr::group_by(POP_ID) %>%
      dplyr::mutate(BETAI = 1 - (sum(HW, na.rm = TRUE) / sum(HB, na.rm = TRUE))) %>%
      dplyr::select(POP_ID, MARKERS, HW, HB, BETAI) %>%
      dplyr::ungroup(.)
  }

  # plots ----------------------------------------------------------------------
  # message("Generating plots")
  # # manhattan
  # fh.manhattan.plot <- ggplot(data = fh, aes(x = INDIVIDUALS, y = FH, colour = POP_ID)) +
  #   geom_jitter() +
  #   labs(y = "Individual IBDg (FH)") +
  #   labs(x = "Individuals") +
  #   labs(colour = "Populations") +
  #   # theme_minimal() +
  #   theme_classic() +
  #   # theme_dark() +
  #   theme(
  #     panel.grid.minor.x = element_blank(),
  #     panel.grid.major.y = element_blank(),
  #     axis.title.x = element_text(size = 10, family = "Helvetica", face = "bold"),
  #     axis.text.x = element_blank(),
  #     axis.title.y = element_text(size = 10, family = "Helvetica", face = "bold"),
  #     axis.text.y = element_text(size = 8, family = "Helvetica")
  #   )
  # # fh.manhattan.plot

  # # Histogram
  # fh.distribution.plot <- ggplot(data = fh, aes(x = FH)) +
  #   geom_histogram() +
  #   labs(x = "Individual IBDg (FH)") +
  #   labs(y = "Markers (number)") +
  #   theme(
  #     legend.position = "none",
  #     axis.title.x = element_text(size = 10, family = "Helvetica", face = "bold"),
  #     axis.title.y = element_text(size = 10, family = "Helvetica", face = "bold"),
  #     axis.text.x = element_text(size = 8, family = "Helvetica", angle = 90, hjust = 1, vjust = 0.5),
  #     strip.text.x = element_text(size = 10, family = "Helvetica", face = "bold")
  #   )
  # # fh.distribution.plot


  # Results --------------------------------------------------------------------
  res <- list(
    betaiovl = dplyr::distinct(.data = betas, POP_ID, BETAI),
    Hw = dplyr::distinct(.data = betas, MARKERS, POP_ID, HW),
    Hb = dplyr::distinct(.data = betas, MARKERS, HB)
  )

  if (verbose) {
    message("\nBETA per pop (averaged over locus):")
    message(stringi::stri_join(res$betaiovl$POP_ID, " = ", round(res$betaiovl$BETAI, 4), "\n"))
    timing <- proc.time() - timing
    message(stringi::stri_join("Computation time: ", round(timing[[3]]), " sec"))
    cat("############################## completed ##############################\n")
  }
  return(res)
}



##option 1 tested that was very straighforward using tidyr::nest

# Function to compute gene diversity between populations (Hb)
# gene_diversity_between <- function(x) {
#   mult <- function(y) y[1]*y[2]
#   res <- (sum(unlist(utils::combn(x = x$FREQ_ALT, m = 2, FUN = mult, simplify = FALSE))) + sum(unlist(utils::combn(x = x$FREQ_REF, m = 2, FUN = mult, simplify = FALSE))))*2
#   return(res)
# }
#
# #
# betas <- input %>%
#   dplyr::filter(GT_VCF != "./.") %>%
#   dplyr::group_by(MARKERS, POP_ID) %>%
#   dplyr::summarise(
#     N = n(),
#     HOM_ALT = length(GT_VCF[GT_VCF == "1/1"]),
#     HET = length(GT_VCF[GT_VCF == "1/0" | GT_VCF == "0/1"])
#   ) %>%
#   dplyr::mutate(
#     NN = N * 2,
#     NN_C = NN / (NN - 1),
#     FREQ_ALT = ((HOM_ALT * 2) + HET) / NN,
#     FREQ_REF = 1 - FREQ_ALT,
#     HOM_E = (FREQ_REF^2) + (FREQ_ALT^2),# MP2 hierfstat
#     HET_E = 1 - HOM_E,
#     HW = NN_C * HET_E
#   ) %>%
#   dplyr::group_by(MARKERS) %>%
#   dplyr::mutate(
#     N_POP = n(), # number of pop per markers
#     N_POP_C = 1/(N_POP * (N_POP - 1)) # corrected number of pop per markers
#   ) %>%
#   dplyr::ungroup(.) %>%
#   dplyr::select(MARKERS, POP_ID, HW, FREQ_ALT, FREQ_REF, N_POP_C) %>%
#   dplyr::group_by(MARKERS, N_POP_C) %>%
#   tidyr::nest(.key = FREQ) %>%
#   dplyr::mutate(
#     HB = purrr::map(.x = .$FREQ, .f = gene_diversity_between),
#     HB = 1 - N_POP_C * unlist(HB)
#   ) %>%
#   tidyr::unnest(.) %>%
#   dplyr::select(POP_ID, MARKERS, HW, HB) %>%
#   dplyr::group_by(POP_ID) %>%
#   dplyr::mutate(BETAI = 1 - (sum(HW, na.rm = TRUE)/sum(HB, na.rm = TRUE))) %>%
#   dplyr::ungroup(.)
