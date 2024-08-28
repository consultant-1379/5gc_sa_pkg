#!/usr/bin/env bash


help()
{
    echo "This script can get panels id from Grafana json files of given path."
    echo "Example: get_id.sh ~/5gc_sa_pkg/lab/grafana "
    exit 1
}

while getopts 'p:h' OPT; do
    case $OPT in
        p) path="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done

# Output directory for text files (current working directory)
output_directory="$(pwd)"

# Function to check if a panel should be included (based on the absence of 'collapsed' key)
should_include_panel() {
    # Check if 'collapsed' key does not exist
    jq 'has("collapsed") | not' <<< "$1" > /dev/null
    return $?
}
for json_file in "$path"/*.json; do
    if [ -e "$json_file" ]; then
        echo "Processing: $json_file"
        # Extract the filename without extension (for output file name)
        filename=$(basename "$json_file" .json)
        output_file="${output_directory}/${filename}_ids.txt"  # Specify the output file path
        jq '.panels[] | select(.type == "timeseries") | .id' "$json_file" > "$output_file"
        jq '.panels[] | select(.type != "timeseries") |.panels[] | select(.type == "timeseries")| .id' "$json_file" >> "$output_file"
        echo "IDs saved to: $output_file"
    else
        echo "File not found: $json_file"
    fi
done
