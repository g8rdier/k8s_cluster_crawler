# New section: Rename contexts in kubeconfig files to ensure uniqueness
# Assuming that your kubeconfig files are located in /tmp/kubeconfigs
# and are already decoded and saved there

# Directory containing individual kubeconfig files
KUBECONFIGS_DIR="/tmp/kubeconfigs"

# Check if the directory exists
if [ -d "$KUBECONFIGS_DIR" ]; then
    log "INFO" "Renaming contexts in kubeconfig files to ensure uniqueness"

    for file in "$KUBECONFIGS_DIR"/*; do
        cluster_name=$(basename "$file" | sed 's/_kubeconfig//')
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
