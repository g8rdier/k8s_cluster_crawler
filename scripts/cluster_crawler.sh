#!/bin/bash

# set -x  # Debugging-Modus aktivieren (gibt jeden Befehl aus)

# Standard-Logging-Level
DETAILLIERTES_LOGGING=false

# Argumente der Befehlszeile parsen
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dl) DETAILLIERTES_LOGGING=true ;;  # Detailliertes Logging aktivieren
        *) echo "Unbekannter Parameter übergeben: $1"; exit 1 ;;
    esac
    shift
done

# Funktion zum Loggen von Nachrichten (abhängig vom Logging-Flag)
log() {
    local level="$1"
    local message="$2"
    if [ "$DETAILLIERTES_LOGGING" = true ]; then
        echo "$level: $message"
    elif [ "$level" != "DEBUG" ]; then
        echo "$level: $message"
    fi
}

# Skript zum Sammeln von Daten aller Cluster
UNSERE_CLUSTER="fttc ftctl"

# Marker-Datei zur Verfolgung, ob das Skript bereits erfolgreich ausgeführt wurde
MARKER_FILE="$(dirname "$0")/cluster_crawler_marker"

# Überprüfen, ob FORCE_REBUILD gesetzt werden soll
if [ -f "$MARKER_FILE" ]; then
    FORCE_REBUILD=0
else
    FORCE_REBUILD=1
fi

# Erklärung: Wenn FORCE_REBUILD auf 1 gesetzt ist, werden alle zwischengespeicherten Cluster-Informationen aktualisiert.
# Wenn es auf 0 gesetzt ist oder nicht definiert wurde, werden die vorhandenen Cache-Daten verwendet.

# Funktion zum Erstellen eines Verzeichnisses, falls es nicht existiert
create_directory() {
    locDir="${1}"
    if [ ! -d "${locDir}" ]; then
        mkdir -p "${locDir}" > /dev/null
    fi
    if [ ! -d "${locDir}" ]; then
        log "ERROR" "Fehler beim Erstellen des Verzeichnisses '${locDir}'"
        return 1
    fi
    return 0
}

# Funktion zum Erstellen eines leeren Verzeichnisses (falls vorhanden, wird es entfernt, dann neu erstellt)
create_empty_directory() {
    locDir="${1}"
    rm -rf "${locDir}" > /dev/null 2>&1
    create_directory "${locDir}"  # Corrected function call
}

# Funktion zum Setzen des Kubernetes-Kontexts für einen gegebenen Cluster
set_kube_context() {
    if kubectl config use-context "$1"; then  # Fixed syntax here by removing unnecessary quotes
        log "INFO" "Erfolgreich zu Kontext ${1} gewechselt"
        return 0
    else
        log "ERROR" "Fehler beim Wechseln zu Kontext ${1}"
        return 1
    fi
}

# Ab hier beginnt das Hauptskript

# temporäres Verzeichnis
DAYSTAMP="$(date +"%Y%m%d")"

# Einrichten des Info-Cache-Verzeichnisses
INFO_CACHE="info_cache_${DAYSTAMP}"

if ! create_directory "${INFO_CACHE}"; then
    exit 1
fi

if [ "${FORCE_REBUILD}" == "1" ]; then
    log "INFO" "Umgebungsvariable 'FORCE_REBUILD' ist auf 1 gesetzt, aktualisiere alle zwischengespeicherten Cluster-Informationen"
    rm -rf "${INFO_CACHE:?}/*" > /dev/null 2>&1
else
    log "INFO" "Umgebungsvariable 'FORCE_REBUILD' ist nicht auf 1 gesetzt, benutze zwischengespeicherte Cluster-Informationen"
fi

# Funktion zum Protokollieren von Fehlern und Debugging-Informationen
debug_crawler_error() {
    pwd
    ls -al
    ls -al "${INFO_CACHE}"
}

# IP Scraper: Abrufen und Speichern der IP-Adressen aller Cluster
#CLSTR_IPS="${INFO_CACHE}/cluster_ips.json"
#if [ ! -s "${CLSTR_IPS}" ]; then
#    if ! cloudctl ip list -o json > "${CLSTR_IPS}"; then
#        log "ERROR" "Fehler beim Ausführen des Befehls 'cloudctl ip list -o json'"
#        debug_crawler_error
#        exit 1
#    fi
#
#    if [ ! -s "${CLSTR_IPS}" ]; then
#        log "ERROR" "'cloudctl ip list' hat keine Ausgabe in '${CLSTR_IPS}' erzeugt"
#        debug_crawler_error
#        exit 1
#    fi
#fi

# NAMEID Scraper: Abrufen und Speichern der Name-ID-Zuordnung aller Cluster
NAMEID_MAP="${INFO_CACHE}/name_id.map"
if [ ! -s "${NAMEID_MAP}" ]; then
    : > "${NAMEID_MAP}"  # Datei erstellen oder leeren

    log "DEBUG" "Unsere Cluster sind '${UNSERE_CLUSTER}'"
    for tnt in ${UNSERE_CLUSTER}; do
        log "DEBUG" "Tenant ist ${tnt}"
        # Cluster für jeden Tenant auflisten und zur Map hinzufügen
        if ! cloudctl cluster list --tenant "${tnt}" | grep -v "NAME" | awk '{ print $4";"$1 }' >> "${NAMEID_MAP}"; then
            log "ERROR" "Fehler beim Auflisten der Cluster für Tenant '${tnt}'"
            debug_crawler_error
            exit 1
        fi
    done

    # Letzte Überprüfung, ob die name_id.map Datei gefüllt ist
    if [ ! -s "${NAMEID_MAP}" ]; then
        log "ERROR" "Fehler beim Erstellen / Füllen von '${NAMEID_MAP}'"
        debug_crawler_error
        exit 1
    fi
fi

# Cluster Describer: Abrufen und Speichern detaillierter Informationen für jeden Cluster
#while IFS=";" read -r CLSTRNM CLSTRID; do
#    log "DEBUG" "Beschreibe ${CLSTRNM} mit ${CLSTRID}"
#
#    CLSTR_INFO="${INFO_CACHE}/${CLSTRNM}_describe.json"
#    if [ ! -s "${CLSTR_INFO}" ]; then
#        if ! cloudctl cluster describe "${CLSTRID}" -o json > "${CLSTR_INFO}"; then
#            log "ERROR" "Fehler beim Beschreiben des Clusters '${CLSTRNM}' mit ID '${CLSTRID}'"
#            debug_crawler_error
#            exit 1
#        fi
#    fi
#
#    if [ ! -s "${CLSTR_INFO}" ]; then
#        log "ERROR" "Fehler beim Erstellen / Füllen von '${CLSTR_INFO}'"
#        debug_crawler_error
#        exit 1
#    fi
#done < "${NAMEID_MAP}"

# Kubernetes Data Collector: Abrufen und Speichern von Kubernetes-Informationen (Pods und Ingress) für jeden Cluster
while IFS=";" read -r CLSTRNM CLSTRID; do
    log "DEBUG" "Hole kubectl Cluster-Inhalte für ${CLSTRNM}"

    # Dateipfade für das Speichern von Clusterinformationen definieren
    CLSTR_PODS="${INFO_CACHE}/${CLSTRNM}_pods.json"
    CLSTR_INGRESS="${INFO_CACHE}/${CLSTRNM}_ingress.json"

    # Überprüfen, ob der kube context existiert
    if ! kubectl config get-contexts "${CLSTRNM}" &> /dev/null; then
        log "WARNING" "Kein kube Kontext für Cluster '${CLSTRNM}' gefunden, überspringe..."
        continue
    fi

    # Zum entsprechenden kube Kontext für den Cluster wechseln
    if ! set_kube_context "${CLSTRNM}"; then
        log "ERROR" "Fehler beim Setzen des kube Kontextes für Cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi
    
    # Kubernetes Version fetchen
    KUBE_VERSION=$(kubectl version --output=json | jq -r '.serverVersion.gitVersion')

    # Abrufen und Speichern von Pod-Informationen
    if ! kubectl get pods -A -o json | jq --arg k8s_version "$KUBE_VERSION" '.items |= map(. + {kubernetesVersion: $k8s_version})' > "${CLSTR_PODS}"; then
        log "ERROR" "Fehler beim Abrufen der Pods für Cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    # Abrufen und Speichern von Ingress-Informationen
    if ! kubectl get ingress -A -o json > "${CLSTR_INGRESS}"; then
        log "ERROR" "Fehler beim Abrufen der Ingress für Cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi
done < "${NAMEID_MAP}"

# Doppelte Überprüfung, ob alle Cluster aus name_id.map verarbeitet wurden
# ALL_CLUSTERS_PROCESSED_SUCCESSFULLY=true

# while IFS=";" read -r CLSTRNM CLSTRID; do
#    CLSTR_INFO="${INFO_CACHE}/${CLSTRNM}_describe.json"
#    
#    if [ ! -s "${CLSTR_INFO}" ]; then
#        log "ERROR" "Cluster '${CLSTRNM}' wurde nicht korrekt verarbeitet"
#        debug_crawler_error
#        ALL_CLUSTERS_PROCESSED_SUCCESSFULLY=false
#    fi
#done < "${NAMEID_MAP}"

# Cleanup-Funktion für das Entfernen der Dateien, wenn alle Cluster erfolgreich verarbeitet wurden
#cleanup() {
#    if [ $ALL_CLUSTERS_PROCESSED_SUCCESSFULLY == true ]; then
#        log "INFO" "Alle Cluster wurden erfolgreich verarbeitet, name_id.map und cluster_ips.json werden entfernt"
#        rm -f "${NAMEID_MAP}"
#        rm -f "${CLSTR_IPS}"
        # Marker-Datei erstellen, um anzuzeigen, dass das Skript erfolgreich ausgeführt wurde
#        touch "$MARKER_FILE"
#    else
#        log "INFO" "Einige Cluster wurden nicht erfolgreich verarbeitet, name_id.map und cluster_ips.json bleiben zur weiteren Überprüfung erhalten."
#    fi
}
trap cleanup EXIT

# Hinweis für detailliertes Logging
log "INFO" "Hinweis: Du kannst detailliertes Logging aktivieren, indem du das Skript mit der Option '-dl' ausführst."

exit 0

