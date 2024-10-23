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

# Standard logging level is not detailed unless passed as an argument
DETAILLIERTES_LOGGING=false

# Initialize NO_COMMIT flag
NO_COMMIT=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dl) DETAILLIERTES_LOGGING=true ;;  # Enable detailed logging
        --no-commit) NO_COMMIT=true ;;       # Enable no-commit mode
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

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

# Function to verify that all expected files are present in the repository
verify_files() {
    local repo_dir="$1"
    local name_id_map="$2"
    local missing_files=0

    while IFS=";" read -r CLSTRNM _CLSTRID; do
        [[ -z "$CLSTRNM" || "$CLSTRNM" =~ ^# ]] && continue

        PODS_MD_FILE="${repo_dir}/boms/k8s/pods/${CLSTRNM}_pods.md"
        INGRESS_MD_FILE="${repo_dir}/boms/k8s/ingress/${CLSTRNM}_ingress.md"

        if [ ! -f "$PODS_MD_FILE" ]; then
            log "ERROR" "Missing pod file for cluster '$CLSTRNM': '$PODS_MD_FILE'"
            missing_files=1
        fi
        if [ ! -f "$INGRESS_MD_FILE" ]; then
            log "ERROR" "Missing ingress file for cluster '$CLSTRNM': '$INGRESS_MD_FILE'"
            missing_files=1
        fi
    done < "$name_id_map"

    if [ "$missing_files" -eq 0 ]; then
        log "INFO" "All cluster ingress and pod files are present in the repository."
    else
        log "ERROR" "Some cluster files are missing in the repository."
        exit 1
    fi
}

# Temporary directory
DAYSTAMP="$(date +"%Y%m%d")"
INFO_CACHE="${SCRIPT_DIR}/info_cache_${DAYSTAMP}"

if ! create_directory "${INFO_CACHE}"; then
    exit 1
fi

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

log "INFO" "Contents of ${NAMEID_MAP}:"
cat "${NAMEID_MAP}" || { log "ERROR" "Failed to read ${NAMEID_MAP}"; exit 1; }

# Debugging: Log the available kubeconfig files in the directory
KUBECONFIGS_DIR="/tmp/kubeconfigs"
log "DEBUG" "Available kubeconfig files in ${KUBECONFIGS_DIR}:"
ls -l "${KUBECONFIGS_DIR}" || log "ERROR" "Failed to list kubeconfig directory contents"

# New section: Rename contexts, users, and clusters in kubeconfig files to ensure uniqueness
if [ -d "$KUBECONFIGS_DIR" ]; then
    log "INFO" "Renaming contexts, users, and clusters in kubeconfig files to ensure uniqueness"

    for file in "$KUBECONFIGS_DIR"/*; do
        cluster_name=$(basename "$file" | sed 's/_kubeconfig//' | tr '_' '-')
        log "DEBUG" "Processing kubeconfig file '$file' for cluster '$cluster_name'"

        new_context_name="$cluster_name"
        new_user_name="${cluster_name}-user"
        new_cluster_name="${cluster_name}-cluster"

        yq e "(.contexts[0].name) = \"$new_context_name\"" -i "$file" || { log "ERROR" "Failed to rename context in '$file'"; exit 1; }
        yq e "(.contexts[0].context.user) = \"$new_user_name\"" -i "$file" || { log "ERROR" "Failed to rename user in '$file'"; exit 1; }
        yq e "(.contexts[0].context.cluster) = \"$new_cluster_name\"" -i "$file" || { log "ERROR" "Failed to rename cluster in '$file'"; exit 1; }
        yq e "(.users[0].name) = \"$new_user_name\"" -i "$file" || { log "ERROR" "Failed to rename user in '$file'"; exit 1; }
        yq e "(.clusters[0].name) = \"$new_cluster_name\"" -i "$file" || { log "ERROR" "Failed to rename cluster in '$file'"; exit 1; }
        yq e ".\"current-context\" = \"$new_context_name\"" -i "$file" || { log "ERROR" "Failed to update current-context in '$file'"; exit 1; }

        log "INFO" "Renamed context, user, and cluster in file '$file' to '$new_context_name', '$new_user_name', and '$new_cluster_name'"
    done

    log "INFO" "Merging kubeconfig files"
    export KUBECONFIG=$(find "$KUBECONFIGS_DIR" -type f -exec printf '{}:' \;)
    kubectl config view --flatten > /tmp/merged_kubeconfig || { log "ERROR" "Error flattening kubeconfig"; exit 1; }

    log "INFO" "Available contexts after merging kubeconfig files:"
    export KUBECONFIG="/tmp/merged_kubeconfig"
    kubectl config get-contexts || { log "ERROR" "Error retrieving contexts from merged kubeconfig"; exit 1; }

else
    log "ERROR" "Kubeconfig directory '$KUBECONFIGS_DIR' not found!"
    exit 1
fi

export KUBECONFIG="/tmp/merged_kubeconfig"

log "INFO" "Building cluster to context mapping"
declare -A cluster_context_map

available_contexts=$(kubectl config get-contexts -o name)

for context in $available_contexts; do
    cluster_context_map["$context"]="$context"
    log "DEBUG" "Mapped cluster '$context' to context '$context'"
done

log "INFO" "Cluster to Context Mapping:"
for key in "${!cluster_context_map[@]}"; do
    log "INFO" "Cluster: '$key' -> Context: '${cluster_context_map[$key]}'"
done

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
    log "ERROR" "Error copying pods files to '${PODS_PATH}/'"
    exit 1
fi

# Function to generate a summary of collected data and display it in the terminal
generate_summary() {
    log "INFO" "Generating summary of collected data."

    # Print header for the summary table
    echo "| Cluster Name | Pods Count | Ingress Count |"
    echo "|--------------|------------|---------------|"

    while IFS=";" read -r CLSTRNM _CLSTRID; do
        [[ -z "$CLSTRNM" || "$CLSTRNM" =~ ^# ]] && continue

        # Define paths to pod and ingress files for each cluster
        PODS_MD_FILE="${INFO_CACHE}/${CLSTRNM}_pods.md"
        INGRESS_MD_FILE="${INFO_CACHE}/${CLSTRNM}_ingress.md"

        # Initialize counts for pods and ingress
        pods_count=0
        ingress_count=0

        # Check for pod file and count entries (assuming '###' indicates an entry)
        if [ -f "$PODS_MD_FILE" ]; then
            pods_count=$(grep -c "###" "$PODS_MD_FILE")  # Adjust pattern as necessary
        fi

        # Check for ingress file and count entries
        if [ -f "$INGRESS_MD_FILE" ]; then
            ingress_count=$(grep -c "###" "$INGRESS_MD_FILE")  # Adjust pattern as necessary
        fi

        # Output the cluster information directly to the terminal
        echo "| ${CLSTRNM} | ${pods_count} | ${ingress_count} |"

    done < "${NAMEID_MAP}"

    log "INFO" "Summary of collected data displayed in the terminal."
}

# Call the generate_summary function after collecting data
generate_summary
}

# Kubernetes Data Collector: Retrieve and save Kubernetes information (pods and ingress) for each cluster
while IFS=";" read -r CLSTRNM _CLSTRID; do
    [[ -z "$CLSTRNM" || "$CLSTRNM" =~ ^# ]] && continue

    log "INFO" "Processing cluster: '$CLSTRNM'"
    context="${cluster_context_map[$CLSTRNM]:-}"

    if [ -z "$context" ]; then
        log "WARNING" "No matching context for cluster '$CLSTRNM', skipping..."
        continue
    fi

    log "INFO" "Using context: '$context' for cluster: '$CLSTRNM'"
    set_kube_context "$context" || { log "ERROR" "Failed to switch to context '$context'"; continue; }

    log "INFO" "Fetching and parsing pod and ingress data for '$CLSTRNM'"

    PODS_MD_FILE="${INFO_CACHE}/${CLSTRNM}_pods.md"
    INGRESS_MD_FILE="${INFO_CACHE}/${CLSTRNM}_ingress.md"

    log "INFO" "Fetching pods data for '$CLSTRNM'"
    if kubectl get pods -A -o json | python3 "${SCRIPT_DIR}/parser.py" --pods -dl --output_file "$PODS_MD_FILE"; then
        log "INFO" "Pod data for '$CLSTRNM' successfully written to '$PODS_MD_FILE'"
    else
        log "ERROR" "Failed to fetch or parse pods data for '$CLSTRNM'"
    fi

    log "INFO" "Fetching ingress data for '$CLSTRNM'"
    if kubectl get ingress -A -o json | python3 "${SCRIPT_DIR}/parser.py" --ingress -dl --output_file "$INGRESS_MD_FILE"; then
        log "INFO" "Ingress data for '$CLSTRNM' successfully written to '$INGRESS_MD_FILE'"
    else
        log "ERROR" "Failed to fetch or parse ingress data for '$CLSTRNM'"
    fi
done < "${NAMEID_MAP}"

# Call the generate_summary function after collecting data
generate_summary

# Before copying the new data into the repository, log the existing files
log "INFO" "Listing current files in the repository before overwriting"

if [ -d "${INGRESS_PATH}" ]; then
    log "INFO" "Current files in the ingress directory:"
    ls -l "${INGRESS_PATH}" || { log "ERROR" "Failed to list ingress directory"; exit 1; }
else
    log "WARNING" "Ingress directory does not exist. It will be created."
fi

if [ -d "${PODS_PATH}" ]; then
    log "INFO" "Current files in the pods directory:"
    ls -l "${PODS_PATH}" || { log "ERROR" "Failed to list pods directory"; exit 1; }
else
    log "WARNING" "Pods directory does not exist. It will be created."
fi

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
    log "ERROR" "Error copying pods files to '${PODS_PATH}/'"
    exit 1
fi

# Log the updated contents of the repository
log "INFO" "Listing updated files in the repository after copying new data"
log "INFO" "Updated files in the ingress directory:"
ls -l "${INGRESS_PATH}" || { log "ERROR" "Failed to list ingress directory"; exit 1; }

log "INFO" "Updated files in the pods directory:"
ls -l "${PODS_PATH}" || { log "ERROR" "Failed to list pods directory"; exit 1; }

# Verification Step: Ensure all files are present in the repository
verify_files "$REPO_DIR" "$NAMEID_MAP" || { log "ERROR" "File verification failed."; exit 1; }


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
    log "ERROR" "Error copying pods files to '${PODS_PATH}/'"
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

# Commit and push if there are changes
if git commit -am "Automatisches Update der Cluster-Daten am $(date)"; then
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

