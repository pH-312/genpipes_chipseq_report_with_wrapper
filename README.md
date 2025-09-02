# README for 'genpipes_chipseq_report' & 'genpipes_chipseq_report_with_wrapper'
Last updated: 2025-08-29

## About
Collects files from GenPipes' ChIP-seq pipeline (for both ChIP-seq and ATAC-seq data)
Renders an HTML report from 'ChIP-seq_Report.Rmd' or 'ATAC-seq_Report.Rmd'
Outputs a tarball, either 'GenPipes_ChIP-seq_Results.tar.gz' or 'GenPipes_ATAC-seq_Results.tar.gz', containing the following:
- annotations directory
- ChIP-seq_Report.html or ATAC-seq_Report.html
- graphs directory (with added fingerprint plots, read coverage PCA plots and insert size plots (ATAC-seq only))
- IHEC metrics table (all samples)
- MultiQC Report HTML
- peak_call.zip (**TO DO**)
- tracks_bigWigs.zip
- trimReadsetTable.tsv

## To run
Go to report directory of GenPipes' output
See below ("Difference between 'genpipes_chipseq_report' & 'genpipes_chipseq_report_with_wrapper'") for how to run each script

### Requirements
**For ChIP-seq:** 
Must run Genpipes steps 1 (if necessary), 2-18 (8 is optional?) and 20-21

**For ATAC-seq:** 
Must run Genpipes steps 1 (if necessary), 2-17 (8 is optional?) and 19-20 (with "-t atacseq" option)
TMP: Until ATAC-seq pipeline is updated with deepTools:
  Run GenPipes with the "-t chipseq" option for step 12 and 20 only, specifying the same output as for the ATAC-seq run
  Must specify "atacseq" as the 3rd argument when submitting the job (defaults to "chipseq" if not specified)

### Notes
- Because HOMER motif analysis is done only with narrow peak marks, rendering the 'Peak Annotations' tab (see child Rmd 'ChIP-seq_Peak_Annotations_Tab.Rmd') in 'ChIP-seq_Report.Rmd' depends of the presence of 'ChipSeq.homer_find_motifs_genome.md'
- The script will be exited if not run from the right directory, if missing required arguments, if required files are not found, if step fails, etc.

## Difference between 'genpipes_chipseq_report' & 'genpipes_chipseq_report_with_wrapper':
'genpipes_chipseq_report_with_wrapper' was created to take into account situations in which users would want to specify what ini file, readset file and project start date to use. 'generate_report_wrapper.sh' was created to facilitate passing arguments to 'generate_report.sh'.

'genpipes_chipseq_report' (original version) takes only project ID and primary contact as arguments (tmp: seq type too). Here, the newest ini file is always used. The name of the readset file to use is extracted from this ini file, as is the project start date.

**Important note 1:** Despite files in each directory having the same names, the scripts are *different* (.Rmd and .sh files)
The Rmd files will only work with their corresponding .sh scripts

**Important note 2:** 'genpipes_chipseq_report_with_wrapper/generate_report.sh' is based off 'genpipes_chipseq_report/generate_report.sh', but has been tested less extensively than the original script

### 'genpipes_chipseq_report'
Submitted directly to the SLURM with 2/3 mandatory positional arguments:
    ARG1: Project ID          (mandatory)
    ARG2: Primary contact     (mandatory)
    ARG3: chipseq or atacseq  (optional, defaults to chipseq)

Example:
[user@narval report]$ sbatch path_to/genpipes_chipseq_report/generate_report.sh "Project ID" "Primary Contact" "atacseq"

### 'genpipes_chipseq_report_with_wrapper'
Submitted directly to the SLURM with 2-6 positional arguments (1) or indirectly using 'generate_report_wrapper.sh' (2)

Option 1: Submit directly to the SLURM
Specify the following position arguments (no skips):
    ARG1: Project ID            (mandatory)
    ARG2: Primary contact       (mandatory)
    ARG3: chipseq or atacseq    (optional, defaults to chipseq)
    ARG4: Ini file name         (optional, defalut: newest ini file)
    ARG5: Readset file name     (optional, default: extracted from ini file)
    ARG6: Project start date    (optional, default: extracted from ini file)

Example:
[user@narval report]$ sbatch path_to/genpipes_chipseq_report_with_wrapper/generate_report.sh "Project ID" "Primary Contact" "chipseq" "ChipSeq.chipseq.2025-08-11T15.44.04.config.trace.ini" "myReadset2.tsv" "2025-08-26"

Option 2: Using the wrapper
Run 'generate_report_wrapper.sh' from the login node
Enter inputs as prompted
Check inputs and press Enter to confirm submission of 'generate_report.sh' to SLURM

Example:
[user@narval report]$ bash path_to/genpipes_chipseq_report_with_wrapper/generate_report_wrapper.sh

## Anticipated changes
'generate_report.sh' was created considering that the next iteration of GenPipes' ChIP-seq pipeline would have the following updates:
- Addition of deepTools analysis to ATAC-seq pipeline
- Fix to IHEC metrics all samples table for ChIP-seq pipeline

Additionally, the 'peak_call' directory would have to be added to the report directory and the final archive file

**Important:** need to fix read coverage PCA plots for ATAC-seq data using a consensus peak file created by merging bedfiles

Here is a list of changes anticipated for both versions of 'generate_report.sh' (in order of appearance):
1) For the 3rd argument becomes optional for atacseq (in setup) 
    Once deepTools is added for atacseq, the script should be able to get the seq_type directly from the newest ini file
2) Change multiQC_date and html find pattern (step 2)
    For ATAC-seq, runnig GenPipes a 2nd time with chipseq option can create a second multiQC file
    So temporarily, the script specifies -iname "ChipSeq.chipseq.multiqc_data"
    Commented out for later use: -iname "ChipSeq.*.multiqc_data"
3) List peak_call files (step 2) *
4) A: For ChIP-seq, finding individual ihec metrics files not required after fix to population of all samples table (step 2)
4) B: Move find ihec_metrics (all samples) from ATAC-seq specific section to common find section (step 2)
5) Symlink peak_call files, can use similar method as bigwig files (after step 2 - before step 6) *
6) Remove step 4 entirely after IHEC metrics table is fixed (step 4)
7) Fix read coverage PCA plots for ATAC-seq using censensus peak file (step 5) * **Important!**
8) Add peak_call files to list of files to include in the tree (step 6) *
9) Add peak_call files to the tarball (step 8) *

## Suggestions from presentation (2025-08-28)
- Saving Rmd to create report in different formats (pdf, etc.)
- Explaining what inputs are
- Embedding MultiQC report directly into the page
- Explaining design
