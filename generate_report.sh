#!/bin/bash
#SBATCH --time=01:00:00
#SBATCH --mem=2G
#SBATCH --job-name=generate_report
#SBATCH --output=%J-generate_report.out
#SBATCH --account=rrg-bourqueg-ad

###################################################################################################################
###               Generate report from GenPipes' ChIP-seq Pipeline Output (ChIP-seq & ATAC-seq)                 ###
###################################################################################################################
# Version 6.1: 2025-08-22 
# This version implements the wrapper and has 6 positional arguments, but requires at least the first 2 to be specified

# Generates an archive file (.tar.gz) for clients with results output by GenPipes' ChIP-seq pipeline (version 6.0)
# Creates an HTML report summarizing the results

###################################
#           HOW TO USE            #
###################################
# --- OPTION 1: WITH WRAPPER ----------------------------------------------------------------------------------------
# From the report directory of Genpipes' output, run generate_report_wrapper.sh in the login node.

# EXAMPLE: [user@narval report]$ bash path_to/generate_report_wrapper.sh

# --- OPTION 2: WITHOUT WRAPPER -------------------------------------------------------------------------------------
# From the report directory of Genpipes' output, submit generate_report.sh to the SLURM
# Specify the following positional arguments:
# ARG1: Project ID (mandatory)
# ARG: Primary contact (mandatory)
# ARG3: chipseq or atacseq (optional, default: chipseq)
  # TMP: specify "atacseq" as 3rd arg for ATAC-seq data
  # (Script finds seq_type in most recent ini so running deepTools with "-t chipseq" makes seq_type "chipseq")
  # (Once deepTools is implemented, no more need to specify "atacseq")
# ARG4: Ini file name (optional, defalut: newest ini file)
# ARG5: Readset file name (optional, default: extracted from ini file)
# ARG6: Project start date (optional, default: extracted from ini file)

# SIMPLE EXAMPLE: [user@narval report]$ sbatch path_to/generate_report.sh "Project ID" "Primary Contact" "atacseq"

# COMPLEX EXAMPLE: [user@narval report]$ sbatch path_to/generate_report.sh "Project ID" "Primary Contact" "chipseq" "ChipSeq.chipseq.2025-08-11T15.44.04.config.trace.ini" "myReadset2.tsv" "2025-08-26"

# generate_report_test.sh does the following:
    # 1) Finds the files and directories needed to generate the report and checks if they exists
    # 2) Copies or links required files to the report directory
    # 3) Compresses bigWigs into zip file in report directory
    # 4) Fixes the ihec_metrics table (TMP, ChIP-seq pipeline only)
    # 5) Generates a read coverage PCA plot (pdf and png)
    # 6) Generates a tree of the report folder
    # 7) Renders Rmd report into HTML 
    # 8) Compresses client report folder (only specified files)

# Output: 'GenPipes_ChIP-seq_Results.tar.gz' or 'GenPipes_ATAC-seq_Results.tar.gz' archive file containing the following:
    # annotations directory
    # ChIP-seq_Report.html or ATAC-seq_Report.html
    # graphs directory (with added fingerprint plots, read coverage PCA plots and insert size plots (ATAC-seq only))
    # IHEC metrics table (all samples)
    # MultiQC Report HTML
    # peak_call.zip                                                      ######## TO DO #########
    # tracks_bigWigs.zip
    # trimReadsetTable.tsv

###################################
#        NOTES & ASSUMPTIONS      #
###################################
# For ChIP-seq: 
# Must run Genpipes steps 1 (if necessary), 2-18 (8 is optional?) and 20-21
# Because HOMER motif analysis is done only with narrow peak marks, rendering the 'Peak Annotations' tab in 'ChIP-seq_Report.Rmd' 
# depends of the presence of 'ChipSeq.homer_find_motifs_genome.md'

# For ATAC-seq (before update): 
# Must run Genpipes steps 1 (if necessary), 2-17 (8 is optional?) and 19-20 (with "-t atacseq" option)
# TMP: Until ATAC-seq pipeline is updated with deepTools:
  # Run GenPipes with the "-t chipseq" option for step 12 and 20 only, specifying the same output as for the ATAC-seq run
  # Must specify "atacseq" as the 3rd argument when submitting the job (defaults to "chipseq" if not specified)

# For reference:
# rf_dir = ReportingFigures directory: contains this script, Rmd scripts for report generation and images required to generate report
# results_dir = GenPipes output directory 
# report_dir = Report directory within results_dir

echo $'\n'NOTES \---------------------------------------------------------
echo "Collecting files from GenPipes ChIP-seq pipeline for client's results and rendering report..."

### MODULES ##################################################################################################################
echo $'\n'MODULES \-----------------------------------------------------------

module purge
module load mugqic/R_Bioconductor/4.3.2_3.18
module load mugqic/deepTools/3.5.1
module load mugqic/ghostscript/8.70

### FUNCTIONS ###############################################################################################################
# If a variable is empty (file/dir not found), exit program:

file_exists () {
  file="$1"
  file_name="$2"
  if [ -z "${file}" ]; then
    echo "Error: ${file_name} file(s) not found. Exiting."
    exit 1
  fi
}

dir_exists () {
  dir="$1"
  dir_name="$2"
  if [ -z "${dir}" ]; then
    echo "Error: ${dir_name} directory not found. Exiting."
    exit 1
  fi
}

### SETUP ###################################################################################################################
echo $'\n'SETUP \-------------------------------------------------------------
# - Command arguments ---------------------------------------------------
# Arguments to pass as parameters to report Rmd:
project_id="$1"
primary_contact="$2"
seq_type="$3"
ini_name=$(basename "$4")
readset_name=$(basename "$5")
start_date="$6"

# Check that project_id and primary_contact arguments were provided:
if [[ -z "$project_id" || -z "$primary_contact" ]]; then
    echo "Error: Project ID and primary contact not provided."
    echo "Please provide the project ID as the 1st argument and primary contact as the 2nd argument when submitting this script." 
    echo "Exiting."
    exit 1
fi

# - Working directory setup ---------------------------------------------
# Check that script is running in the correct directory (report):
if [ "$(basename "$(pwd)")" != "report" ]; then
    echo "Error: Running script from the incorrect directory." 
    echo "Please run from the GenPipes output report directory." 
    echo "Exiting."
    exit 1
fi

report_dir="$(pwd)" # GenPipes report directory
results_dir="$(dirname "$report_dir")" # GenPipes results directory

# For files copied to report_dir, but excluded from archive file:
  # Includes ini, readset, read coverage and report images
copied2report_dir="$report_dir/copied2report"
mkdir "$copied2report_dir"

# - ChIP-seq or ATAC-seq? -----------------------------------------------
# Find ini file:
if [[ -n "$ini_name" ]]; then
  # Use specfied ini file
  ini_file=$(find "$results_dir" -maxdepth 1 -type f -iname "$ini_name")
else
  # Use newest ini file (default)
  ini_file=$(find "$results_dir" -maxdepth 1 -type f -iname "ChipSeq*.config.trace.ini" -printf "%p\n" | sort -nr | head -n 1)
fi
file_exists "$ini_file" Config.trace.ini

# Extract GenPipes command used:
genpipes_command=$(grep "^# Command:" "$ini_file")

# TMP until ATAC-seq pipeline is updated:
seq_type="$3"
if [ -z "$seq_type" ]; then # If not specified: default to chipseq
  seq_type="chipseq"
elif [[ "$seq_type" != "chipseq" && "$seq_type" != "atacseq" ]]; then # If specified: check input
  echo "Invalid input for sequencing type. Use \"chipseq\" or \"atacseq\". Exiting."
  exit 1
fi
# For when ATAC-seq pipeline is updated with deepTools: (not tested)
# Get seq_type from ini command: chipseq or atacseq?
# if [ -z "$seq_type" ]; then # If ARG3 not specified, retrieve from ini
#   if [[ "$genpipes_command" != *"--type "* && "$genpipes_command" != *"-t "* ]]; then #Type not specified, default to chipseq
#     seq_type="chipseq"
#   else
#     seq_type=$(echo "$genpipes_command" | sed -n 's/.*\(--type\|-t\) \([^ ]*\).*/\2/p')
#   fi
# else
#   seq_type="$3"
#   if [[ "$seq_type" != "chipseq" && "$seq_type" != "atacseq" ]]; then # If specified: check input
#     echo "Invalid input for sequencing type. Use \"chipseq\" or \"atacseq\". Exiting."
#     exit 1
#   fi
# fi


# - Readset -------------------------------------------------------------
if [ -z "$readset_name" ]; then
  # If no readset name specified, get from ini command:
  readset_name=$(basename "$(echo "$genpipes_command" | sed -E 's/.*-r[=[:space:]]*([^[:space:]]+).*/\1/')")
fi

# Find readset file: - - - - - - - - - - - - - - -
dir="$results_dir" # Starting from the results_dir

# Traverse up directories until readset file is found or "projects" directory is reached:
while [[ "$(basename "$dir")" != "projects" ]]; do
  readset=$(find "$dir" -maxdepth 1 -type f,l -name "$readset_name")
  # Readset found:
    if [[ -f "$readset" ]]; then
        break
    fi
  # Readset not found, go up to parent dir:
  dir=$(dirname "$dir")
done
file_exists "$readset" "Readset"
# - - - - - - - - - - - - - - - - - - - - - - - - -

# - Project start date --------------------------------------------------
if [ -z "$start_date" ]; then
  # If no date specified, get from ini command:
  start_date=$(sed -n 's/^# Created on: \([0-9\-]*\)T.*/\1/p' "$ini_file")
fi

# - ReportingFigures & R Markdown ----------------------------------------
rf_dir="/path_to/ReportingFigures/genpipes_chipseq_report_with_wrapper" # TO CHANGE DURING SET-UP
img_dir="$rf_dir/report_images"

if [[ "$seq_type" == "chipseq" ]]; then
  rmd_name="ChIP-seq_Report.Rmd"
elif [[ "$seq_type" == "atacseq" ]]; then
  rmd_name="ATAC-seq_Report.Rmd"
fi

rmd="$rf_dir/$rmd_name" # Path R Markdown script for generating html report

if [[ "$seq_type" == "chipseq" ]]; then # Child document to main rmd (for ChIP-seq with narrow peaks only)
  peak_annotations_rmd="$rf_dir/ChIP-seq_Peak_Annotations_Tab.Rmd"
elif [[ "$seq_type" == "atacseq" ]]; then
  peak_annotations_rmd="NA"
fi

# - Output archive file (.tar.gz) ----------------------------------------
if [[ "$seq_type" == "chipseq" ]]; then
  results_compressed="GenPipes_ChIP-seq_Results.tar.gz"
elif [[ "$seq_type" == "atacseq" ]]; then
  results_compressed="GenPipes_ATAC-seq_Results.tar.gz"
fi

# - Check arguments and paths -------------------------------------------
echo "Project ID:             $project_id"
echo "Primary contact:        $primary_contact"
echo "Sequencing data type:   $seq_type"
echo "Project start date:     $start_date" $'\n'
echo "Ini file:               $(basename "$ini_file")"
echo "Readset file name:      $(basename "$readset")" $'\n'
echo "Report directory (working directory): $report_dir"
echo "Report R Markdown:                    $rmd" 
echo "Output archive file:                  $results_compressed" $'\n'

### (1) Finding required files & directories ############################################################################### (1) ###
# Exit program if required file(s) or directory not found
echo \-------------------------------------------------------------------
echo Step 1: Finding required files and directories...
echo \-------------------------------------------------------------------

# - Find required files within report directory: ----------------------------
annotation_dir=$(find -maxdepth 1 -type d -iname "annotation")
dir_exists "$annotation_dir" "Annotation"

#multiqc_data_dir=$(find -maxdepth 1 -type d -iname "ChipSeq.*.multiqc_data")
# TMP: Until ATAC-seq updated with deeptools
multiqc_data_dir=$(find -maxdepth 1 -type d -iname "ChipSeq.chipseq.multiqc_data")
dir_exists "$multiqc_data_dir" "MultiQC data"

# multiqc_html=$(find -maxdepth 1 -type f -iname "ChipSeq.*.multiqc.html")
# TMP: Until ATAC-seq updated with deeptools, use multiQC report produced by chipseq option
multiqc_html=$(find -maxdepth 1 -type f -iname "ChipSeq.chipseq.multiqc.html")
file_exists "$multiqc_html" "MultiQC HTML"

homer_html_list=$(find -maxdepth 1 -type f -iname "ChipSeq.homer_find_motifs_genome.md")
if [[ "$seq_type" == "chipseq" ]]; then # For ChIP-seq: Not mandatory - no peak annotation if no narrow peak mark are used
  if [[ -z "$homer_html_list" ]]; then
    homer_html_list="No HOMER known motif results"
  fi
elif [[ "$seq_type" == "atacseq" ]]; then
  file_exists "$homer_html_list" "ChipSeq.homer_find_motifs_genome.md"
fi

graphs_dir=$(find -maxdepth 1 -type d -iname "graphs")
dir_exists "$graphs_dir" "Graphs"

tracks_zip=$(find -maxdepth 1 -type f -iname "tracks.zip")
file_exists "$tracks_zip" "tracks.zip"

trim_readset=$(find -maxdepth 1 -type f -iname "trimReadsetTable.tsv")
file_exists "$trim_readset" "trimReadsetTable.tsv"

echo \- - In report directory \- - - - - - - - - - - - - - - - - - - - - -
echo "Annotation:                          $annotation_dir"
echo "MultiQC data:                        $multiqc_data_dir"
echo "MultiQC HTML:                        $multiqc_html"
echo "ChipSeq.homer_find_motifs_genome.md: $homer_html_list"
echo "Graphs directory:                    $graphs_dir"
echo "trimReadsetTable.tsv:                $trim_readset" $'\n'

# - Find required files outside of report directory: ------------------------
# Files be copied or symlinked to report directory in step 2

# Find read coverage file for PCA plot:
read_coverage=$(find "$results_dir/metrics/deeptools" -type f -iname "BamSummResults.npz.txt")
file_exists "$read_coverage" "BamSummResults.npz.txt"

# List bigWig files:
mapfile -d '' bigwig_files < <(find "$results_dir/tracks" -type f -iname "*.bw" -print0)
file_exists "${bigwig_files[@]}" "bigWig files"

# - Find files: ChIP-seq - - - - - - - - - - - - - - - - - - - - - - - - - -
if [[ "$seq_type" == "chipseq" ]]; then

  # TMP until IHEC metrics is fixed
  # Check that an IHEC metrics file for each sample exists (used in step 4):
  mapfile -d '' ihec_metrics_files < <(find "$results_dir/ihec_metrics" -type f -iname "IHEC_*_metrics.*.*.tsv" -print0)
  file_exists "${ihec_metrics_files[@]}" "IHEC metrics files for each sample"

  # List fingerprint plots for all samples (ihec_metrics: 1 plot per readset-input pair):
  mapfile -d '' fingerprint_plots < <(find "$results_dir/ihec_metrics" -type f -iname "*fingerprint.png" -print0)
  file_exists "${fingerprint_plots[@]}" "Fingerprint plot"

  # Verify that the right files were found (ChIP-seq):
  echo \- - Outside of report directory \- - - - - - - - - - - - - - - - - -
  echo "Config.trace.ini file found at: $ini_file"
  echo "Readset file found at:          $readset"
  echo "Read coverage file found at:    $read_coverage"
  echo IHEC metrics files for each sample found at:
  for sample_metrics in "${ihec_metrics_files[@]}"; do
    echo $'\t' "$sample_metrics"
  done
  echo Fingerprint plots found at:
  for fp_plot in "${fingerprint_plots[@]}"; do 
    echo $'\t' "$fp_plot"
  done
  echo bigWigs found at:
  for bigwig in "${bigwig_files[@]}"; do 
    echo $'\t' "$bigwig"
  done
  echo ""

# - Find files: ATAC-seq - - - - - - - - - - - - - - - - - - - - - - - - - - -
elif [[ "$seq_type" == "atacseq" ]]; then
  # TMP until IHEC metrics is fixed for ChIP-seq --> when fixed add this to common files section
  # Find IHEC metrics file:
  ihec_metrics=$(find "$results_dir/ihec_metrics" -type f -iname "IHEC_*_metrics_AllSamples.tsv")
  file_exists "$ihec_metrics" "IHEC metrics all samples"

  # List fingerprint plots for all samples (metrcis/deeptools: 1 plot for readsets of the same sample group):
  mapfile -d '' fingerprint_plots < <(find "$results_dir/metrics/deeptools" -type f -iname "*fingerprint.png" -print0)
  file_exists "${fingerprint_plots[@]}" "Fingerprint plot"

  # List insert size histograms for all samples:
  mapfile -d '' insert_size_plots < <(find "$results_dir/metrics" -type f -iname "*insert_size_histogram.pdf" -print0)
  file_exists "${insert_size_plots[@]}" "Insert size distribution plot"

  # Verify that the right files were found (ATAC-seq):
  echo \- - Outside of report directory \- - - - - - - - - - - - - - - - - - - -
  echo "Config.trace.ini file found at:      $ini_file"
  echo "Readset file found at:               $readset"
  echo "Read coverage file found at:         $read_coverage"
  echo "IHEC metrics file found at:          $ihec_metrics"
  echo Fingerprint plots found at:
  for fp_plot in "${fingerprint_plots[@]}"; do 
    echo $'\t' "$fp_plot"
  done
  echo Insert size distribution plots found at:
  for insert_plot in "${insert_size_plots[@]}"; do 
    echo $'\t' "$insert_plot"
  done
  echo bigWigs found at:
  for bigwig in "${bigwig_files[@]}"; do 
    echo $'\t' "$bigwig"
  done
  echo ""

fi

## (2) Copy files needed to generate report into report directory ######################################################### (2) ###
echo \-------------------------------------------------------------------
echo Step 2: Copying files to report directory...
echo \-------------------------------------------------------------------

  mkdir "$report_dir/graphs/fingerprint_plots"
  for fp_plot in "${fingerprint_plots[@]}"; do
    cp "$fp_plot" "$graphs_dir/fingerprint_plots"
  done \
  && { echo "Fingerprint plots copied to graphs directory"; } \
  || { echo "Failed to copy fingerprint plots to graphs directory. Exiting"; exit 1; }

  cp {"$ini_file","$readset","$read_coverage"} "$copied2report_dir" && cp -r "$img_dir" "$copied2report_dir" \
    && { echo "Required files (ini, readset, read coverage and report images) copied to copied2report directory" $'\n'; } \
    || { echo "Failed to copy required files to copied2report directory. Exiting"; exit 1; }

# - Copy ATAC-seq specific files -----------------------------------------
if [[ "$seq_type" == "atacseq" ]]; then

  # TMP until IHEC metrics is fixed for ChIP-seq --> when fixed add this to common files section
  # Copy IHEC metrics: - - - - - - - - - - - - - - - 
  cp "$ihec_metrics" "$report_dir" \
  && { echo "IHEC metrics (all samples) copied to report directory"; } \
  || { echo "Failed to copy ihec metrics to report directory. Exiting"; exit 1; }

  # Re-assign ihec_metrics variable to the copy in report_dir (used later for tar)
  ihec_metrics=$(find -maxdepth 1 -type f -iname "IHEC_*_metrics_AllSamples.tsv")
  file_exists "$ihec_metrics" "IHEC metrics all samples"
  # - - - - - - - - - - - - - - - - - - - - - - - - -

  # Copy insert size plots: - - - - - - - - - - - - -
  mkdir "$graphs_dir/insert_size_plots"
  for insert_plot in "${insert_size_plots[@]}"; do
    cp "$insert_plot" "$graphs_dir/insert_size_plots"
  done \
  && { echo "Insert size plots copied to graphs directory" $'\n'; } \
  || { echo "Failed to copy insert size plots to graphs directory. Exiting"; exit 1; }

  # Convert insert size plot example PDF to PNG
  echo "Converting insert size example plot from pdf to png..."
  insert_size_example_pdf="${insert_size_plots[0]}"
  insert_size_example_png="$(basename "$insert_size_example_pdf" .pdf).png"

  gs -dSAFER -dBATCH -dNOPAUSE \
    -sDEVICE=pngalpha \
    -r300 -sOutputFile="$copied2report_dir/$insert_size_example_png" \
    "$insert_size_example_pdf" \
    && { echo $'\n'"Insert size plot PDF converted to PNG ($insert_size_example_png saved to copied2report)" $'\n'; } \
    || { echo "Failed convert insert size PDF to PNG. Exiting"; exit 1; }
  # - - - - - - - - - - - - - - - - - - - - - - - - -

fi

### (3) Add bigWig files to report directory ############################################################################### (3) ###
echo \-------------------------------------------------------------------
echo Step 3: Creating tracks_bigWigs.zip...
echo \-------------------------------------------------------------------

# Initialize tracks_bigWigs directory:
bigwigs_dir="$report_dir/tracks_bigWigs"
mkdir "$bigwigs_dir"

# Organize files by sample & create symbolic link to bigWig files:
for bigwig in "${bigwig_files[@]}"; do
  sample=$(echo "$bigwig" | sed -E 's|.*/tracks/([^/]+)/.*|\1|')
  mkdir -pv "$bigwigs_dir/$sample"
  ln -s "$bigwig" "$bigwigs_dir/$sample"
done

# Zip tracks_bigWigs directory:
zip -rv tracks_bigWigs.zip $(basename "$bigwigs_dir") \
  && { echo $'\n'"tracks_bigWigs.zip created within report directory" $'\n'; } \
  || { echo "Failed to create tracks_bigWigs.zip. Exiting"; exit 1; }

bigwig_zip=$(find -type f -iname "tracks_bigWigs.zip")

### (4) Fix IHEC Metrics Table (ChIP-seq only) ############################################################################## (4) ###
echo \-------------------------------------------------------------------
echo Step 4: Fixing IHEC metrics table...
echo \-------------------------------------------------------------------

# R commands below are run from the report_dir (current dir) and finds files within ../ihec_metrics
# TMP: Outputs a fixed IHEC metrics table to report_dir
# TMP until IHEC metrics is fixed for ChIP-seq --> when fixed remove this section entirely and fix find/copy files sections accordingly

# - Fix IHEC metrics: ChIP-seq -------------------------------------------
if [[ "$seq_type" == "chipseq" ]]; then
  R --no-restore --no-save <<EOF
## Load
library(magrittr)
library(tidyverse)

## Essentials for loop:
# Find all ihec metrics files
ihec_metrics_all <- list.files(path = "../ihec_metrics", pattern = "^IHEC_.*_metrics", all.files=TRUE, full.names=TRUE, recursive=TRUE)

# Keep only those for individual samples (remove file for all samples)"
ihec_metrics_samples <- ihec_metrics_all[!grepl("IHEC_.*_metrics_AllSamples.tsv", ihec_metrics_all)]

# Initialize new AllSamples ihec metrics df:
merge <- NULL

## LOOP: Iterate through ihec metrics for each sample:
for(i in ihec_metrics_samples){
  
  ## Get lists
  colnames <- read_tsv(i, show_col_types = F) %>% colnames()
  
  x1 <- read_tsv(i, show_col_types = F) %>%
    slice(1) %>% 
    flatten_chr()
  x1 <- x1[1:33]
  
  x2 <- read_tsv(i, show_col_types = F) %>%
    slice(2) %>% 
    flatten_chr()
  x2 <- x2[2:3]
  
  x3 <- read_tsv(i, show_col_types = F) %>%
    slice(3) %>% 
    flatten_chr()
  x3 <- x3[2:6]
  
  ## Remake table
  x <- NULL
  x <- rbind(c(x1, x2, x3)) %>%
    as.data.frame() %>%
    set_colnames(colnames)
  
  ## Merge sample data to AllSamples df
  merge <- bind_rows(merge, x)
  
  rm(x, x1, x2, x3, colnames)
}

## write out merge
write_tsv(merge, "IHEC_chipseq_metrics_AllSamples.tsv")

rm(merge)

q()
EOF

  ihec_metrics=$(find -maxdepth 1 -type f -name "IHEC_chipseq_metrics_AllSamples.tsv") \
    && { echo $'\n'"IHEC metrics table created in report directory" $'\n'; } \
    || { echo "Failed to create IHEC_chipseq_metrics_AllSamples.tsv in report directory. Exiting"; exit 1; }

# - IHEC metrics already fixed: ATAC-seq ---------------------------------
elif [[ "$seq_type" == "atacseq" ]]; then
  echo "IHEC metrics (all samples) already OK, copied to report directory in previous step" $'\n'
fi

### (5) Generate read coverage PCA plot #################################################################################### (5) ###
echo \-------------------------------------------------------------------
echo Step 5: Generating read coverage PCA plots...
echo \-------------------------------------------------------------------

# List of labels (label format: Sample.MarkName):
mapfile -t label_list < <(awk -F'\t' '
  NR == 1 {
    for (i = 1; i <= NF; i++) {
      if ($i == "Sample") sample_col = i
      if ($i == "MarkName") mark_col = i
    }
    next
  }
  {
    label = $sample_col "." $mark_col
    if (!seen[label]++) {
      print label
    }
  }
  ' "$readset")

echo "${label_list[@]}"

# Extract list of unique mark names from label list:
mapfile -t markname_list < <(
  printf '%s\n' "${label_list[@]}" |
  awk -F'.' '{print $2}' |
  sort -u
)

# List of possible markers (shapes):
all_markers=("o" "v" "s" "D" "p" "X" "h" "P" "^" "d" "." "<" ">" "*") #14 different shapes

# Assign a different marker to each mark name:
declare -A markname_marker
marker_list_index=0

for markname in "${markname_list[@]}"; do
  if [[ "$marker_list_index" -le 13 ]]; then
    markname_marker+=(["$markname"]="${all_markers[$marker_list_index]}")
    echo "${markname_marker[${markname}]}":"$markname"
    ((marker_list_index++))
  else # For over 14 unique marks
    marker_list_index=0
    markname_marker+=(["$markname"]="${all_markers[$marker_list_index]}")
    ((marker_list_index++))
  fi
done

# Create a list of markers based on the label list:
marker_list=()
for label in "${label_list[@]}"; do
  for markname in ${!markname_marker[@]}; do
      if [[ "$label" == *"$markname" ]]; then
        marker_list+=("${markname_marker[${markname}]}")
        break
      fi
    done
done

# Create PCA plot PDF
plotPCA -in "$read_coverage" -o "$graphs_dir/read_coverage_pca_testtest.pdf" -l "${label_list[@]}" --markers "${marker_list[@]}" -T "Read coverage PCA"\
  && { echo $'\n'"PDF format read coverage PCA plot created in graphs directory"; } || { echo "Failed to create read coverage PCA plot"; exit 1; }

# Create PCA plot PNG
plotPCA -in "$read_coverage" -o "$graphs_dir/read_coverage_pca.png" -l "${label_list[@]}" --markers "${marker_list[@]}" -T "Read coverage PCA"\
  && { echo "PNG format read coverage PCA plot PNG created in graphs directory" $'\n'; } || { echo "Failed to create read coverage PC plot"; exit 1; }

### (6) Generate client report directory tree ############################################################################# (6) ###
echo \-------------------------------------------------------------------
echo Step 6: Generating tree...
echo \-------------------------------------------------------------------
# Create a tree excluding everything in the report directory that isn't within the tree_include list

# Include the following files in the tree:
tree_include=(
  $(basename "$annotation_dir") \
  $(basename "$bigwig_zip") \
  $(basename "$graphs_dir") \
  $(basename "$ihec_metrics") \
  $(basename "$multiqc_html") \
  $(basename "$trim_readset") \
  )

# Get all immediate files and subdirectories within report_dir:
report_dir_all=($(find -maxdepth 1 -mindepth 1 -printf "%f\n"))

# Get a list of files and directories to exclude from the tree:
tree_exclude=()

for item in "${report_dir_all[@]}"; do
    exclude_from_tree=true 
    for item2include in "${tree_include[@]}"; do
        if [[ "$item" == "$item2include" ]]; then
            exclude_from_tree=false
            break
        fi
    done
    if $exclude_from_tree; then
        tree_exclude+=("$item")
    fi
done

# Join items from tree_exclude in tree_ignore with "|"
tree_ignore=$(IFS="|"; echo "${tree_exclude[*]}")

# Generate tree: 
tree \
  "$report_dir" \
  -I ""$tree_ignore"|*Misc_Graphs*|*QC_Metrics*|fingerprint_plots|read_coverage*|*tree*|insert_size_plots" \
  -L 2 \
  > "$report_dir/tree.txt" \
  && { echo "tree.txt created in report directory" $'\n'; } \
  || { echo "Failed to create tree.txt"; exit 1; }

### (7) Generate HTML report ############################################################################################### (7) ###
echo \-------------------------------------------------------------------
echo Step 7: Rendering report Rmd into html...
echo \-------------------------------------------------------------------

Rscript - <<EOF
rmarkdown::render(
  input = "$rmd",
  output_dir = "$report_dir",
  knit_root_dir = "$report_dir",
  output_options = list(self_contained = TRUE),
  params = list(
    project_id = "$project_id",
    primary_contact = "$primary_contact",
    project_start_date = "$start_date",
    readset_name = "$readset_name",
    peak_annotations_tab = "$peak_annotations_rmd"
  )
)
EOF

report_html=$(find -maxdepth 1 -type f -name "${rmd_name%.Rmd}.html") \
  && { echo $'\n'"Report HTML created at: "${rmd_name%.Rmd}.html"" $'\n'; } \
  || { echo "Failed to create report html"; exit 1; }

### (8) Compress client report directory ################################################################################### (8) ###
echo \-------------------------------------------------------------------
echo Step 8: Creating archive file...
echo \-------------------------------------------------------------------

tar -czvf "$results_compressed" \
  "$annotation_dir" \
  "$bigwig_zip" \
  "$graphs_dir" \
  "$ihec_metrics" \
  "$multiqc_html" \
  "$report_html" \
  "$trim_readset" \
  && { echo $'\n'"Archive file "$results_compressed" created" $'\n'; } \
  || { echo "Failed to create archive file $results_compressed"; exit 1; }

echo \-------------------------------------------------------------------
echo Complete!
echo Find "$results_compressed" in the report directory
echo \-------------------------------------------------------------------
