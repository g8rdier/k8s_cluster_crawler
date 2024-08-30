# Cluster-Daten-Sammlung und Berichtserstellung

Dieses Repository enthält eine Sammlung von Skripten, die dazu dienen, Daten aus mehreren Kubernetes-Clustern zu sammeln und detaillierte Markdown-Berichte zu generieren. Der Prozess umfasst zwei Hauptskripte:

1. **Bash-Skript (`crawl_clusters.sh`)**: Dieses Skript sammelt Daten aus den angegebenen Kubernetes-Clustern.
2. **Python-Skript (`generate_ingress_reports.py`)**: Dieses Skript verarbeitet die gesammelten Daten und generiert für jeden Cluster Markdown-Dateien, die die Ingress-Informationen zusammenfassen.


## Voraussetzungen

Bevor die Skripte ausgeführt werden, stellen Sie sicher, dass die folgenden Werkzeuge auf Ihrem System installiert sind:

- **Kubernetes CLI (`kubectl`)**: Wird verwendet, um mit Kubernetes-Clustern zu interagieren.
- **Python 3.x**: Das Python-Skript erfordert Python 3.x.
- **Cloudctl CLI**: Erforderlich, falls Ihre Umgebung den IBM Cloud Kubernetes Service verwendet.


## Nutzungsanleitung

### Schritt 1: Repository klonen

Klone das Repository auf deine lokale Maschine:

```bash
git clone https://git.f-i-ts.de/devops-services/toolchain/develop/tc-cluster-crawler.git
cd tc-cluster-crawler

### Schritt 2: Bash-Skript ausführen
Das Skript crawl_clusters.sh sammelt Daten aus den in dem Skript angegebenen Kubernetes-Clustern. Es wechselt die Kontexte zu jedem Cluster, ruft die erforderlichen Informationen ab und speichert sie im Verzeichnis info_cache_<DATUM>.

Erster Lauf des Skripts
Beim ersten Ausführen des Skripts setzen Sie die Umgebungsvariable FORCE_REBUILD auf 1, um die Sammlung neuer Daten aus allen Clustern zu erzwingen:

./crawl_clusters.sh -dl

-dl: Aktiviert detailliertes Logging, das ausführlichere Ausgaben für Debugging- und Überwachungszwecke bereitstellt.
Nachfolgende Ausführungen
Bei nachfolgenden Ausführungen verwendet das Skript die zwischengespeicherten Daten, es sei denn, FORCE_REBUILD wird manuell auf 1 gesetzt. Du kannst das Skript ohne zusätzliche Argumente ausführen: ./crawl_clusters.sh

Hinweis: Das Skript schaltet die Variable FORCE_REBUILD automatisch um, je nachdem, ob es zuvor ausgeführt wurde oder nicht. Das Skript erstellt nach einem erfolgreichen Lauf eine Marker-Datei (cluster_crawler_marker), die verwendet wird, um zu bestimmen, ob der Cache beim nächsten Ausführen neu aufgebaut werden soll.


### Schritt 3: Python-Skript ausführen


Nach dem Sammeln der Cluster-Daten führst du das Python-Skript aus, um Markdown-Berichte zu generieren: python3 generate_ingress_reports.py -dl


[-dl: Aktiviert detailliertes Logging im Python-Skript.]

Dieses Skript verarbeitet die im Verzeichnis info_cache_<DATUM> gespeicherten Daten und generiert Markdown-Dateien, die die Ingress-Informationen für jeden Cluster zusammenfassen. Die Markdown-Dateien werden im Verzeichnis ergebnisse gespeichert und mit Dateinamen versehen, die dem jeweiligen Cluster entsprechen.


### Schritt 4: Die Markdown-Berichte anzeigen
Nach dem Ausführen des Python-Skripts navigierst du zum Verzeichnis ergebnisse, um die generierten Markdown-Berichte anzuzeigen. Jede Datei ist nach dem Cluster benannt, mit einem Suffix _ingress.md.

Beispiel:

ergebnisse/
├── fttc-demo1_ingress.md
├── fttc-pf01_ingress.md
...

Fehlersuche
- Authentifizierungsprobleme: Stelle sicher, dass du die erforderlichen Berechtigungen und Anmeldedaten hast, um auf die Kubernetes-Cluster zuzugreifen.
- Force Rebuild: Wenn das Skript keine neuen Daten sammelt, versuche, die Umgebungsvariable FORCE_REBUILD manuell auf 1 zu setzen.
- Detailliertes Logging: Verwende die Option -dl für detailliertere Ausgaben, die bei der Fehlerbehebung helfen können.

Beispielablauf

# Schritt 1: Bash-Skript ausführen, um Cluster-Daten zu sammeln
./crawl_clusters.sh -dl

# Schritt 2: Python-Skript ausführen, um Berichte zu generieren
python3 generate_ingress_reports.py -dl

# Schritt 3: Generierte Berichte im Verzeichnis 'ergebnisse' anzeigen


Skript-Details
# Bash-Skript (crawl_clusters.sh)
- Zweck: Sammelt Daten aus Kubernetes-Clustern, einschließlich IP-Adressen, Pod-Details und Ingress-Konfigurationen.
- Logging: Bietet detaillierte Logs, wenn es mit der Option -dl ausgeführt wird. Es schaltet auch die Variable FORCE_REBUILD automatisch um, je nachdem, ob es das erste Mal ausgeführt wird oder nicht.
- Ausgaben: Speichert gesammelte Daten im Verzeichnis info_cache_<DATUM> und erstellt nach erfolgreichem Abschluss eine Marker-Datei.
# Python-Skript (generate_ingress_reports.py)
- Zweck: Verarbeitet die gesammelten Daten und generiert Markdown-Berichte, die die Ingress-Konfigurationen für jeden Cluster zusammenfassen.
- Logging: Bietet detaillierte Logs, wenn es mit der Option -dl ausgeführt wird.
- Ausgaben: Generiert Markdown-Dateien im Verzeichnis 'ergebnisse'.

