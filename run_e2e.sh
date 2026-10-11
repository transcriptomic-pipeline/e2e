#!/bin/bash
# ==============================================================================
# run_e2e.sh
# End-to-End Orchestrator for Transcriptomic Analysis Pipeline
# ==============================================================================

# Enforce strict POSIX safety protocols for unattended execution
set -euo pipefail

# ------------------------------------------------------------------------------
# Initialization and Logging
# ------------------------------------------------------------------------------
if [[ $# -ne 1 ]]; then
    echo "Usage: bash run_e2e.sh <path_to_pipeline_master.conf>"
    exit 1
fi

CONFIG_FILE="$1"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

mkdir -p "$OUTPUT_DIR/logs_e2e"
E2E_LOG="$OUTPUT_DIR/logs_e2e/e2e_pipeline_run_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo -e "[$(date '+%F %T')] [ORCHESTRATOR] $1" | tee -a "$E2E_LOG"
}

err() {
    echo -e "[$(date '+%F %T')] [FATAL ERROR] $1" | tee -a "$E2E_LOG" >&2
    exit 1
}

trap 'err "Pipeline aborted unexpectedly at line $LINENO. Review $E2E_LOG for complete traceback."' ERR

log "====================================================================="
log " Starting End-to-End Transcriptomic Pipeline"
log " Master Configuration: $CONFIG_FILE"
log " Output Directory: $OUTPUT_DIR"
log "====================================================================="

# ------------------------------------------------------------------------------
# 1. Quality Control (FastQC & Trimmomatic)
# ------------------------------------------------------------------------------
QC_OUT="$OUTPUT_DIR/qc"
if [[ "$RUN_QC" == "true" ]]; then
    log "--- Starting Quality Control Module ---"
    
    QC_CMD=("bash" "$PIPELINE_HOME/qc/run_qc.sh" "-i" "$RAW_FASTQ_DIR" "-o" "$QC_OUT" "-t" "$QC_THREADS")
    
    [[ -n "$QC_PHRED" ]] && QC_CMD+=("--phred" "$QC_PHRED")
    [[ -n "$QC_MINLEN" ]] && QC_CMD+=("--minlen" "$QC_MINLEN")
    [[ -n "$QC_LEADING" ]] && QC_CMD+=("--leading" "$QC_LEADING")
    [[ -n "$QC_TRAILING" ]] && QC_CMD+=("--trailing" "$QC_TRAILING")
    [[ -n "$QC_SLIDINGWINDOW" ]] && QC_CMD+=("--slidingwindow" "$QC_SLIDINGWINDOW")
    [[ -n "$QC_ADAPTER_FILE" ]] && QC_CMD+=("-a" "$QC_ADAPTER_FILE")
    [[ "$QC_SINGLE_END" == "true" ]] && QC_CMD+=("--single-end")
    [[ "$QC_RESUME_MODE" == "true" ]] && QC_CMD+=("--resume")
    
    log "Invocation: ${QC_CMD[*]}"
    "${QC_CMD[@]}" 2>&1 | tee -a "$E2E_LOG"
    log "QC Module Completed."
else
    log "Skipping QC Module."
fi

if [[ "$QC_SINGLE_END" == "true" ]]; then
    TRIMMED_DIR="$QC_OUT/trimmed/UP"
else
    TRIMMED_DIR="$QC_OUT/trimmed/PE"
fi

# ------------------------------------------------------------------------------
# 2. Sequence Alignment (STAR / HISAT2)
# ------------------------------------------------------------------------------
ALIGN_OUT="$OUTPUT_DIR/alignment"
if [[ "$RUN_ALIGNMENT" == "true" ]]; then
    log "--- Starting Sequence Alignment Module ---"
    
    if [[ ! -d "$TRIMMED_DIR" ]]; then
        err "Trimmed FASTQ directory not found: $TRIMMED_DIR. QC may have failed."
    fi
    
    ALIGN_CMD=("bash" "$PIPELINE_HOME/alignment/run_alignment.sh" \
        "-i" "$TRIMMED_DIR" \
        "-o" "$ALIGN_OUT" \
        "-t" "$ALIGN_THREADS" \
        "-a" "$ALIGNER" \
        "--reference" "$REF_FASTA" \
        "--gtf" "$REF_GTF")
        
    log "Invocation: ${ALIGN_CMD[*]}"
    "${ALIGN_CMD[@]}" 2>&1 | tee -a "$E2E_LOG"
    log "Alignment Module Completed."
else
    log "Skipping Alignment Module."
fi

# ------------------------------------------------------------------------------
# Dynamic Metadata Bridging and Transformation
# ------------------------------------------------------------------------------
log "--- Generating Dynamic Downstream Metadata Maps ---"
DGE_MAP="$OUTPUT_DIR/metadata/dge_map.tsv"
SPLICING_MAP="$OUTPUT_DIR/metadata/splicing_map.tsv"
VARIANTS_MAP="$OUTPUT_DIR/metadata/variants_map.tsv"

mkdir -p "$OUTPUT_DIR/metadata"
mkdir -p "$ALIGN_OUT/flat_bams"

echo -e "sample\tcondition\tpatient" > "$DGE_MAP"
echo -e "SampleID\tFilePath\tGroup" > "$SPLICING_MAP"
echo -e "SAMPLE_ID\tTYPE\tBAM_PATH\tMATCHED_WITH" > "$VARIANTS_MAP"

log "Flattening complex BAM directory structure via symbolic links..."
find "$ALIGN_OUT" -type f -name "*Aligned.sortedByCoord.out.bam" | while read -r bam_file; do
    ln -sf "$bam_file" "$ALIGN_OUT/flat_bams/$(basename "$bam_file")"
done

log "Parsing Base Manifest and resolving physical BAM paths..."
while IFS=$'\t' read -r sample_id condition patient matched_with; do
    [[ -z "$sample_id" || "$sample_id" =~ ^# ]] && continue
    
    bam_path=$(find "$ALIGN_OUT/flat_bams" -name "${sample_id}_Aligned.sortedByCoord.out.bam" 2>/dev/null | head -n 1 || true)
    
    if [[ -z "$bam_path" ]]; then
        log "WARNING: BAM file absent for sample $sample_id. Excluding from downstream processing maps."
        continue
    fi
    
    echo -e "${sample_id}\t${condition}\t${patient}" >> "$DGE_MAP"
    echo -e "${sample_id}\t${bam_path}\t${condition}" >> "$SPLICING_MAP"
    echo -e "${sample_id}\t${condition}\t${bam_path}\t${matched_with:-}" >> "$VARIANTS_MAP"

done < "$BASE_SAMPLE_MANIFEST"
log "Dynamic map generation complete."

# ------------------------------------------------------------------------------
# 3. Differential Gene Expression (featureCounts / DESeq2)
# ------------------------------------------------------------------------------
DGE_OUT="$OUTPUT_DIR/dge"
if [[ "$RUN_DGE" == "true" ]]; then
    log "--- Starting Differential Gene Expression Module ---"
    
    DGE_CMD=("bash" "$PIPELINE_HOME/dge/run_dge.sh" \
        "--out-dir" "$DGE_OUT" \
        "--mode" "$DGE_MODE" \
        "--bam-dir" "$ALIGN_OUT/flat_bams" \
        "--gtf" "$REF_GTF" \
        "--fasta" "$REF_FASTA" \
        "--threads" "$DGE_THREADS" \
        "--fc_paired" "$DGE_FC_PAIRED" \
        "--junc" "$DGE_JUNC" \
        "--deseq2_design" "$DGE_DESIGN" \
        "--min_read_support" "$DGE_MIN_READ_SUPPORT" \
        "--log2fc" "$DGE_LOG2FC" \
        "--padj" "$DGE_PADJ" \
        "--annotation" "$DGE_ANNOTATION" \
        "--sample_map" "$DGE_MAP")
        
    log "Invocation: ${DGE_CMD[*]}"
    "${DGE_CMD[@]}" 2>&1 | tee -a "$E2E_LOG"
    log "DGE Module Completed."
else
    log "Skipping DGE Module."
fi

# ------------------------------------------------------------------------------
# 4. Fusion Gene Detection (STAR-Fusion / Arriba)
# ------------------------------------------------------------------------------
FUSION_OUT="$OUTPUT_DIR/fusion"
if [[ "$RUN_FUSION" == "true" ]]; then
    log "--- Starting Fusion Module ---"
    
    FUSION_CMD=("bash" "$PIPELINE_HOME/fusion/run_fusion.sh" \
        "-t" "$FUSION_TOOL" \
        "-i" "$TRIMMED_DIR" \
        "-o" "$FUSION_OUT" \
        "--threads" "$FUSION_THREADS" \
        "--sample-jobs" "$FUSION_SAMPLE_JOBS" \
        "--depmap" "$FUSION_DEPMAP_DIR")
        
    [[ "$FUSION_SKIP_INTERSECTION" == "true" ]] && FUSION_CMD+=("-s")
    [[ -n "$ARRIBA_DB" ]] && FUSION_CMD+=("--arriba-db" "$ARRIBA_DB")
    [[ -n "$ARRIBA_BLACKLIST" ]] && FUSION_CMD+=("--arriba-blacklist" "$ARRIBA_BLACKLIST")
    [[ -n "$ARRIBA_KNOWN_FUSIONS" ]] && FUSION_CMD+=("--arriba-known-fusions" "$ARRIBA_KNOWN_FUSIONS")
    
    log "Invocation: ${FUSION_CMD[*]}"
    "${FUSION_CMD[@]}" 2>&1 | tee -a "$E2E_LOG"
    log "Fusion Module Completed."
else
    log "Skipping Fusion Module."
fi

# ------------------------------------------------------------------------------
# 5. Alternative Splicing (rMATS)
# ------------------------------------------------------------------------------
AS_OUT="$OUTPUT_DIR/alt_splicing"
if [[ "$RUN_ALT_SPLICING" == "true" ]]; then
    log "--- Starting Alternative Splicing Module ---"
    
    AS_READ_TYPE="paired"
    [[ "$QC_SINGLE_END" == "true" ]] && AS_READ_TYPE="single"

    AS_CMD=("bash" "$PIPELINE_HOME/alt-splicing/run_alt-splicing.sh" \
        "-i" "$ALIGN_OUT/flat_bams" \
        "-o" "$AS_OUT" \
        "--mode" "$AS_MODE" \
        "--stage" "$AS_STAGE" \
        "-m" "$SPLICING_MAP" \
        "-t" "$AS_READ_TYPE" \
        "--read-len" "$AS_READ_LEN" \
        "--threads" "$AS_THREADS" \
        "--gtf" "$REF_GTF" \
        "--star-index" "$STAR_INDEX" \
        "--fdr" "$AS_FDR" \
        "--delta-psi" "$AS_DELTA_PSI" \
        "--min-reads" "$AS_MIN_READS")
        
    [[ -n "$AS_RECURRENCE_MIN" ]] && AS_CMD+=("--recurrence" "$AS_RECURRENCE_MIN")
    
    log "Invocation: ${AS_CMD[*]}"
    "${AS_CMD[@]}" 2>&1 | tee -a "$E2E_LOG"
    log "Alternative Splicing Module Completed."
else
    log "Skipping Alternative Splicing Module."
fi

# ------------------------------------------------------------------------------
# 6. Transcript Variants (GATK Mutect2)
# ------------------------------------------------------------------------------
VAR_OUT="$OUTPUT_DIR/transcript_variants"
if [[ "$RUN_TRANSCRIPT_VARIANTS" == "true" ]]; then
    log "--- Starting Transcript Variants Module ---"
    
    VAR_CMD=("bash" "$PIPELINE_HOME/transcript-variants/run_transcript_variants.sh" \
        "-o" "$VAR_OUT" \
        "-j" "$VAR_JOBS" \
        "--ref" "$REF_FASTA" \
        "--dbsnp" "$VAR_DBSNP" \
        "--mills" "$VAR_MILLS" \
        "--gatk" "$VAR_GATK_BIN" \
        "--picard" "$VAR_PICARD_JAR" \
        "--samtools" "$VAR_SAMTOOLS_BIN" \
        "--sample-map" "$VARIANTS_MAP" \
        "--rg-file" "$BASE_RG_FILE")
        
    [[ -n "$VAR_GNOMAD" ]] && VAR_CMD+=("--gnomad" "$VAR_GNOMAD")
    [[ -n "$VAR_PON" ]] && VAR_CMD+=("--pon" "$VAR_PON" "--pon-mode" "use")
    [[ "$VAR_MARKDUP" == "false" ]] && VAR_CMD+=("--no-markdup")
    [[ "$VAR_SKIP_PREPROCESSED" == "true" ]] && VAR_CMD+=("--skip-preprocessed")
    
    log "Invocation: ${VAR_CMD[*]}"
    "${VAR_CMD[@]}" 2>&1 | tee -a "$E2E_LOG"
    log "Transcript Variants Module Completed."
else
    log "Skipping Transcript Variants Module."
fi

log "====================================================================="
log " End-to-End Transcriptomic Pipeline Completed Successfully."
log " Output Directory: $OUTPUT_DIR"
log "====================================================================="