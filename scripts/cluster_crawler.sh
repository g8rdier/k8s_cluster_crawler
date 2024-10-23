#!/bin/bash
set -euo pipefail  # Exit on error, treat unset variables as error, and handle pipeline failures

# Determine the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging function with timestamps
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    if [ "${DETAILLIERTES_LOGGING:-false}" = true ]; then
        echo "$timestamp [$level]: $message"
    elif [ "$level" != "DEBUG" ]; then
        echo "$timestamp [$level]: $message"
    fi
}

DETAILLIERTES_LOGGING=false  # Default logging level
NO_COMMIT=false  # Default commit flag

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dl) DETAILLIERTES_LOGGING=true ;;
        --no-commit) NO_COMMIT=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Define directory paths
REPO_DIR="/tmp/docs-repo"
INFO_CACHE="${SCRIPT_DIR}/info_cache_$(date +"%Y%m%d")"
INGRESS_PATH="${REPO_DIR}/boms/k8s/ingress"
PODS_PATH="${REPO_DIR}/boms/k8s/pods"

# Function to create a directory if it doesn't exist
create_directory() {
    local locDir="$1"
    if [ ! -d "$locDir" ]; then
        mkdir -p "$locDir"
    fi
}

# Function to switch contexts and add context listing for debugging
set_kube_context() {
    local cluster="$1"
    log "INFO" "Switching context for cluster '$cluster'"

    # List available contexts before attempting to switch
    log "INFO" "Available contexts:"
    kubectl config get-contexts || { log "ERROR" "Failed to list available contexts"; exit 1; }

    for ((i=1; i<=3; i++)); do  # Retry 3 times if the context switch fails
        if kubectl config use-context "$cluster"; then
            log "INFO" "Switched to context '$cluster'"
            return 0
        else
            log "WARNING" "Error switching to context '$cluster', attempt $i/3"
            sleep 5
        fi
    done
    log "ERROR" "Failed to switch to context '$cluster'"
    return 1
}

# Function to verify files
verify_files() {
    local name_id_map="$1"
    local repo_dir="$2"
    missing_files=0
    
    while IFS=";" read -r CLSTRNM _CLSTRID; do
        [[ -z "$CLSTRNM" || "$CLSTRNM" =~ ^# ]] && continue
        PODS_MD_FILE="${repo_dir}/boms/k8s/pods/${CLSTRNM}_pods.md"
        INGRESS_MD_FILE="${repo_dir}/boms/k8s/ingress/${CLSTRNM}_ingress.md"
        
        if [ ! -f "$PODS_MD_FILE" ]; then
            log "ERROR" "Missing pod file for '$CLSTRNM'"
            missing_files=1
        fi
        if [ ! -f "$INGRESS_MD_FILE" ]; then
            log "ERROR" "Missing ingress file for '$CLSTRNM'"
            missing_files=1
        fi
    done < "$name_id_map"
    
    return $missing_files
}

# Function to collect data from Kubernetes and process it through the Python parser
collect_data() {
    local cluster="$1"
    local context="$2"
    
    set_kube_context "$context"
    
    log "INFO" "Collecting raw data for cluster '$cluster'"
    kubectl get pods -A -o json | python3 "${SCRIPT_DIR}/parser.py" --pods --output_file "${INFO_CACHE}/${cluster}_pods.md"
    kubectl get ingress -A -o json | python3 "${SCRIPT_DIR}/parser.py" --ingress --output_file "${INFO_CACHE}/${cluster}_ingress.md"
}

# Collect data and overwrite files
overwrite_files() {
    log "INFO" "Copying data files to repo and overwriting"
    
    cp -rf "${INFO_CACHE}"/*_pods.md "$PODS_PATH"
    cp -rf "${INFO_CACHE}"/*_ingress.md "$INGRESS_PATH"
    
    log "INFO" "Files copied successfully"
}

# Main logic
create_directory "$INFO_CACHE"
create_directory "$PODS_PATH"
create_directory "$INGRESS_PATH"
log "INFO" "Starting cluster crawler"

# Loop through the name_id.map
while IFS=";" read -r CLSTRNM CLSTRID; do
    [[ -z "$CLSTRNM" || "$CLSTRNM" =~ ^# ]] && continue
    collect_data "$CLSTRNM" "$CLSTRID"
done < "${SCRIPT_DIR}/docs/name_id.map"

overwrite_files

# Verification Step
if verify_files "${SCRIPT_DIR}/docs/name_id.map" "$REPO_DIR"; then
    log "INFO" "All expected files are present."
else
    log "ERROR" "Some files are missing after copying."
    exit 1
fi

# Git Operations
GIT_REPO_URL="https://gitlab-ci-token:${PUSH_BOM_PAGES}@git.f-i-ts.de/devops-services/toolchain/docs.git"
echo "oauth: '[MASKED]'"

if [ ! -d "$REPO_DIR" ]; then
    log "INFO" "Cloning repository into '${REPO_DIR}'"
    git clone "$GIT_REPO_URL" "$REPO_DIR" || { log "ERROR" "Failed to clone repository"; exit 1; }
else
    log "INFO" "Repository already cloned. Pulling latest changes."
    cd "$REPO_DIR" || { log "ERROR" "Failed to navigate to repository directory"; exit 1; }
    git pull origin main || { log "ERROR" "Failed to pull latest changes"; exit 1; }
    cd - || exit
fi

cd "$REPO_DIR" || { log "ERROR" "Failed to navigate to '${REPO_DIR}'"; exit 1; }
git config user.email "ci@f-i-ts.de"
git config user.name "Cluster Crawler"
git pull origin main || { log "ERROR" "Failed to pull latest changes"; exit 1; }

git add -A || { log "ERROR" "Failed to stage changes"; exit 1; }

if [ "$NO_COMMIT" = false ]; then
    git commit -am "Automatisches Update der Cluster-Daten am $(date)" || log "WARNING" "Nothing to commit, proceeding to push"
    git push origin main || { log "ERROR" "Failed to push changes"; exit 1; }
else
    log "INFO" "No-commit flag is set. Skipping git commit and push."
fi

log "INFO" "Cluster crawler finished successfully."
exit 0
