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
# shellcheck disable=SC2034
UNSERE_CLUSTER="fttc ftctl"

# Marker-Datei zur Verfolgung, ob das Skript bereits erfolgreich ausgeführt wurde
MARKER_FILE="$(dirname "$0")/cluster_crawler_marker"

# Überprüfen, ob FORCE_REBUILD gesetzt werden soll
if [ -f "$MARKER_FILE" ]; then
    FORCE_REBUILD=0
else
    FORCE_REBUILD=1
fi

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

# Funktion zum Setzen des Kubernetes-Kontexts für einen gegebenen Cluster
set_kube_context() {
    if kubectl config use-context "$1"; then
        log "INFO" "Erfolgreich zu Kontext ${1} gewechselt"
        return 0
    else
        log "ERROR" "Fehler beim Wechseln zu Kontext ${1}"
        return 1
    fi
}

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

# NAMEID Scraper: Abrufen und Speichern der Name-ID-Zuordnung aller Cluster
NAMEID_MAP="scripts/docs/name_id.map"

if [ -f "${NAMEID_MAP}" ]; then
    log "INFO" "Statische name_id.map Datei gefunden. Verwende die Datei für die Cluster-Informationen."
else
    log "ERROR" "Statische name_id.map Datei nicht gefunden! Bitte überprüfen."
    debug_crawler_error
    exit 1
fi

# Kubernetes Data Collector: Abrufen und Speichern von Kubernetes-Informationen (Pods und Ingress) für jeden Cluster
while IFS=";" read -r CLSTRNM _CLSTRID; do
    log "DEBUG" "Hole kubectl Cluster-Inhalte für ${CLSTRNM}"

    # Dateipfade für das Speichern von Clusterinformationen definieren
    CLSTR_PODS="${INFO_CACHE}/${CLSTRNM}_pods.json"
    CLSTR_INGRESS="${INFO_CACHE}/${CLSTRNM}_ingress.json"

    if ! kubectl config get-contexts "${CLSTRNM}" &> /dev/null; then
        log "WARNING" "Kein kube Kontext für Cluster '${CLSTRNM}' gefunden, überspringe..."
        continue
    fi

    if ! set_kube_context "${CLSTRNM}"; then
        log "ERROR" "Fehler beim Setzen des kube Kontextes für Cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    KUBE_VERSION=$(kubectl version --output=json | jq -r '.serverVersion.gitVersion')

    if ! kubectl get pods -A -o json | jq --arg k8s_version "$KUBE_VERSION" '.items |= map(. + {kubernetesVersion: $k8s_version})' > "${CLSTR_PODS}"; then
        log "ERROR" "Fehler beim Abrufen der Pods für Cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi

    if ! kubectl get ingress -A -o json > "${CLSTR_INGRESS}"; then
        log "ERROR" "Fehler beim Abrufen der Ingress für Cluster '${CLSTRNM}'"
        debug_crawler_error
        exit 1
    fi
done < "${NAMEID_MAP}"

# Git-Token und Repository konfigurieren
GIT_USER="gitlab+deploy-token-<ID>"
GIT_TOKEN="${PUSH_BOM_PAGES}"  # Env-Variable für den Token
GIT_REPO_URL="https://gitlab-ci-token:${PUSH_BOM_PAGES}@gitlab.com/devops-services/toolchain/docs.git"


# Klonen des Repositories in ein temporäres Verzeichnis
REPO_DIR="/tmp/docs-repo"
if [ ! -d "${REPO_DIR}" ]; then
    git clone "${GIT_REPO_URL}" "${REPO_DIR}"
fi

# Pfade zum Repository festlegen
INGRESS_PATH="${REPO_DIR}/boms/k8s/ingress"
PODS_PATH="${REPO_DIR}/boms/k8s/pods"

# Erstellen der Zielverzeichnisse im Repository
create_directory "${INGRESS_PATH}"
create_directory "${PODS_PATH}"

# Kopiere die neuen Daten ins Repository-Verzeichnis
cp -r "${INFO_CACHE}/*_ingress.json" "${INGRESS_PATH}/"
cp -r "${INFO_CACHE}/*_pods.json" "${PODS_PATH}/"

# Automatischer Commit und Push
cd "${REPO_DIR}" || exit
git add .
git commit -m "Automatisches Update der Cluster-Daten am $(date)"
git push "${GIT_REPO_URL}" main
