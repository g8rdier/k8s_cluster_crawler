#!/bin/bash

# Skript zum Sammeln von Daten aller "unserer" Cluster

UNSERE_CLUSTER="fttc ftctl"

# Setzt die Umgebungsvariable FORCE_REBUILD
FORCE_REBUILD=1

# Funktion zum Erstellen eines Verzeichnisses, falls es nicht existiert
create_directory() {
    locDir="${1}"
    if [ ! -d "${locDir}" ]; then
        mkdir -p "${locDir}" > /dev/null
    fi
    if [ ! -d "${locDir}" ]; then
        echo "error: failed to create directory '${locDir}'"
        return 1
    fi
    return 0
}

# Funktion zum Erstellen eines leeren Verzeichnisses (falls vorhanden, wird es entfernt, dann neu erstellt)
create_empty_directory() {
    locDir="${1}"
    rm -rf "${locDir}" > /dev/null 2>&1
    create_directory "${locDir}"
}

# Funktion zum Setzen des Kubernetes-Kontexts für einen gegebenen Cluster
set_kube_context() {
    if kubectl config use-context "${1}"; then
        echo "Successfully switched to context ${1}"
        return 0
    else
        echo "Failed to switch to context ${1}"
        return 1
    fi
}

# Ab hier beginnt das Hauptskript

# Variablen für Zeitstempel, Ergebnisverzeichnis und temporäres Verzeichnis
DAYSTAMP="$(date +"%Y%m%d")"
RESULTS_DIR="results"
TMPS_DIR="tmps/week_${WEEKNUM}"

# Erstellen von Ergebnis- und temporären Verzeichnissen
if ! create_empty_directory "${RESULTS_DIR}"; then
    exit 1
fi
if ! create_empty_directory "${TMPS_DIR}"; then
    exit 1
fi

# Einrichten des Info-Cache-Verzeichnisses
INFO_CACHE="${TMPS_DIR}/info_cache_${DAYSTAMP}"

if [ "${FORCE_REBUILD}" == "1" ]; then
    echo "info: environment variable 'FORCE_REBUILD' is set to 1, refreshing all cached cluster information"
    rm -rf "${INFO_CACHE}" > /dev/null 2>&1

    if [ -d "${INFO_CACHE}" ]; then
        echo "error: failed to clear cache '${INFO_CACHE}'"
        exit 1
    fi
else
    echo "info: environment variable 'FORCE_REBUILD' not set to 1, using cached cluster information"
fi

if [ ! -d "${INFO_CACHE}" ]; then
    # Möglicherweise ein neuer Tag, daher alle alten info_cache Verzeichnisse löschen
    rm -rf "${TMPS_DIR}/info_cache_*" > /dev/null 2>&1
    create_empty_directory "${INFO_CACHE}"
fi

# Funktion zum Protokollieren von Fehlern und Debugging-Informationen
debug_crawler_error() {
    pwd
    ls -al
    ls -al "${INFO_CACHE}"
}

# IP Scraper: Abrufen und Speichern der IP-Adressen aller Cluster
CLSTR_IPS="${INFO_CACHE}/cluster_ips.json"
if [ ! -s "${CLSTR_IPS}" ]; then
    if ! cloudctl ip list -o json > "${CLSTR_IPS}"; then
        echo "error: failed to execute 'cloudctl ip list -o json' command"
        debug_crawler_error
        exit 1
    fi

    if [ ! -s "${CLSTR_IPS}" ]; then
        echo "error: 'cloudctl ip list' did not produce output in '${CLSTR_IPS}'"
        debug_crawler_error
        exit 1
    fi
fi

# NAMEID Scraper: Abrufen und Speichern der Name-ID-Zuordnung aller Cluster
NAMEID_MAP="${INFO_CACHE}/name_id.map"
if [ ! -s "${NAMEID_MAP}" ]; then
    : > "${NAMEID_MAP}"  # Dies stellt sicher, dass die Datei erstellt oder geleert wird, ohne unnötige Kommandosubstitution zu verwenden

    echo "debug: unsere cluster sind '${UNSERE_CLUSTER}'"
    for tnt in ${UNSERE_CLUSTER}; do
        echo "debug: tenant is ${tnt}"
        # Überprüfen, ob Cluster für jeden Tenant aufgelistet sind und sie zur Map hinzufügen
        if ! cloudctl cluster list --tenant "${tnt}" | grep -v "NAME" | awk '{ print $4";"$1 }' >> "${NAMEID_MAP}"; then
            echo "error: failed to list clusters for tenant '${tnt}'"
            debug_crawler_error
            exit 1
        fi
    done

    # Letzte Überprüfung, ob die name_id.map Datei gefüllt ist
    if [ ! -s "${NAMEID_MAP}" ]; then
        echo "error: failed to create / fill '${NAMEID_MAP}'"
        debug_crawler_error
        exit 1
    fi
fi

# Cluster Describer: Abrufen und Speichern detaillierter Informationen für jeden Cluster
for line in $(cat "${NAMEID_MAP}"); do
    CLSTRNM=$(echo "${line}" | cut -f 1 -d ";")
    CLSTRID=$(echo "${line}" | cut -f 2 -d ";")
    echo "debug: will describe ${CLSTRNM} with ${CLSTRID}"

    CLSTR_INFO="${INFO_CACHE}/${CLSTRNM}_describe.json"
    if [ ! -s "${CLSTR_INFO}" ]; then
        if ! cloudctl cluster describe "${CLSTRID}" -o json > "${CLSTR_INFO}"; then
            echo "error: failed to describe cluster '${CLSTRNM}' with ID '${CLSTRID}'"
            debug_crawler_error
            exit 1
        fi
    fi

    if [ ! -s "${CLSTR_INFO}" ]; then
        echo "error: failed to create / fill '${CLSTR_INFO}'"
        debug_crawler_error
        exit 1
    fi
done

# Kubernetes Data Collector: Abrufen und Speichern von Kubernetes-Informationen (Pods und Ingress) für jeden Cluster
for line in $(cat "${NAMEID_MAP}"); do
    CLSTRNM=$(echo "${line}" | cut -f 1 -d ";")
    echo "debug: will kubectl cluster content for ${CLSTRNM}"

    # Dateipfade für das Speichern von Clusterinformationen definieren
    CLSTR_PODS="${INFO_CACHE}/${CLSTRNM}_pods.json"
    CLSTR_INGRESS="${INFO_CACHE}/${CLSTRNM}_ingress.json"

    # Zum entsprechenden kube Kontext für den Cluster wechseln
    if ! set_kube_context "${CLSTRNM}"; then
        echo "error: failed to set kube context for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    # Abrufen und Speichern von Pod-Informationen
    if ! kubectl get pods -A -o json > "${CLSTR_PODS}"; then
        echo "error: failed to retrieve pods for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    # Abrufen und Speichern von Ingress-Informationen
    if ! kubectl get ingress -A -o json > "${CLSTR_INGRESS}"; then
        echo "error: failed to retrieve ingress for cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi
done

# Doppelte Überprüfung, ob alle Cluster aus name_id.map verarbeitet wurden
for line in $(cat "${NAMEID_MAP}"); do
    CLSTRNM=$(echo "${line}" | cut -f 1 -d ";")
    CLSTR_INFO="${INFO_CACHE}/${CLSTRNM}_describe.json"
    
    if [ ! -s "${CLSTR_INFO}" ]; then
        echo "Fehler: Cluster '${CLSTRNM}' wurde nicht korrekt verarbeitet"
        debug_crawler_error
        ALL_CLUSTERS_PROCESSED_SUCCESSFULLY=false
    fi
done

# Cleanup-Funktion für das Entfernen der Dateien, wenn alle Cluster erfolgreich verarbeitet wurden
cleanup() {
    if [ "$ALL_CLUSTERS_PROCESSED_SUCCESSFULLY" = true ]; then
        echo "Info: Alle Cluster wurden erfolgreich verarbeitet, name_id.map und cluster_ips.json werden entfernt"
        rm -f "${NAMEID_MAP}"
        rm -f "${CLSTR_IPS}"
    else
        echo "Info: Einige Cluster wurden nicht erfolgreich verarbeitet, name_id.map und cluster_ips.json bleiben zur weiteren Überprüfung erhalten."
    fi
}
trap cleanup EXIT

exit 0
