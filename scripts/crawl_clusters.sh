#!/bin/bash

# Script to collect data from all "our" clusters

UNSERE_CLUSTER="fttc ftctl"

# Function to create a directory if it doesn't exist
create_directory() {
    locDir="${1}"
    if [ ! -d ${locDir} ]; then
        mkdir ${locDir} > /dev/null
    fi
    if [ ! -d ${locDir} ]; then
        echo "error: failed to create directory '${locDir}'"
        return 1
    fi
    return 0
}

# Function to create an empty directory (remove if exists, then create)
create_empty_directory() {
    locDir="${1}"
    rm -rf ${locDir} > /dev/null 2>&1
    create_directory "${locDir}"
    return $?
}

# Function to set the Kubernetes context for a given cluster
set_kube_context() {
    local CLUSTER_NAME="$1"
    local CONTEXT_NAME="context-${CLUSTER_NAME}"
    
    if kubectl config use-context "${CONTEXT_NAME}"; then
        echo "Successfully switched to context ${CONTEXT_NAME}"
        return 0
    else
        echo "Failed to switch to context ${CONTEXT_NAME}"
        return 1
    fi
}

# Main script starts here

# Variables for timestamp, results directory, and temporary directory
DAYSTAMP="$(date +"%Y%m%d")"
RESULTS_DIR="results"
TMPS_DIR="tmps"

# Create results and temporary directories
create_empty_directory "${RESULTS_DIR}"
if [ $? -ne 0 ]; then
    exit 1
fi
create_empty_directory "${TMPS_DIR}"
if [ $? -ne 0 ]; then
    exit 1
fi

# Set up the info cache directory
INFO_CACHE="info_cache_${DAYSTAMP}"

if [ "${FORCE_REBUILD}" == "1" ]; then
    echo "info: environment variable 'FORCE_REBUILD' is set to 1, refreshing all cached cluster information"
    rm -rf ${INFO_CACHE} > /dev/null 2>&1

    if [ -d ${INFO_CACHE} ]; then
        echo "error: failed to clear cache '${INFO_CACHE}'"
        exit 1
    fi
else
    echo "info: environment variable 'FORCE_REBUILD' not set to 1, using cached cluster information"
fi

if [ ! -d ${INFO_CACHE} ]; then
    # Possibly a new day, so delete all old info_cache directories
    rm -rf info_cache_* > /dev/null 2>&1
    create_empty_directory ${INFO_CACHE}
fi

# Function to log errors and debugging information
debug_crawler_error() {
    pwd
    ls -al
    ls -al ${INFO_CACHE}
}

# IP Scraper: Retrieve and store the IP addresses of all clusters
CLSTR_IPS="${INFO_CACHE}/cluster_ips.json"
if [ ! -s ${CLSTR_IPS} ]; then
    if ! cloudctl ip list -o json > ${CLSTR_IPS}; then
        echo "error: failed to execute 'cloudctl ip list -o json' command"
        debug_crawler_error
        exit 1
    fi

    if [ ! -s ${CLSTR_IPS} ]; then
        echo "error: 'cloudctl ip list' did not produce output in '${CLSTR_IPS}'"
        debug_crawler_error
        exit 1
    fi
fi

# NAMEID Scraper: Retrieve and store the name-ID mapping of all clusters
NAMEID_MAP="${INFO_CACHE}/name_id.map"
if [ ! -s ${NAMEID_MAP} ]; then
    > ${NAMEID_MAP}

    echo "debug: unsere cluster sind '${UNSERE_CLUSTER}'"
    for tnt in ${UNSERE_CLUSTER}; do
        echo "debug: tenant is ${tnt}"
        # Check if clusters are listed for each tenant and append them to the map
        if ! cloudctl cluster list --tenant ${tnt} | grep -v "NAME" | awk '{ print $4";"$1 }' >> ${NAMEID_MAP}; then
            echo "error: failed to list clusters for tenant '${tnt}'"
            debug_crawler_error
            exit 1
        fi
    done

    # Final check to ensure the name_id.map file is populated
    if [ ! -s ${NAMEID_MAP} ]; then
        echo "error: failed to create / fill '${NAMEID_MAP}'"
        debug_crawler_error
        exit 1
    fi
fi

# Cluster Describer: Retrieve and store detailed information for each cluster
for line in $(cat ${NAMEID_MAP}); do
    CLSTRNM=$(echo ${line} | cut -f 1 -d ";")
    CLSTRID=$(echo ${line} | cut -f 2 -d ";")
    echo "debug: will describe ${CLSTRNM} with ${CLSTRID}"

    CLSTR_INFO="${INFO_CACHE}/${CLSTRNM}_describe.json"
    if [ ! -s ${CLSTR_INFO} ]; then
        if ! cloudctl cluster describe ${CLSTRID} -o json > ${CLSTR_INFO}; then
            echo "error: failed to describe cluster '${CLSTRNM}' with ID '${CLSTRID}'"
            debug_crawler_error
            exit 1
        fi
    fi

    if [ ! -s ${CLSTR_INFO} ]; then
        echo "error: failed to create / fill '${CLSTR_INFO}'"
        debug_crawler_error
        exit 1
    fi
done

# Kubernetes Data Collector: Retrieve and store Kubernetes information (pods and ingress) for each cluster
for line in $(cat ${NAMEID_MAP}); do
    CLSTRNM=$(echo ${line} | cut -f 1 -d ";")
    echo "debug: will kubectl cluster content for ${CLSTRNM}"

    # Define file paths for storing cluster information
    CLSTR_PODS="${INFO_CACHE}/${CLSTRNM}_pods.json"
    CLSTR_INGRESS="${INFO_CACHE}/${CLSTRNM}_ingress.json"

    # Switch to the appropriate kube context for the cluster
    if ! set_kube_context "${CLSTRNM}"; then
        echo "error: failed to set kube context for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    # Retrieve and store pod information
    if ! kubectl get pods -A -o json > "${CLSTR_PODS}"; then
        echo "error: failed to retrieve pods for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    # Retrieve and store ingress information
    if ! kubectl get ingress -A -o json > "${CLSTR_INGRESS}"; then
        echo "error: failed to retrieve ingress for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi
done

exit 0
