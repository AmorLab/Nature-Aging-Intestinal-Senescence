#Alexander Harris and Joseph Gewolb
#Bulk RNAseq plotting functions

## --------------------------------------------------------------------------------------------------------
library(DESeq2)
library(dplyr)
library(ggplot2)
library(ComplexHeatmap)
library(org.Mm.eg.db)
library(tidyverse)
library(viridis)
library(EnhancedVolcano)
library(ComplexHeatmap)
library(circlize)


#Load in counts
counts <- read.delim("count_matrix.txt", header = TRUE, row.names = 1)
row.names(counts) <- make.unique(gsub("\\..*", "", row.names(counts)))
counts <- counts[which(rowSums(counts) > 0),]


#Set conditions
condition <- factor(c("O_UT","O_UT","O_uPAR","O_uPAR","Y_UT","Y_UT","Y_uPAR","Y_uPAR"))
coldata <- data.frame(row.names = colnames(counts), condition)


#Run Deseq2
dds <- DESeqDataSetFromMatrix(countData = round(counts), colData = coldata, design = ~condition)
dds <- DESeq(dds)


#Normalization and vst
norm_counts <- counts(dds, normalized = TRUE)
norm_counts.df <- as.data.frame(norm_counts)
norm_counts.df$symbol <- mapIds(org.Mm.eg.db,
                                keys = rownames(norm_counts.df),
                                keytype = "ENSEMBL",
                                column = "SYMBOL")

norm_counts.df <- na.omit(norm_counts.df)
norm_counts.df <- norm_counts.df[!duplicated(norm_counts.df$symbol),]
row.names(norm_counts.df) <- norm_counts.df$symbol
norm_counts.df$symbol <- NULL
vsdata <- vst(dds, blind = TRUE)
vsdata <- assay(vsdata)


#Get stemness gene expression levels for bar graphs
genes_to_plot <- c("Lgr4", "Lgr5", "Myc", "Sox9", "Olfm4", "Ccnd1", 'Hopx', 'Malat1')
vst_counts <- as.data.frame(vsdata)
vst_counts$symbol <- mapIds(org.Mm.eg.db, keys = row.names(vst_counts), keytype = "ENSEMBL", column = "SYMBOL")
vst_counts <- na.omit(vst_counts)
vst_counts <- vst_counts[!duplicated(vst_counts$symbol),]
row.names(vst_counts) <- vst_counts$symbol
vst_counts$symbol <- NULL
vst_subset <- vst_counts[genes_to_plot, ]
vst_norm <- t(scale(t(vst_subset), center = TRUE, scale = FALSE))
vst_norm <- t(apply(vst_norm, 1, function(x) x - min(x)))
write.table(vst_norm,'vst_norm.csv',sep = ',')


#Prep for heatmap
gene_symbols <- mapIds(org.Mm.eg.db,
                       keys = rownames(vsdata),
                       keytype = "ENSEMBL",
                       column = "SYMBOL")
valid_genes <- which(!is.na(gene_symbols) & !duplicated(gene_symbols))
vsdata <- vsdata[valid_genes, ]
rownames(vsdata) <- gene_symbols[valid_genes]
stemness_genes <- c("Sox9", "Ccnd1", "Myc", "Malat1", "Lgr5", "Lgr4", "Hopx", "Olfm4")
available_stemness_genes <- stemness_genes[stemness_genes %in% rownames(vsdata)]
stem_mat <- vsdata[available_stemness_genes, ]
stem_mat_z <- t(scale(t(stem_mat)))
grouping <- list(
  O_UT = c("O_UT_1", "O_UT_2"),
  O_uPAR = c("O_uPAR_1", "O_uPAR_2"),
  Y_UT = c("Y_UT_1", "Y_UT_2"),
  Y_uPAR = c("Y_uPAR_1", "Y_uPAR_2")
)
stem_mat_grouped <- sapply(grouping, function(reps) {
  rowMeans(stem_mat_z[, reps, drop = FALSE])
})
colnames(stem_mat_grouped) <- c("Old UT", "Old uPAR", "Young UT", "Young uPAR")
stem_mat_grouped <- stem_mat_grouped[, c("Young UT", "Young uPAR", "Old UT", "Old uPAR")]


#Create heatmap
heatmap_color_scale <- colorRamp2(c(-1.5, 0, 1.5), c("blue", "white", "red"))
O_Y_heatmap <- Heatmap(
  stem_mat_grouped,
  name = "z-score",
  col = heatmap_color_scale,
  cluster_rows = TRUE,
  cluster_columns = FALSE,
  show_row_names = TRUE,
  show_column_names = TRUE,
  column_title = "Stemness Gene Expression",
  border = FALSE
)
pdf("O_Y_heatmap.pdf", width = 10, height = 6)
draw(O_Y_heatmap)
dev.off()


#Get lfcShrink for GSEA preranking
res <- results(dds, contrast = c('condition','O_UT','Y_UT'))
resLFCshrink <- lfcShrink(dds, contrast = c('condition','O_UT','Y_UT'), type = "ashr")
resLFCshrink.df <- as.data.frame(resLFCshrink)
resLFCshrink.df$symbol <- mapIds(org.Mm.eg.db, keys = rownames(resLFCshrink.df), keytype = "ENSEMBL", column = "SYMBOL")
resLFCshrink.df <- na.omit(resLFCshrink.df)
resLFCshrink.df <- resLFCshrink.df[!duplicated(resLFCshrink.df$symbol),]
write.table(resLFCshrink.df,'lfcshrink_O_UT_Y_UT.csv',sep = ',')


#Prep for lollipop plot of GSEA pathways
hm <- read.delim("Hallmark_O_uPAR_O_UT.txt", header = TRUE, row.names = 1)
Paths <- rownames(hm)
hm <- hm%>%mutate(Paths=fct_reorder(Paths, NES))


#Create lollipop plot for GSEA pathways
Hallmark_O_uPAR_O_UT_lollipop <- ggplot(hm, aes(x = NES, y = Paths)) +
  geom_segment(aes(x = 0, y = Paths, xend = NES, yend = Paths)) +
  geom_point(aes(color = padj), size = 8) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black") +
  scale_color_viridis_c(option = 'plasma') +
  labs(
    title = "Old m.uPAR-m.28z vs Old UT",  # Title
    x = "Normalized enrichment score",
    y = ""
  ) +
  theme_classic() +
  theme(
    text = element_text(size = 16),  # Larger text size
    plot.title = element_text(hjust = 0.5, face = "bold"),  # Centered and bold title
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    panel.border = element_rect(color = "black", fill = NA, linewidth = 1),
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank()
  )
ggsave(file = 'Hallmark_O_uPAR_O_UT_pathways.pdf', plot=Hallmark_O_uPAR_O_UT_lollipop, width=10, height=10, units="in")


#Prep for Volcano Plot
sigs.df <- sigs.df %>% 
  mutate(
    regulation = case_when(
      padj < 0.05 & log2FoldChange > 1 ~ "Upregulated",
      padj < 0.05 & log2FoldChange < -1 ~ "Downregulated",
      TRUE ~ "Not Significant"
    )
  )
top_up <- sigs.df %>%
  filter(padj < 0.05, log2FoldChange > 0) %>%
  arrange(desc(log2FoldChange)) %>%
  slice_head(n = 10)

top_down <- sigs.df %>%
  filter(padj < 0.05, log2FoldChange < 0) %>%
  arrange(log2FoldChange) %>%
  slice_head(n = 10)
top_genes <- bind_rows(top_up, top_down)


#Create Enhanced Volcano Plot
reg_colors <- c(
  "Not Significant" = "grey30",
  "Downregulated" = "#7CA1CC",
  "Upregulated" = "#FF4902"
)

O_UT_Y_UT_Evolcano <- EnhancedVolcano(
  sigs.df,
  lab = sigs.df$symbol,
  x = 'log2FoldChange',
  y = 'padj',
  selectLab = top_genes$symbol,
  pCutoff = 0.05,
  FCcutoff = 1,
  drawConnectors = TRUE,
  arrowheads = FALSE,
  ends = 'none',
  widthConnectors = 0.5,
  max.overlaps = 40,
  pointSize = 2.0,
  labSize = 3.0,
  colCustom = reg_colors[sigs.df$regulation],
  legendLabels = c('Not Significant', 'Downregulated', 'Upregulated'),
  legendPosition = 'right',
  title = "Old UT vs Young UT",
  xlab = "log2 Fold Change",
  ylab = "-log10(padj)",
  subtitle = NULL,
  caption = NULL
)
ggsave(file = 'O_UT_Y_UT_Evolcano.pdf', plot=O_UT_Y_UT_Evolcano, width=10, height=6, units="in")
