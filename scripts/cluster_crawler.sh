#!/bin/bash
set -euo pipefail  # Exit on error, treat unset variables as error, and handle pipeline failures

# Set the timezone to Europe/Berlin
export TZ="Europe/Berlin"

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

# Standard logging level is not detailed unless passed as an argument
DETAILLIERTES_LOGGING=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dl) DETAILLIERTES_LOGGING=true ;;  # Enable detailed logging
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Set FORCE_REBUILD to 1 to ensure rebuild each time
FORCE_REBUILD=1

# Function to create a directory if it doesn't exist
create_directory() {
    local locDir="${1}"
    if [ ! -d "${locDir}" ]; then
        mkdir -p "${locDir}"
    fi
    if [ ! -d "${locDir}" ]; then
        log "ERROR" "Error creating directory '${locDir}'"
        return 1
    fi
    return 0
}

# Function to set the Kubernetes context for a given cluster with retries and checks
set_kube_context() {
    local cluster="$1"
    local RETRIES=3
    log "INFO" "Setting context for cluster '$cluster'"

    # Output available contexts and current context before the switch
    log "INFO" "Available contexts before switch:"
    kubectl config get-contexts || { log "ERROR" "Failed to get contexts"; exit 1; }
    current_context=$(kubectl config current-context 2>/dev/null || true)
    log "INFO" "Current context before switch: '${current_context}'"

    # Retry logic for switching to the desired context
    for ((i=1; i<=RETRIES; i++)); do
        if kubectl config use-context "$cluster"; then
            log "INFO" "Successfully switched to context '$cluster'"
            # Output available contexts and current context after the switch
            log "INFO" "Available contexts after switch:"
            kubectl config get-contexts || { log "ERROR" "Failed to get contexts"; exit 1; }
            current_context=$(kubectl config current-context)
            log "INFO" "Current context after switch: '${current_context}'"
            return 0
        else
            log "WARNING" "Error switching to context '$cluster', attempt $i/$RETRIES"
            sleep 5
        fi
    done
    log "ERROR" "Failed to switch to context '$cluster' after $RETRIES attempts"
    return 1
}

# Temporary directory
DAYSTAMP="$(date +"%Y%m%d")"

# Set up the info cache directory
INFO_CACHE="${SCRIPT_DIR}/info_cache_${DAYSTAMP}"

if ! create_directory "${INFO_CACHE}"; then
    exit 1
fi

# Rebuild cache if needed
log "INFO" "FORCE_REBUILD is set to 1, updating all cached cluster information"
rm -rf "${INFO_CACHE:?}"/* > /dev/null 2>&1 || true

# NAMEID Scraper: Retrieve and save name-ID mapping for all clusters
NAMEID_MAP="${SCRIPT_DIR}/docs/name_id.map"

if [ -f "${NAMEID_MAP}" ]; then
    log "INFO" "Static name_id.map file found. Using the file for cluster information."
else
    log "ERROR" "Static name_id.map file not found! Please check."
    exit 1
fi

# Log the contents of name_id.map for verification
log "INFO" "Contents of ${NAMEID_MAP}:"
cat "${NAMEID_MAP}" || { log "ERROR" "Failed to read ${NAMEID_MAP}"; exit 1; }

# New section: Rename contexts, users, and clusters in kubeconfig files to ensure uniqueness
KUBECONFIGS_DIR="/tmp/kubeconfigs"

if [ -d "$KUBECONFIGS_DIR" ]; then
    log "INFO" "Renaming contexts, users, and clusters in kubeconfig files to ensure uniqueness"

    for file in "$KUBECONFIGS_DIR"/*; do
        cluster_name=$(basename "$file" | sed 's/_kubeconfig//' | tr '_' '-')
        log "INFO" "Processing file '$file' with cluster name '$cluster_name'"

        # Define new names
        new_context_name="$cluster_name"
        new_user_name="${cluster_name}-user"
        new_cluster_name="${cluster_name}-cluster"

        # Use yq to rename context, user, and cluster
        yq e "(.contexts[0].name) = \"$new_context_name\"" -i "$file" || { log "ERROR" "Failed to rename context in '$file'"; exit 1; }
        yq e "(.contexts[0].context.user) = \"$new_user_name\"" -i "$file" || { log "ERROR" "Failed to rename user in '$file'"; exit 1; }
        yq e "(.contexts[0].context.cluster) = \"$new_cluster_name\"" -i "$file" || { log "ERROR" "Failed to rename cluster in '$file'"; exit 1; }

        yq e "(.users[0].name) = \"$new_user_name\"" -i "$file" || { log "ERROR" "Failed to rename user in '$file'"; exit 1; }
        yq e "(.clusters[0].name) = \"$new_cluster_name\"" -i "$file" || { log "ERROR" "Failed to rename cluster in '$file'"; exit 1; }

        # Update current-context
        yq e ".\"current-context\" = \"$new_context_name\"" -i "$file" || { log "ERROR" "Failed to update current-context in '$file'"; exit 1; }

        log "INFO" "Renamed context, user, and cluster in file '$file' to '$new_context_name', '$new_user_name', and '$new_cluster_name'"
    done

    # Merge all kubeconfig files into a single file
    log "INFO" "Merging kubeconfig files"
    export KUBECONFIG=$(find "$KUBECONFIGS_DIR" -type f -exec printf '{}:' \;)
    kubectl config view --flatten > /tmp/merged_kubeconfig || { log "ERROR" "Error flattening kubeconfig"; exit 1; }

    # Verify contexts after merging
    log "INFO" "Available contexts after merging kubeconfig files:"
    export KUBECONFIG="/tmp/merged_kubeconfig"
    kubectl config get-contexts || { log "ERROR" "Error retrieving contexts from merged kubeconfig"; exit 1; }

else
    log "ERROR" "Kubeconfig directory '$KUBECONFIGS_DIR' not found!"
    exit 1
fi

# Use the merged kubeconfig
export KUBECONFIG="/tmp/merged_kubeconfig"

# Build a mapping from cluster names to context names
log "INFO" "Building cluster to context mapping"

declare -A cluster_context_map

available_contexts=$(kubectl config get-contexts -o name)

for context in $available_contexts; do
    # The context name is the cluster name in this setup
    cluster_context_map["$context"]="$context"
    log "DEBUG" "Mapped cluster '$context' to context '$context'"
done

# Log the cluster to context mappings
log "INFO" "Cluster to Context Mapping:"
for key in "${!cluster_context_map[@]}"; do
    log "INFO" "Cluster: '$key' -> Context: '${cluster_context_map[$key]}'"
done

# Kubernetes Data Collector: Retrieve and save Kubernetes information (pods and ingress) for each cluster
while IFS=";" read -r CLSTRNM _CLSTRID; do
    # Skip empty lines and lines starting with #
    [[ -z "$CLSTRNM" || "$CLSTRNM" =~ ^# ]] && continue

    # Validation: Ensure both CLSTRNM and _CLSTRID are non-empty
    if [[ -z "$CLSTRNM" || -z "$_CLSTRID" ]]; then
        log "ERROR" "Invalid entry in name_id.map: '$CLSTRNM;$_CLSTRID'"
        exit 1
    fi

    log "INFO" "Processing cluster: '$CLSTRNM'"

    # Safely access the associative array with a default value
    context="${cluster_context_map[$CLSTRNM]:-}"

    if [ -z "$context" ]; then
        log "WARNING" "No matching context for cluster '$CLSTRNM', skipping..."
        continue
    fi

    log "INFO" "Using context: '$context' for cluster: '$CLSTRNM'"
    set_kube_context "$context" || { log "ERROR" "Failed to switch to context '$context'"; continue; }

    # Get the current timestamp
    CURRENT_TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

    # Fetch data for the cluster and directly pass to the parser
    log "INFO" "Fetching and parsing pod and ingress data for '$CLSTRNM'"

    # Define the output files
    PODS_MD_FILE="${INFO_CACHE}/${CLSTRNM}_pods.md"
    INGRESS_MD_FILE="${INFO_CACHE}/${CLSTRNM}_ingress.md"

    # Fetch pods and parse to Markdown
    log "INFO" "Fetching pods data for '$CLSTRNM'"
    if kubectl get pods -A -o json | python3 "${SCRIPT_DIR}/parser.py" --pods -dl --cluster_name "$CLSTRNM" --timestamp "$CURRENT_TIMESTAMP" --output_file "$PODS_MD_FILE"; then
        log "INFO" "Pod data for '$CLSTRNM' successfully written to '$PODS_MD_FILE'"
    else
        log "ERROR" "Failed to fetch or parse pods data for '$CLSTRNM'"
    fi

    # Fetch ingress and parse to Markdown
    log "INFO" "Fetching ingress data for '$CLSTRNM'"
    if kubectl get ingress -A -o json | python3 "${SCRIPT_DIR}/parser.py" --ingress -dl --cluster_name "$CLSTRNM" --timestamp "$CURRENT_TIMESTAMP" --output_file "$INGRESS_MD_FILE"; then
        log "INFO" "Ingress data for '$CLSTRNM' successfully written to '$INGRESS_MD_FILE'"
    else
        log "ERROR" "Failed to fetch or parse ingress data for '$CLSTRNM'"
    fi

done < "${NAMEID_MAP}"

# Show contents of the info cache directory
log "INFO" "Contents of directory '${INFO_CACHE}':"
ls -l "${INFO_CACHE}" || { log "ERROR" "Failed to list contents of '${INFO_CACHE}'"; exit 1; }

# --- Begin Git Operations Integration ---

# Git token and repository configuration
GIT_REPO_URL="https://gitlab-ci-token:${PUSH_BOM_PAGES}@git.f-i-ts.de/devops-services/toolchain/docs.git"

# Mask the Git token in the logs
echo "oauth: '[MASKED]'"

# Clone the repository into a temporary directory
REPO_DIR="/tmp/docs-repo"
if [ ! -d "${REPO_DIR}" ]; then
    log "INFO" "Cloning repository into '${REPO_DIR}'"
    git clone "${GIT_REPO_URL}" "${REPO_DIR}" || { log "ERROR" "Failed to clone repository"; exit 1; }
else
    log "INFO" "Repository already cloned. Pulling latest changes in '${REPO_DIR}'"
    cd "${REPO_DIR}" || { log "ERROR" "Failed to navigate to '${REPO_DIR}'"; exit 1; }
    git pull origin main || { log "ERROR" "Failed to pull latest changes"; exit 1; }
    cd - || exit
fi

# Set paths within the repository
INGRESS_PATH="${REPO_DIR}/boms/k8s/ingress"
PODS_PATH="${REPO_DIR}/boms/k8s/pods"

# Create target directories in the repository
create_directory "${INGRESS_PATH}" || { log "ERROR" "Failed to create directory '${INGRESS_PATH}'"; exit 1; }
create_directory "${PODS_PATH}" || { log "ERROR" "Failed to create directory '${PODS_PATH}'"; exit 1; }

# Copy the new data into the repository directory
log "INFO" "Copying ingress files to '${INGRESS_PATH}/'"
if cp -r "${INFO_CACHE}"/*_ingress.md "${INGRESS_PATH}/"; then
    log "INFO" "Ingress files copied successfully to '${INGRESS_PATH}/'"
else
    log "ERROR" "Error copying ingress files to '${INGRESS_PATH}/'"
    exit 1
fi

log "INFO" "Copying pods files to '${PODS_PATH}/'"
if cp -r "${INFO_CACHE}"/*_pods.md "${PODS_PATH}/"; then
    log "INFO" "Pods files copied successfully to '${PODS_PATH}/'"
else
    log "ERROR" "Error copying pods files to '${PODS_PATH}'"
    exit 1
fi

# Configure Git with a generic user
cd "${REPO_DIR}" || { log "ERROR" "Failed to navigate to '${REPO_DIR}'"; exit 1; }
git config user.email "ci@f-i-ts.de"
git config user.name "Cluster Crawler"

# Pull the latest changes again to ensure up-to-date before committing
git pull origin main || { log "ERROR" "Failed to pull latest changes before committing"; exit 1; }

# Stage all changes
git add -A || { log "ERROR" "Failed to stage changes"; exit 1; }

# Construct the commit message with timestamp
COMMIT_MESSAGE="Cluster Crawler am $(date +"%Y-%m-%d") um $(date +"%H:%M:%S")"

# Commit and push changes, forcing a commit even if there are no changes
if git commit --allow-empty -am "$COMMIT_MESSAGE"; then
    log "INFO" "Committed changes successfully"
else
    log "WARNING" "Nothing to commit, but proceeding to push"
fi

# Push changes to remote
if git push origin main; then
    log "INFO" "Git push completed successfully"
else
    log "ERROR" "Failed to push changes to the repository"
    exit 1
fi

exit 0

