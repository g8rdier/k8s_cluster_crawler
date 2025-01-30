#!/bin/bash

# Default values
DRY_RUN=false
LOCAL_RUN=false

# Help function
show_help() {
    echo "Usage: $0 [-d] [-l]"
    echo "Options:"
    echo "  -d    Dry run (don't push to repository)"
    echo "  -l    Local run (use local kubectl context)"
    echo "  -h    Show this help message"
}

# Parse command line arguments
while getopts "dlh" opt; do
    case $opt in
        d) DRY_RUN=true ;;
        l) LOCAL_RUN=true ;;
        h) show_help; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_MAP="$SCRIPT_DIR/docs/cluster_map.yaml"

# Create necessary directories
mkdir -p "$SCRIPT_DIR/info_cache_$(date +%Y%m%d)"
mkdir -p "$SCRIPT_DIR/results/$(date +%Y%m%d)"

# Function to get cluster data
get_cluster_data() {
    local cluster_name=$1
    local cluster_id=$2
    local date_dir=$(date +%Y%m%d)
    local cache_dir="$SCRIPT_DIR/info_cache_$date_dir/$cluster_name"
    local results_dir="$SCRIPT_DIR/results/$date_dir"
    
    mkdir -p "$cache_dir"
    mkdir -p "$results_dir"

    if [ "$LOCAL_RUN" = true ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]: Using local kubectl context for $cluster_name"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]: Would authenticate to cluster $cluster_name ($cluster_id)"
    fi

    # Get pods and ingresses
    kubectl get pods -A -o json > "$cache_dir/pods.json"
    kubectl get ingress -A -o json > "$cache_dir/ingress.json"

    # Parse data
    python3 "$SCRIPT_DIR/parser.py" \
        "$cache_dir/pods.json" \
        "$cache_dir/ingress.json" \
        "$results_dir/${cluster_name}_status.md"
}

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]: FORCE_REBUILD is set to 1, updating all cached cluster information"

# Process each cluster from YAML
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([^:]+):[[:space:]]*$ ]]; then
        cluster_name="${BASH_REMATCH[1]}"
        cluster_id=$(yq ".clusters.$cluster_name.uuid" "$CLUSTER_MAP")
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]: Processing cluster: $cluster_name ($cluster_id)"
        get_cluster_data "$cluster_name" "$cluster_id"
    fi
done < <(yq '.clusters | keys | .[]' "$CLUSTER_MAP")

# Push results if not dry run
if [ "$DRY_RUN" = false ]; then
    current_date=$(date +"%Y-%m-%d %H:%M:%S")
    git add "$SCRIPT_DIR/results"
    git commit -m "Update cluster status: $current_date"
    git push
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]: Crawler completed successfully!"
