#!/bin/bash
set -euo pipefail  # Exit on error, treat unset variables as error, and handle pipeline failures

# Set the timezone
export TZ="UTC"

# Determine the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging function with timestamps
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    if [ "${DETAILED_LOGGING:-false}" = true ]; then
        echo "$timestamp [$level]: $message"
    elif [ "$level" != "DEBUG" ]; then
        echo "$timestamp [$level]: $message"
    fi
}

# Standard logging level is not detailed unless passed as an argument
DETAILED_LOGGING=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dl) DETAILED_LOGGING=true ;;  # Enable detailed logging
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Set FORCE_REBUILD to 1 to ensure rebuild each time
FORCE_REBUILD=1

# Function to create a directory if it doesn't exist
create_directory() {
    local dir="${1}"
    if [ ! -d "${dir}" ]; then
        mkdir -p "${dir}"
    fi
    if [ ! -d "${dir}" ]; then
        log "ERROR" "Error creating directory '${dir}'"
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

# Set up directories
DAYSTAMP="$(date +"%Y%m%d")"
INFO_CACHE="${SCRIPT_DIR}/info_cache_${DAYSTAMP}"

if ! create_directory "${INFO_CACHE}"; then
    exit 1
fi

# Rebuild cache if needed
log "INFO" "FORCE_REBUILD is set to 1, updating all cached cluster information"
rm -rf "${INFO_CACHE:?}"/* > /dev/null 2>&1 || true

# Cluster mapping file
CLUSTER_MAP="${SCRIPT_DIR}/docs/cluster_map.yaml"

if [ -f "${CLUSTER_MAP}" ]; then
    log "INFO" "Static cluster_map.yaml file found. Using the file for cluster information."
else
    log "ERROR" "Static cluster_map.yaml file not found! Please check."
    exit 1
fi

# Log the contents of cluster_map.yaml for verification
log "INFO" "Contents of ${CLUSTER_MAP}:"
cat "${CLUSTER_MAP}" || { log "ERROR" "Failed to read ${CLUSTER_MAP}"; exit 1; }

# Set up kubeconfig
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

        log "INFO" "Renamed context, user, and cluster in file '$file'"
    done

    # Merge all kubeconfig files
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

# Build cluster to context mapping
log "INFO" "Building cluster to context mapping"
declare -A cluster_context_map
available_contexts=$(kubectl config get-contexts -o name)

for context in $available_contexts; do
    cluster_context_map["$context"]="$context"
    log "DEBUG" "Mapped cluster '$context' to context '$context'"
done

# Process each cluster
while IFS=";" read -r CLUSTER_NAME _CLUSTER_ID; do
    [[ -z "$CLUSTER_NAME" || "$CLUSTER_NAME" =~ ^# ]] && continue

    if [[ -z "$CLUSTER_NAME" || -z "$_CLUSTER_ID" ]]; then
        log "ERROR" "Invalid entry in cluster_map.yaml: '$CLUSTER_NAME;$_CLUSTER_ID'"
        exit 1
    fi

    log "INFO" "Processing cluster: '$CLUSTER_NAME'"
    context="${cluster_context_map[$CLUSTER_NAME]:-}"

    if [ -z "$context" ]; then
        log "WARNING" "No matching context for cluster '$CLUSTER_NAME', skipping..."
        continue
    fi

    # Get current timestamp and process cluster data
    CURRENT_TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    PODS_MD_FILE="${INFO_CACHE}/${CLUSTER_NAME}_pods.md"
    INGRESS_MD_FILE="${INFO_CACHE}/${CLUSTER_NAME}_ingress.md"

    # Fetch and process pod data
    log "INFO" "Fetching pods data for '$CLUSTER_NAME'"
    if kubectl get pods -A -o json | python3 "${SCRIPT_DIR}/parser.py" --pods -dl \
        --cluster_name "$CLUSTER_NAME" --timestamp "$CURRENT_TIMESTAMP" --output_file "$PODS_MD_FILE"; then
        log "INFO" "Pod data successfully written to '$PODS_MD_FILE'"
    else
        log "ERROR" "Failed to fetch or parse pods data for '$CLUSTER_NAME'"
    fi

    # Fetch and process ingress data
    log "INFO" "Fetching ingress data for '$CLUSTER_NAME'"
    if kubectl get ingress -A -o json | python3 "${SCRIPT_DIR}/parser.py" --ingress -dl \
        --cluster_name "$CLUSTER_NAME" --timestamp "$CURRENT_TIMESTAMP" --output_file "$INGRESS_MD_FILE"; then
        log "INFO" "Ingress data successfully written to '$INGRESS_MD_FILE'"
    else
        log "ERROR" "Failed to fetch or parse ingress data for '$CLUSTER_NAME'"
    fi

done < "${CLUSTER_MAP}"

# Show contents of the info cache directory
log "INFO" "Contents of directory '${INFO_CACHE}':"
ls -l "${INFO_CACHE}" || { log "ERROR" "Failed to list contents of '${INFO_CACHE}'"; exit 1; }

# Git operations
GIT_REPO_URL="https://github.com/g8rdier/k8s_cluster_crawler.git"
REPO_DIR="/tmp/repo"

# Clone or update repository
if [ ! -d "${REPO_DIR}" ]; then
    log "INFO" "Cloning repository into '${REPO_DIR}'"
    git clone "${GIT_REPO_URL}" "${REPO_DIR}" || { log "ERROR" "Failed to clone repository"; exit 1; }
else
    log "INFO" "Repository already cloned. Pulling latest changes"
    cd "${REPO_DIR}" || { log "ERROR" "Failed to navigate to '${REPO_DIR}'"; exit 1; }
    git pull origin main || { log "ERROR" "Failed to pull latest changes"; exit 1; }
    cd - || exit
fi

# Set up repository paths
INGRESS_PATH="${REPO_DIR}/data/ingress"
PODS_PATH="${REPO_DIR}/data/pods"

# Create directories
create_directory "${INGRESS_PATH}" || { log "ERROR" "Failed to create directory '${INGRESS_PATH}'"; exit 1; }
create_directory "${PODS_PATH}" || { log "ERROR" "Failed to create directory '${PODS_PATH}'"; exit 1; }

# Copy files
log "INFO" "Copying files to repository"
cp -r "${INFO_CACHE}"/*_ingress.md "${INGRESS_PATH}/" || { log "ERROR" "Error copying ingress files"; exit 1; }
cp -r "${INFO_CACHE}"/*_pods.md "${PODS_PATH}/" || { log "ERROR" "Error copying pods files"; exit 1; }

# Configure Git
cd "${REPO_DIR}" || { log "ERROR" "Failed to navigate to '${REPO_DIR}'"; exit 1; }
git config user.email "crawler@example.com"
git config user.name "Cluster Crawler"

# Commit and push changes
COMMIT_MESSAGE="Cluster crawling on $(date +"%Y-%m-%d") at $(date +"%H:%M")"

git add -A || { log "ERROR" "Failed to stage changes"; exit 1; }
git commit --allow-empty -m "$COMMIT_MESSAGE" || log "WARNING" "Nothing to commit"

if git push origin main; then
    log "INFO" "Successfully pushed changes to repository"
else
    log "ERROR" "Failed to push changes to repository"
    exit 1
fi

exit 0

