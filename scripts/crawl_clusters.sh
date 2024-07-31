#!/bin/bash

# Skript zum Sammeln von Daten aller "unserer" Cluster

UNSERE_CLUSTER="fttc ftctl"

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

create_empty_directory() {
    locDir="${1}"
    rm -rf ${locDir} > /dev/null 2>&1

    create_directory "${locDir}"
    return $?
}

DAYSTAMP="$(date +"%Y%m%d")"

RESULTS_DIR="results"
TMPS_DIR="tmps"
create_empty_directory "${RESULTS_DIR}"
if [ $? -ne 0 ]; then
    exit 1
fi
create_empty_directory "${TMPS_DIR}"
if [ $? -ne 0 ]; then
    exit 1
fi

INFO_CACHE="info_cache_${DAYSTAMP}"

if [ "${FORCE_REBUILD}" == "1" ]; then
    echo "info: environment variable 'FORCE_REBUILD' is set to 1, and so we will refresh all (cached) cluster informations"
    rm -rf ${INFO_CACHE} > /dev/null 2>&1

    if [ -d ${INFO_CACHE} ]; then
        echo "error: failed to clear cache '${INFO_CACHE}'"
        exit 1
    fi
else
    echo "info: environment variable 'FORCE_REBUILD' not set to 1, so we will use cached cluster informations"
fi

if [ ! -d ${INFO_CACHE} ]; then
    # evtl. ein neuer Tag, und somit löschen wir alle alten info_cache_ -Verzeichnisse
    rm -rf info_cache_* > /dev/null 2>&1

    create_empty_directory ${INFO_CACHE}
fi

debug_crawler_error() {
    pwd
    ls -al
    ls -al ${INFO_CACHE}
}

#
# alle IPs aller cluster
#

CLSTR_IPS="${INFO_CACHE}/cluster_ips.json"

# Retrieve the list of cluster IPs in JSON format if the file does not exist or is empty
if [ ! -s ${CLSTR_IPS} ]; then
    if ! cloudctl ip list -o json > ${CLSTR_IPS}; then
        echo "error: failed to execute 'cloudctl ip list -o json' command"
        debug_crawler_error
        exit 1
    fi

   # Verify that the file was successfully created and filled
    if [ ! -s ${CLSTR_IPS} ]; then
        echo "error: 'cloudctl ip list' did not produce output in '${CLSTR_IPS}'"
        debug_crawler_error
        exit 1
    fi
fi

#
# Aufstellung / mapping über Namen und ID unserer cluster
#
NAMEID_MAP="${INFO_CACHE}/name_id.map"
if [ ! -s ${NAMEID_MAP} ]; then
    # create empty file
    > ${NAMEID_MAP}

    echo "debug: unsere cluster sind '${UNSERE_CLUSTER}'"
    for tnt in $(echo ${UNSERE_CLUSTER}); do
        echo "debug: tenant is ${tnt}"
        if ! cloudctl cluster list --tenant ${tnt} | grep -v "NAME" | awk '{ print $4";"$1 }' >> ${NAMEID_MAP}; then
            echo "error: failed to list clusters for tenant '${tnt}'"
            debug_crawler_error
            exit 1
        fi
    done
fi

if [ ! -s ${NAMEID_MAP} ]; then
    echo "error: failed to create / fill '${NAMEID_MAP}'"
    debug_crawler_error
    exit 1
fi

#
# für jeden unserer cluster die gesamte Info holen
#
for line in $(cat ${NAMEID_MAP}); do
    CLSTRNM=$(echo ${line} | cut -f 1 -d ";")
    CLSTRID=$(echo ${line} | cut -f 2 -d ";")
    echo "debug: will describe ${CLSTRNM} with ${CLSTRID}"

    CLSTR_INFO="${INFO_CACHE}/${CLSTRNM}_describe.json"
    if [ ! -s ${CLSTR_INFO} ]; then
        cloudctl cluster describe ${CLSTRID} -o json > ${CLSTR_INFO}
    fi
    if [ ! -s ${CLSTR_INFO} ]; then
        echo "error: failed to create / fill '${CLSTR_INFO}'"
        debug_crawler_error
        exit 1
    fi
done

for line in $(cat ${NAMEID_MAP}); do
    CLSTRNM=$(echo ${line} | cut -f 1 -d ";")
    echo "debug: will kubectl cluster content for ${CLSTRNM}"

    #
    # keine Ahnung, wie man "modern" jetzt jeweils auf den jeweiligen, entsprechenden kube context umschaltet
    #   also so, dass der kubectl gegen den entsprechenden cluster geht
    #

    CLSTR_PODS="${INFO_CACHE}/${CLSTRNM}_pods.json"
    # kubectl get pods -A
    CLSTR_INGRESS="${INFO_CACHE}/${CLSTRNM}_ingress.json"
    # kubectl get ingress -A
done

exit 0
