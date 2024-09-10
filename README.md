# Cluster-Daten-Sammlung und Berichtserstellung

Dieses Repository enthält eine Sammlung von Skripten, die dazu dienen, Daten aus mehreren Kubernetes-Clustern zu sammeln und detaillierte Markdown-Berichte zu generieren. Der Prozess umfasst zwei Hauptskripte:

1. **Bash-Skript (`crawl_clusters.sh`)**: Dieses Skript sammelt Daten aus den angegebenen Kubernetes-Clustern.
2. **Python-Skript (`generate_ingress_reports.py`)**: Dieses Skript verarbeitet die gesammelten Daten und generiert für jeden Cluster ingress-und pod-spezifische Markdownberichte.


## Voraussetzungen

Bevor die Skripte ausgeführt werden, stelle sicher, dass die folgenden Werkzeuge auf deinem System installiert sind:

- **Kubernetes CLI (`kubectl`)**: Wird verwendet, um mit Kubernetes-Clustern zu interagieren.
- **FI-TS Cloudctl**: Wird verwendet, um mit Kubernetes-Clustern zu interagieren: https://github.com/fi-ts/cloudctl.
- **Python 3.x**: Das Python-Skript erfordert Python 3.x.
- Python Abhängigkeiten: Installiere die Python-lib `tabulate`:
```
pip install -r requirements.txt
```


## Nutzungsanleitung

### 1. Repository klonen

Klone das Repository auf deinen lokalen Rechner:

```
git clone https://git.f-i-ts.de/devops-services/toolchain/develop/tc-cluster-crawler.git
cd tc-cluster-crawler
```

### 2. Bash-Skript ausführen
Das Skript crawl_clusters.sh sammelt Daten aus den in dem Skript angegebenen Kubernetes-Clustern. Es wechselt die Kontexte zu jedem Cluster, ruft die erforderlichen Informationen ab und speichert sie im Verzeichnis `info_cache_<DATUM>`.

Erster Lauf des Skripts
Vor erstem Lauf des Skripts einmal mit `cloudctl login` authentifizieren.
Anschließend führst du das Skript mit dem `-dl`-Flag für detaillierte Logs aus:

```
./crawl_clusters.sh -dl
```

- `-dl`: Aktiviert detailliertes Logging, das ausführlichere Ausgaben für Debugging- und Überwachungszwecke bereitstellt.

# Nachfolgende Ausführungen
Bei nachfolgenden Ausführungen verwendet das Skript die zwischengespeicherten Daten, sofern die Umgebungsvariable FORCE_REBUILD nicht auf `1`gesetzt ist. Du kannst das Skript ohne Flags ausführen: 
```
./crawl_clusters.sh
```

Das Skript wechselt automatisch die `FORCE_REBUILD`-Variable, je nachdem, ob es zuvor ausgeführt wurde. Bei erfolgreicher Ausführung wird eine Marker-Datei (`cluster_crawler_marker`) erstellt.


### 3. Python-Skript ausführen


Sobald die Daten gesammelt wurden, kannst du das Python-Skript ausführen, um Markdown-Berichte zu generieren: 
```
python3 generate_ingress_reports.py -dl
```
- `-dl`: Aktiviert detailliertes Logging im Python-Skript.

Dieses Skript verarbeitet die gesammelten Daten aus dem Verzeichnis `info_cache_<DATUM>` und speichert die Berichte im Verzeichnis `ergebnisse`.




### Schritt 4: Berichte anzeigen
Nach der Ausführung des Python-Skripts findest du die generierten Markdown-Dateien im Verzeichnis `ergebnisse`, sortiert nach Cluster-Namen:
```
ergebnisse/
├── fttc-demo1_ingress.md
├── fttc-pf01_ingress.md
```

# Fehlersuche
- **Authentifizierungsprobleme**: Stelle sicher, dass du korrekt mit `cloudctl login`authentifiziert bist.
- **Force Rebuild**: Setze die Umgebungsvariable `FORCE_REBUILD`auf `1`, wenn das Skript keine neuen Daten sammelt. 
- Detailliertes Logging: Verwende `dl`für detaillierte Logs bei der Fehlersuche.


## Beispielablauf

1. Bash-Skript ausführen, um Cluster-Daten zu sammeln:
```
./crawl_clusters.sh -dl
```

2. Python-Skript ausführen, um Berichte zu generieren:
```
python3 generate_ingress_reports.py -dl
```

3. Die generierten Berichte im Verzeichnis `ergebnisse`anzeigen.


