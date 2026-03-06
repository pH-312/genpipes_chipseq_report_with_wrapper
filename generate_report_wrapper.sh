#!/bin/bash

### WORKING DIRECTORY SETUP #######################################################################################################
# Check that script is running in the correct directory (report):
if [ "$(basename "$(pwd)")" != "report" ]; then
    echo "Error: Running script from the incorrect directory." 
    echo "Please run from the GenPipes output report directory." 
    echo "Exiting."
    exit 1
fi

report_dir="$(pwd)" # GenPipes report directory
results_dir="$(dirname "$report_dir")" # GenPipes results directory

### FUNCTIONS ######################################################################################################################

find_default_ini () {
  ini_file=$(find "$results_dir" -maxdepth 1 -type f -iname "ChipSeq*.config.trace.ini" -printf "%p\n" | sort -nr | head -n 1)
}

find_specific_ini () {
  ini_file=$(find "$results_dir" -maxdepth 1 -type f -iname "$ini_name")
}

extract_readset_name () {
  genpipes_command=$(grep "^# Command:" "$ini_file")
  readset_name=$(basename "$(echo "$genpipes_command" | sed -E 's/.*-r[=[:space:]]*([^[:space:]]+).*/\1/')")
}

find_readset () {
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
}

get_ini_start_date () {
  start_date=$(sed -n 's/^# Created on: \([0-9\-]*\)T.*/\1/p' "$ini_file")
}

### PROMPT USER FOR INPUTS #######################################################################################################
# Inputs passed as arguments to generate_report_6.1.sh

# ARGUMENT 1: Project ID (mandatory) -------------------------------------------
read -p $'\n'"Enter the Project ID: " project_id
while [[ -z "$project_id" ]]; do
    echo $'\n'"Project ID not provided."
    read -p "Enter the Project ID: " project_id
done

# ARGUMENT 2: Primary Contact (mandatory) --------------------------------------
read -p $'\n'"Enter the Primary Contact: " primary_contact
while [[ -z "$primary_contact" ]]; do
    echo $'\n'"Project ID not provided."
    read -p "Enter the Primary Contact: " primary_contact
done

# ARGUMENT 3: Sequencing type (mandatory) ---------------------------------------
read -p $'\n'"Enter the sequencing type ([1] chipseq or [2] atacseq): " seq_type

# Check input:
while [[ "$seq_type" != "1" && "$seq_type" != "2" ]]; do
  echo $'\n'"Invalid input for sequencing type."
  read -p "Enter [1] for chipseq or [2] for atacseq): " seq_type
done

# Define R Markdown report to render and output file name:
if [[ "$seq_type" == "1" ]]; then
  seq_type="chipseq"
  rmd_name="ChIP-seq_Report_wrapper.html"
  results_compressed="GenPipes_ChIP-seq_Results.tar.gz"
elif [[ "$seq_type" == "2" ]]; then
  seq_type="atacseq"
  rmd_name="ATAC-seq_Report_wrapper.html"
  results_compressed="GenPipes_ATAC-seq_Results.tar.gz"
fi

# ------------------------------------------------------------------------------
### PROCEED WITH DEFAULT INI, READSET AND START DATE? ###
echo $'\n'"By default, generate_report_6.1.sh uses the most recent config.trace.ini file in a GenPipes output."
echo "This file is used to extract information such as the project start date, the name of the readset file used and the module versions used."

echo $'\n'"Proceed with default settings?"
read -p "To proceed with the default settings enter [1]. To specify any of the parameters above [2]: " use_default
while [[ "$use_default" != "1" && "$use_default" != "2" ]]; do
  echo $'\n'"Invalid input."
  echo "To use the most recent ini file and the readset file and start date specified in this ini file enter [1]."
  echo "To specify any of the above parameters enter [2]."
  read -p "Enter [1] to use default parameters or [2] to specify them: " use_default
done
# ------------------------------------------------------------------------------

if [[ "$use_default" == "1" ]]; then # Use default:
  find_default_ini && echo $'\n'"Using newest ini file '$ini_file'"
  extract_readset_name && find_readset && echo "Using readset from ini file '$readset'"
  get_ini_start_date && echo "Using start date from ini file $start_date"

elif [[ "$use_default" == "2" ]]; then # Prompt user for inputs:

  # ARGUMENT 4: Ini file to use (optional) ---------------------------------------
  read -p $'\n'"Specify a config.trace.ini file if needed, or press Enter to use the default (newest): " ini_name

  # Find ini file:
  while [[ -z "$ini_file" ]]; do
    if [[ -n "$ini_name" ]]; then
      find_specific_ini

      if [[ -z "${ini_file}" ]]; then
        echo $'\n'"'$ini_name' not found in the output directory '$results_dir'."
        read -p "Specify the file name of the config.trace.ini file found in GenPipes' output, or press Enter to use the newest one: " ini_name
      fi
    else
      find_default_ini
    fi
  done
  echo $'\n'"Using ini file '$ini_file'"

  # ARGUMENT 5: Readset file to use (optional) -----------------------------------
  echo $'\n'"By default, the readset file name is extracted from '$(basename $ini_file)'." 
  read -p "Specify a different readset file if needed, or press Enter to use the default: " readset_name

  # Find readset file:
  while [[ -z "$readset" ]]; do
    if [[ -n "$readset_name" ]]; then
      find_readset

      if [[ -z "${readset}" ]]; then
        echo $'\n'"$readset_name not found."
        read -p "Specify the readset file name, or press Enter to use the default one: " readset_name
      fi
    else
      extract_readset_name && find_readset
    fi
  done
  echo $'\n'"Using readset file '$readset'"

  # ARGUMENT 6: Project start date (optional) ------------------------------------
  echo $'\n'"By default, the project start date used in the report is extracted from '$(basename $ini_file)'."
  read -p "Specify a different date if needed, or press Enter to use the default: " start_date
  if [[ -z "$start_date" ]]; then
    get_ini_start_date
  fi
  echo $'\n'"Using start date $start_date"

fi 

### CHECK INPUTS #################################################################################################################
echo $'\n'"Before generating the client archive file and report please verify the following:"
echo "--------------------------------------------------------------------------"
echo "Project ID:             $project_id"
echo "Primary contact:        $primary_contact"
echo "Sequencing data type:   $seq_type"
echo "Project start date:     $start_date" $'\n'

echo "Ini file:               $ini_file"
echo "Readset file name:      $readset" $'\n'

echo "Report:                 $rmd_name" 
echo "Output archive file:    $results_compressed"
echo "--------------------------------------------------------------------------"

read -p $'\n'"Press Enter to submit generate_report_6.1.sh to SLURM..."

## PROMPT USER FOR INPUTS #######################################################################################################
sbatch /path_to/ReportingFigures/generate_report_6.1.sh \ # TO CHANGE DURING SET-UP
    "$project_id" \
    "$primary_contact" \
    "$seq_type" \
    "$ini_name" \
    "$readset_name" \
    "$start_date"
