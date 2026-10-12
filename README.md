# e2e

# End-to-End Orchestrator — Transcriptomic Pipeline

Automated master controller for the continuous, unattended execution of the ESCC transcriptomic analysis pipeline. 

**Author:** Babul Pradhan, Ph.D. Student, Institute of Bioinformatics (IOB), Bangalore, India
**Supervisor:** Dr. Jyoti Sharma, Institute of Bioinformatics (IOB), Bangalore, India
**Date:** 09/12/2025
**Part of:** Automated Transcriptomic Analysis Pipeline for ESCC

---

## Overview

This repository acts as the global orchestrator for six independent bioinformatics modules. It relies on strict POSIX safety protocols (`set -euo pipefail`) to halt execution upon critical failure, preventing corrupted data from propagating through the pipeline. By centralizing all parameters into a single master configuration file, this module ensures perfectly reproducible clinical-grade runs.

**Pipeline Flow:**
`Raw FASTQ` → `[QC]` → `[Alignment]` → `[Dynamic Metadata Bridging]` → `[DGE | Fusion | Alt-Splicing | Transcript Variants]

---

## Repository Structure

```text
e2e/
├── install_e2e.sh          # Workspace setup and dependency cloner
├── pipeline_master.conf    # Global configuration and execution parameters
└── run_e2e.sh              # Master execution wrapper and metadata translator
System Requirements
OS: Linux (Ubuntu 18.04+, CentOS 7+)

RAM: 32 GB minimum (required for STAR alignment and STAR-Fusion), 64 GB recommended

Storage: 1TB+ recommended for raw FASTQ, intermediate BAMs, and reference databases

Permissions: sudo access required for initial workspace creation in /opt

Workspace Setup
The pipeline operates within a centralized home directory to resolve path dependencies across modules. Use the installation script to build the workspace and clone all necessary repositories.

Bash
# 1. Download the orchestrator setup script
git clone [https://github.com/transcriptomic-pipeline/e2e.git](https://github.com/transcriptomic-pipeline/e2e.git)
cd e2e

# 2. Execute the workspace builder (requires sudo for /opt directory creation)
bash install_e2e.sh
Note: The installer automatically creates /opt/transcriptomic-pipeline (the pipeline home directory) and clones the qc, alignment, dge, fusion, alt-splicing, and transcript-variants repositories alongside e2e into the pipeline home directory.

Configuration & Metadata
Prior to execution, the administrator must provide two baseline metadata files and update the configuration parameters.

1. Master Configuration (pipeline_master.conf)
Open and edit the configuration file using any text editor and set your global execution toggles to "true" or "false". Update the hardware thread limits and reference genome paths to match your server architecture.

2. Base Metadata Files
You must create and supply two master TSV files (sample files are provided under the "examples" dir) into the "e2e" under the pipeline home directory defining your cohort:

*Base Sample Manifest (base_sample_manifest.tsv): Tracks experimental design in the "dge", and "alt-splicing" modules (only if used).

Format: SAMPLE_ID \t CONDITION(Tumor/Normal) \t PATIENT_ID \t MATCHED_WITH

*Read Group Details (base_rg_file.tsv): Required for Genome Analysis Tool Kit (GATK) somatic variant calling in the "transcript-variants" module (only if used).

Format: SAMPLE \t RGID \t RGLB \t RGPL \t RGPU \t RGSM

The orchestrator will automatically flatten BAM directory structures and translate these two baseline files into the specific map files in ".tsv" formats required by downstream tools (dge, alt-splicing, and transcript-variants).

Execution
Once the configuration file is tailored to your study, launch the unattended pipeline:

Bash
cd /opt/transcriptomic-pipeline/e2e

# Run the end-to-end pipeline (e2e) under the pipeline home directory (/opt/transcriptomic-pipeline/e2e)
bash run_e2e.sh pipeline_master.conf
All standard output, error traces, and module exit codes are actively monitored and piped into timestamped files within the $OUTPUT_DIR/logs_e2e directory for regulatory auditing.

Contact & Citation
Babul Pradhan — babul@ibioinformatics.com
Supervisor: Dr. Jyoti Sharma, Institute of Bioinformatics (IOB), Bangalore, India
GitHub: babulpradhan1

If you use this orchestration framework in your research, please cite:

Code snippet
@misc{transcriptomic_pipeline,
  author = {Babul Pradhan and Jyoti Sharma},
  title = {End-to-End Orchestrator — Transcriptomic Pipeline},
  year = {2025},
  version = {1.0.0},
  url = {[https://github.com/transcriptomic-pipeline/e2e](https://github.com/transcriptomic-pipeline/e2e)}
}
