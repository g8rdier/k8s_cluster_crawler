#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Logging function (depending on the logging flag)
log() {
    local level="$1"
    local message="$2"
    if [ "$DETAILLIERTES_LOGGING" = true ]; then
        echo "$level: $message"
    elif [ "$level" != "DEBUG" ]; then
        echo "$level: $message"
    fi
}

# Standard logging level
DETAILLIERTES_LOGGING=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dl) DETAILLIERTES_LOGGING=true ;;  # Enable detailed logging
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Script to collect data from all clusters
UNSERE_CLUSTER="fttc ftctl"

# Marker file to track if the script has already run successfully
MARKER_FILE="$(dirname "$0")/cluster_crawler_marker"

# Determine if FORCE_REBUILD should be set
if [ -f "$MARKER_FILE" ]; then
    FORCE_REBUILD=0
else
    FORCE_REBUILD=1
fi

# Function to create a directory if it doesn't exist
create_directory() {
    locDir="${1}"
    if [ ! -d "${locDir}" ]; then
        mkdir -p "${locDir}" > /dev/null
    fi
    if [ ! -d "${locDir}" ]; then
        log "ERROR" "Error creating directory '${locDir}'"
        return 1
    fi
    return 0
}

# Function to set the Kubernetes context for a given cluster
set_kube_context() {
    if kubectl config use-context "$1"; then
        log "INFO" "Successfully switched to context ${1}"
        return 0
    else
        log "ERROR" "Error switching to context ${1}"
        return 1
    fi
}

# Temporary directory
DAYSTAMP="$(date +"%Y%m%d")"

# Set up the info cache directory
INFO_CACHE="info_cache_${DAYSTAMP}"

if ! create_directory "${INFO_CACHE}"; then
    exit 1
fi

if [ "${FORCE_REBUILD}" == "1" ]; then
    log "INFO" "FORCE_REBUILD is set to 1, updating all cached cluster information"
    rm -rf "${INFO_CACHE:?}"/* > /dev/null 2>&1 || true
else
    log "INFO" "FORCE_REBUILD is not set to 1, using cached cluster information"
fi

# Function for error logging and debugging
debug_crawler_error() {
    pwd
    ls -al
    ls -al "${INFO_CACHE}"
}

# NAMEID Scraper: Retrieve and save name-ID mapping for all clusters
NAMEID_MAP="scripts/docs/name_id.map"

if [ -f "${NAMEID_MAP}" ]; then
    log "INFO" "Static name_id.map file found. Using the file for cluster information."
else
    log "ERROR" "Static name_id.map file not found! Please check."
    debug_crawler_error
    exit 1
fi

# New section: Rename contexts in kubeconfig files to ensure uniqueness
# Assuming that your kubeconfig files are located in /tmp/kubeconfigs
# and are already decoded and saved there

# Directory containing individual kubeconfig files
KUBECONFIGS_DIR="/tmp/kubeconfigs"

# Check if the directory exists
if [ -d "$KUBECONFIGS_DIR" ]; then
    log "INFO" "Renaming contexts in kubeconfig files to ensure uniqueness"

    for file in "$KUBECONFIGS_DIR"/*; do
        # Extract cluster name from filename and replace underscores with hyphens
        cluster_name=$(basename "$file" | sed 's/_kubeconfig//' | tr '_' '-')
        export KUBECONFIG="$file"
        current_context=$(kubectl config current-context)
        if [ "$current_context" != "$cluster_name" ]; then
            kubectl config rename-context "$current_context" "$cluster_name"
            log "DEBUG" "Renamed context '$current_context' to '$cluster_name' in file '$file'"
        fi
    done

    # Merge all kubeconfig files into a single file
    export KUBECONFIG=$(find "$KUBECONFIGS_DIR" -type f -exec printf '{}:' \;)
    kubectl config view --flatten > /tmp/merged_kubeconfig
    export KUBECONFIG=/tmp/merged_kubeconfig

    # Verify contexts
    log "INFO" "Available contexts after merging kubeconfigs:"
    kubectl config get-contexts
else
    log "WARNING" "Kubeconfigs directory '$KUBECONFIGS_DIR' not found. Skipping context renaming."
fi

# Build a mapping from cluster names to context names
log "INFO" "Building cluster to context mapping"

declare -A cluster_context_map

available_contexts=$(kubectl config get-contexts -o name)

for context in $available_contexts; do
    # Get the cluster associated with the context
    cluster_info=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$context')].context.cluster}")
    # Get the server URL
    server_url=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$cluster_info')].cluster.server}")

    # Extract the cluster name from the context name
    cluster_name_from_context="$context"

    # Map cluster name to context
    cluster_context_map["$cluster_name_from_context"]="$context"

    log "DEBUG" "Mapped cluster '$cluster_name_from_context' to context '$context'"
done

# Kubernetes Data Collector: Retrieve and save Kubernetes information (pods and ingress) for each cluster
while IFS=";" read -r CLSTRNM _CLSTRID; do
    log "DEBUG" "Processing cluster '${CLSTRNM}'"

    # Get the context name for this cluster
    context="${cluster_context_map[$CLSTRNM]}"

    if [ -z "$context" ]; then
        log "WARNING" "No matching context found for cluster '${CLSTRNM}', skipping..."
        continue
    fi

    log "INFO" "Using context '$context' for cluster '${CLSTRNM}'"

    # Define file paths for saving cluster information
    CLSTR_PODS="${INFO_CACHE}/${CLSTRNM}_pods.json"
    CLSTR_INGRESS="${INFO_CACHE}/${CLSTRNM}_ingress.json"

    if ! set_kube_context "$context"; then
        log "ERROR" "Error setting kube context for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    KUBE_VERSION=$(kubectl version --output=json | jq -r '.serverVersion.gitVersion')

    if ! kubectl get pods -A -o json | jq --arg k8s_version "$KUBE_VERSION" '.items |= map(. + {kubernetesVersion: $k8s_version})' > "${CLSTR_PODS}"; then
        log "ERROR" "Error fetching pods for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    else
        log "INFO" "Pod data for cluster '${CLSTRNM}' saved successfully"
    fi

    if ! kubectl get ingress -A -o json > "${CLSTR_INGRESS}"; then
        log "ERROR" "Error fetching ingress for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    else
        log "INFO" "Ingress data for cluster '${CLSTRNM}' saved successfully"
    fi
done < "${NAMEID_MAP}"

# Show contents of the info cache directory
log "INFO" "Contents of directory ${INFO_CACHE}:"
ls -l "${INFO_CACHE}"

# Define the path to the Python script
PYTHON_PARSER_PATH="scripts/parser.py"
INPUT_DIR="${INFO_CACHE}"
OUTPUT_DIR="${INFO_CACHE}"

# Run the Python parser
python3 "$PYTHON_PARSER_PATH" -dl --input_dir "$INPUT_DIR" --output_dir "$OUTPUT_DIR"

# Git token and repository configuration
GIT_REPO_URL="https://gitlab-ci-token:${PUSH_BOM_PAGES}@git.f-i-ts.de/devops-services/toolchain/docs.git"

echo "oauth: '[MASKED]'"

# Clone the repository into a temporary directory
REPO_DIR="/tmp/docs-repo"
if [ ! -d "${REPO_DIR}" ]; then
    git clone "${GIT_REPO_URL}" "${REPO_DIR}"
else
    # Pull the latest changes if the repository already exists
    cd "${REPO_DIR}" || exit
    git pull origin main
    cd - || exit
fi

# Set paths within the repository
INGRESS_PATH="${REPO_DIR}/boms/k8s/ingress"
PODS_PATH="${REPO_DIR}/boms/k8s/pods"

# Create target directories in the repository
create_directory "${INGRESS_PATH}"
create_directory "${PODS_PATH}"

# Copy the new data into the repository directory
if ! cp -r "${INFO_CACHE}"/*_ingress.md "${INGRESS_PATH}/"; then
    log "ERROR" "Error copying ingress files"
    exit 1
else
    log "INFO" "Ingress files copied successfully"
fi

if ! cp -r "${INFO_CACHE}"/*_pods.md "${PODS_PATH}/"; then
    log "ERROR" "Error copying pods files"
    exit 1
else
    log "INFO" "Pods files copied successfully"
fi

# Configure Git with a generic user
cd "${REPO_DIR}" || exit
git config user.email "ci@f-i-ts.de"
git config user.name "Cluster Crawler"

# Pull the latest changes
git pull origin main

# Stage all changes
git add -A

# Commit and push if there are changes
if ! git diff --cached --quiet; then
    git commit -m "Automatisches Update der Cluster-Daten am $(date)"
    git push origin main
else
    echo "No changes to commit."
fi
exit 0
