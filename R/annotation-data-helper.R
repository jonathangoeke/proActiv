#' @import IRanges
#' @import GenomicRanges
#' @import GenomicFeatures
#' @import GenomicAlignments
#'
NULL

# Get the intron ranks similar to exon rank (increasing from 5' to 3' end)
#' @importFrom S4Vectors runValue
getIntronRank <- function(granges) {
  len <- length(granges)
  intronRank <- NA
  if (len > 0) {
    if(runValue(strand(granges)) == '+') {
      intronRank <- 1:len
    } else {
      intronRank <- rev(1:len)
    }
  }
  return(intronRank)
}

# Reduce the first exons of genes to identify overlapping exons
reduceExonsByGene <- function(idx, exonRanges.firstExon.byGene) {
  exonRanges.firstExon.gene <- exonRanges.firstExon.byGene[[idx]]
  exonRanges.firstExon.gene.reduced <- reduce(exonRanges.firstExon.gene, with.revmap = TRUE, min.gapwidth = 0L)
  exonRanges.firstExon.gene.reduced$revmap <- as(lapply(exonRanges.firstExon.gene.reduced$revmap, function(idx) {exonRanges.firstExon.gene$customId[idx]}), 'IntegerList')
  return(exonRanges.firstExon.gene.reduced)
}

# Get the transcript ranges with metadata and transcript lengths
#' @importFrom GenomeInfoDb keepStandardChromosomes
#' @importFrom GenomeInfoDb 'seqlevelsStyle<-'
getTranscriptRanges <- function(txdb, species = 'Homo_sapiens') {
  # Retrieve transcript ranges with detailed metadata
  transcriptRanges <- transcripts(txdb, columns = c('TXID', 'TXSTART', 'TXEND', 'GENEID', 'TXNAME'))
  names(transcriptRanges) <- transcriptRanges$TXNAME
  transcriptRanges <- keepStandardChromosomes(x = transcriptRanges, species = species, pruning.mode = "tidy")
  GenomeInfoDb::seqlevelsStyle(transcriptRanges) <- 'UCSC'
  return(transcriptRanges)
}

# Get transcript start site coordinates
#' @importFrom GenomeInfoDb keepStandardChromosomes
#' @importFrom GenomeInfoDb 'seqlevelsStyle<-'
getTssRanges <- function(transcriptRanges) {
  # Annotate transcription start sites (TSSs) with ids
  tssCoordinates <- promoters(transcriptRanges, upstream = 0, downstream = 1)
  seqlevelsStyle(tssCoordinates) <- 'UCSC'
  tssCoordinates.unique <- unique(tssCoordinates)
  tssCoordinates.unique$tssId <- paste0('tss.', 1:length(tssCoordinates.unique))
  tssCoordinates.overlap <- findOverlaps(tssCoordinates, tssCoordinates.unique, type = 'equal')
  tssCoordinates$tssId <- tssCoordinates.unique$tssId[subjectHits(tssCoordinates.overlap)]
  return(tssCoordinates)
}

# Get exon ranges for each transcript
#' @importFrom GenomeInfoDb keepStandardChromosomes
#' @importFrom GenomeInfoDb 'seqlevelsStyle<-'
getExonRangesByTx <- function(txdb, species = 'Homo_sapiens') {
  exonRangesByTx <- exonsBy(txdb, by = 'tx', use.names = TRUE)
  exonRangesByTx <- keepStandardChromosomes(x = exonRangesByTx, species = species, pruning.mode = "tidy")
  seqlevelsStyle(exonRangesByTx) <- 'UCSC'
  return(exonRangesByTx)
}

# Get the first exon of each transcript
getFirstExonRanges <- function(exonRangesByTx.unlist, transcriptRanges) {
  exonRanges.firstExon <- exonRangesByTx.unlist[exonRangesByTx.unlist$exon_rank == 1]
  exonRanges.firstExon$tx_name <- names(exonRanges.firstExon)
  exonRanges.firstExon$customId <- 1:length(exonRanges.firstExon)
  return(exonRanges.firstExon)
}

# Reduce all first exons for each gene to identify transcripts belonging to each promoter
getReducedExonRanges <- function(exonRanges.firstExon.byGene, numberOfCores = 1) {
  # Identify overlapping first exons for each gene and annotate with the promoter ids
  print('Identify overlapping first exons for each gene and annotate with the promoter ids...')
  if (numberOfCores == 1) {
    exonReducedRanges.list <- lapply(1:length(exonRanges.firstExon.byGene), reduceExonsByGene, exonRanges.firstExon.byGene)
  } else {
    if (requireNamespace('parallel', quietly = TRUE) == TRUE) {
      exonReducedRanges.list <- parallel::mclapply(1:length(exonRanges.firstExon.byGene), reduceExonsByGene, exonRanges.firstExon.byGene, mc.cores = numberOfCores)
    } else {
      print('Warning: "parallel" package is not available! Using sequential version instead...')
      exonReducedRanges.list <- lapply(1:length(exonRanges.firstExon.byGene), reduceExonsByGene, exonRanges.firstExon.byGene)
    }
  }

  exonReducedRanges <- do.call(c, exonReducedRanges.list)
  exonReducedRanges$promoterId <- paste0('prmtr.', 1:length(exonReducedRanges))
  return(exonReducedRanges)
}

# Get intron ranges for each promoter
#' @importFrom GenomeInfoDb keepStandardChromosomes
#' @importFrom GenomeInfoDb 'seqlevelsStyle<-'
getIntronRangesByTx <- function(txdb, transcriptRanges, species = 'Homo_sapiens') {
  # Retrieve intron ranges for each promoter
  intronRangesByTx <- intronsByTranscript(txdb, use.names = TRUE)
  intronRangesByTx <- keepStandardChromosomes(x = intronRangesByTx, species = species, pruning.mode = "tidy")
  seqlevelsStyle(intronRangesByTx) <- 'UCSC'
  intronRangesByTx <- intronRangesByTx[names(transcriptRanges)]
  return(intronRangesByTx)
}

# Get unique intron ranges with custom ids
getUniqueIntronRanges <- function(intronRangesByTx.unlist) {
  # Annotate unique intron ranges  with unique ids
  intronRanges.unique <- unique(intronRangesByTx.unlist)
  intronRanges.unique <- sort(intronRanges.unique)
  intronRanges.unique$INTRONID <- 1:length(intronRanges.unique)
  names(intronRanges.unique) <- NULL
  return(intronRanges.unique)
}

# Get the rank of each intron within the transcript (similar to exon ranges)
getIntronRanks <- function(intronRangesByTx) {
  # Annotate intron's with ranks within each transcript
  intronRankByTx <- lapply(intronRangesByTx, getIntronRank)
  names(intronRankByTx) <- names(intronRangesByTx)
  return(intronRankByTx)
}

# Annotate all the intron ranges with the metadata
annotateAllIntronRanges <- function(intronRankByTx, intronRangesByTx.unlist, transcriptRanges, promoterIdMapping) {
  # Annotate all intron ranges with corresponding ids
  intronRankByTx.unlist <- unlist(intronRankByTx)
  intronRangesByTx.unlist$INTRONRANK <- intronRankByTx.unlist[which(!is.na(intronRankByTx.unlist))]
  intronRangesByTx.unlist$TXID <- transcriptRanges$TXID[match(names(intronRangesByTx.unlist), transcriptRanges$TXNAME)]
  intronRangesByTx.unlist$TXSTART <- transcriptRanges$TXSTART[match(names(intronRangesByTx.unlist), transcriptRanges$TXNAME)]
  intronRangesByTx.unlist$TXEND <- transcriptRanges$TXEND[match(names(intronRangesByTx.unlist), transcriptRanges$TXNAME)]
  intronRangesByTx.unlist$GENEID <- as.character(transcriptRanges$GENEID)[match(names(intronRangesByTx.unlist), transcriptRanges$TXNAME)]
  intronRangesByTx.unlist$TXNAME <- transcriptRanges$TXNAME[match(names(intronRangesByTx.unlist), transcriptRanges$TXNAME)]
  intronRangesByTx.unlist$TxWidth <- transcriptRanges$TxWidth[match(names(intronRangesByTx.unlist), transcriptRanges$TXNAME)]
  intronRangesByTx.unlist$promoterId <- promoterIdMapping$promoterId[match(intronRangesByTx.unlist$TXID, promoterIdMapping$transcriptId)]
  names(intronRangesByTx.unlist) <- NULL
  return(intronRangesByTx.unlist)
}

# Annotate unique intorn ranges with metadata
annotateUniqueIntronRanges <- function(intronRanges.unique, intronRangesByTx.unlist) {
  # Annotate unique intron ranges with corresponding ids
  intronRanges.unique$INTRONRANK <- as(split(intronRangesByTx.unlist$INTRONRANK, intronRangesByTx.unlist$INTRONID), 'IntegerList')
  intronRanges.unique$TXID <- as(split(intronRangesByTx.unlist$TXID, intronRangesByTx.unlist$INTRONID), 'IntegerList')
  intronRanges.unique$TXSTART <- as(split(intronRangesByTx.unlist$TXSTART, intronRangesByTx.unlist$INTRONID), 'IntegerList')
  intronRanges.unique$TXEND <- as(split(intronRangesByTx.unlist$TXEND, intronRangesByTx.unlist$INTRONID), 'IntegerList')
  intronRanges.unique$GENEID <- as(split(intronRangesByTx.unlist$GENEID, intronRangesByTx.unlist$INTRONID), 'CharacterList')
  intronRanges.unique$TXNAME <- as(split(intronRangesByTx.unlist$TXNAME, intronRangesByTx.unlist$INTRONID), 'CharacterList')
  intronRanges.unique$TxWidth <- as(split(intronRangesByTx.unlist$TxWidth, intronRangesByTx.unlist$INTRONID), 'IntegerList')
  intronRanges.unique$promoterId <- as(split(intronRangesByTx.unlist$promoterId, intronRangesByTx.unlist$INTRONID), 'CharacterList')
  return(intronRanges.unique)
}

# Prepare metadata for each unique intron range considering all of its uses across transcripts
#' @importFrom rlang .data
#' @importFrom dplyr tbl_df mutate group_by '%>%' filter distinct inner_join
getIntronTable <- function(intronRanges.unique, intronRangesByTx.unlist) {
  intronTable <- tbl_df(as.data.frame(intronRanges.unique))  # tbl_df for manipulation

  # Prepare metadata for each intron
  intronRangesByTx.metadata <- tbl_df(as.data.frame(mcols(intronRangesByTx.unlist)))
  intronRangesByTx.metadata <- mutate(group_by(intronRangesByTx.metadata, .data$TXNAME), IntronEndRank = max(.data$INTRONRANK) - .data$INTRONRANK + 1)
  intronRangesByTx.metadata <- mutate(group_by(intronRangesByTx.metadata, .data$INTRONID), MinIntronRank = min(.data$INTRONRANK))
  intronRangesByTx.metadata <- mutate(group_by(intronRangesByTx.metadata, .data$INTRONID), MaxIntronRank = max(.data$INTRONRANK))

  intronRangesByTx.metadata.unique <- group_by(intronRangesByTx.metadata, .data$INTRONID) %>%
    filter(.data$INTRONRANK == .data$MinIntronRank) %>%
    mutate(TxWidthMax = max(.data$TxWidth)) %>%
    dplyr::select(.data$INTRONID, .data$MinIntronRank, .data$MaxIntronRank, .data$TxWidthMax) %>%
    dplyr::rename(MinIntronRankTxWidthMax = .data$TxWidthMax) %>%
    distinct()

  intronTable <- inner_join(intronTable, intronRangesByTx.metadata.unique, by = 'INTRONID')

  ## Extend to last intron prediction
  intronRangesByTx.metadata <- mutate(group_by(intronRangesByTx.metadata, .data$INTRONID), MinIntronEndRank = min(.data$IntronEndRank))
  intronRangesByTx.metadata <- mutate(group_by(intronRangesByTx.metadata, .data$INTRONID), MaxIntronEndRank = max(.data$IntronEndRank))

  intronRangesByTx.metadata.unique <- group_by(intronRangesByTx.metadata, .data$INTRONID) %>%
    filter(.data$IntronEndRank == .data$MinIntronEndRank) %>%
    mutate(TxWidthMax = max(.data$TxWidth)) %>%
    dplyr::select(.data$INTRONID, .data$MinIntronEndRank, .data$MaxIntronEndRank, .data$TxWidthMax) %>%
    dplyr::rename(MinIntronEndRankTxWidthMax = .data$TxWidthMax) %>%
    distinct()
  intronTable <- inner_join(intronTable, intronRangesByTx.metadata.unique, by = 'INTRONID')

  return(intronTable)
}

# Get the ids of introns contributing to the transcription for each promoter
getIntronIdPerPromoter <- function(intronRangesByTx.unlist, promoterIdMapping) {
  intronRanges.firstIntron <- intronRangesByTx.unlist[intronRangesByTx.unlist$INTRONRANK == 1]
  intronIdByPromoter.firstIntron <- split(intronRanges.firstIntron$INTRONID, factor(intronRanges.firstIntron$promoterId, levels = paste0('prmtr.', 1:length(unique(promoterIdMapping$promoterId)))))
  intronIdByPromoter.firstIntron <- sapply(intronIdByPromoter.firstIntron, unique)
  return(intronIdByPromoter.firstIntron)
}

# Get the metadata for each promoter regarding the use of introns
#' @importFrom rlang .data
#' @importFrom dplyr group_by mutate filter distinct n
getPromoterMetadata <- function(intronTable.firstIntron) {
  ## Extract per promoter information from intronTable
  promoterMetadata <- group_by(intronTable.firstIntron, .data$promoterId) %>%
    mutate(MinMergedIntronRank = min(.data$MinIntronRank),
           MaxMergedIntronRank = max(.data$MaxIntronRank),
           MaxMergedIntronTxWidth = max(.data$MinIntronRankTxWidthMax),
           MinMergedIntronEndRank = min(.data$MinIntronEndRank),
           MaxMergedIntronEndRank = max(.data$MaxIntronEndRank),
           SumMergedIntrons = n()) %>%
    filter(.data$MinIntronRank == min(.data$MinIntronRank)) %>%
    dplyr::select(.data$promoterId, .data$MinMergedIntronRank, .data$MaxMergedIntronRank, .data$MaxMergedIntronTxWidth, .data$MinMergedIntronEndRank, .data$MaxMergedIntronEndRank, .data$SumMergedIntrons) %>%
    distinct()
  return(promoterMetadata)
}

# Annotate the reduced exon ranges for each promoter with the intron metadata
annotateReducedExonRanges <- function(exonReducedRanges, promoterMetadata, intronIdByPromoter.firstIntron) {
  intronReducedTable <- cbind(as.data.frame(exonReducedRanges), as.data.frame(promoterMetadata[match(exonReducedRanges$promoterId, promoterMetadata$promoterId), -1]))
  exonReducedRanges <- GRanges(intronReducedTable$seqnames,
                               ranges = IRanges(start = intronReducedTable$start, intronReducedTable$end),
                               strand = intronReducedTable$strand)
  exonReducedRanges$intronId <- as(intronIdByPromoter.firstIntron, 'IntegerList')
  mcols(exonReducedRanges) <- cbind(mcols(exonReducedRanges), intronReducedTable[, c('promoterId', 'MinMergedIntronRank', 'MaxMergedIntronRank', 'MaxMergedIntronTxWidth',
                                                                                     'MinMergedIntronEndRank', 'MaxMergedIntronEndRank', 'SumMergedIntrons')])
  return(exonReducedRanges)
}

# Annotate all unique introns with the promoter metadata
#' @importFrom methods as
annotateIntronRanges <- function(intronRanges.unique, intronTable) {
  # Annotate unique intron ranges
  intronRanges.annotated <- intronRanges.unique
  intronRanges.annotated$MinIntronRank <- intronTable$MinIntronRank
  intronRanges.annotated$MaxIntronRank <- intronTable$MaxIntronRank
  intronRanges.annotated$MinIntronRankTxWidthMax <- intronTable$MinIntronRankTxWidthMax
  intronRanges.annotated$MinIntronEndRank <- intronTable$MinIntronEndRank
  intronRanges.annotated$MaxIntronEndRank <- intronTable$MaxIntronEndRank
  intronRanges.annotated$MinIntronEndRankTxWidthMax <- intronTable$MinIntronEndRankTxWidthMax
  return(intronRanges.annotated)
}
