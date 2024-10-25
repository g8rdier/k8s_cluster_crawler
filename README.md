# Cluster-Scraper und Datenerfassungspipeline

Dieses Projekt ist ein Kubernetes-Cluster-Scraper und eine Datenerfassungspipeline, die Informationen über Kubernetes-Pods und Ingresses von mehreren Clustern sammelt. Die Daten werden gesammelt, in Markdown-Format geparst und im Repository zur späteren Analyse gespeichert.

## Funktionen

- **Scraped Kubernetes-Cluster-Daten** (Pods, Ingresses) von mehreren Clustern.
- **Parsed die gesammelten Daten** in strukturierte Markdown-Dateien (`.md`).
- **Automatische Ausführung einmal wöchentlich** (Montag um 8 Uhr) über eine CI/CD-Pipeline in GitLab.
- **Detaillierte Protokollierung** für Transparenz während des Scraping-Prozesses.
- **Speichert die Daten** für jeden Cluster mit zugehörigen Zeitstempeln.
- **Unterstützt manuelles und automatisches Auslösen** der CI/CD-Pipeline bei Änderungen im `main`-Branch.

## Komponenten

### 1. `crawler.sh`
Das Hauptskript, das für die folgenden Aufgaben verantwortlich ist:
- Abrufen von Daten von jedem Kubernetes-Cluster (Pods und Ingresses).
- Aufruf des Python-Parsers zur Umwandlung der Rohdaten in Markdown-Format.
- Speichern der Ausgaben in den angegebenen Verzeichnissen.
- Automatisches Pushen der gesammelten Daten in das GitLab-Repository mit einer Commit-Nachricht, die den Zeitstempel enthält.

### 2. `parser.py`
Ein Python-Skript, das:
- Die gesammelten JSON-Daten aus den Kubernetes-Clustern verarbeitet.
- Relevante Informationen über Pods und Ingresses extrahiert.
- Die Daten in Markdown-Tabellen formatiert.
- Einen Zeitstempel hinzufügt, der angibt, wann die Daten erfasst wurden.

### 3. `.gitlab-ci.yml`
Die CI/CD-Pipeline-Konfiguration, die:
- Automatisch das Skript `crawler.sh` jeden Montag um 8 Uhr ausführt.
- Manuelles Auslösen unterstützt und auf Änderungen im `main`-Branch reagiert.
- Artefakte speichert, die die vom Scraper generierten Markdown-Dateien enthalten.

## Einrichtung

### Voraussetzungen
- **Zugriff auf mehrere Kubernetes-Cluster.**
- **Installierte Tools:** `kubectl`, `yq`, `python3`, `pip3`.
- **GitLab zur Automatisierung mit CI/CD.**
- **GitLab Personal Access Token** (zum Pushen der Daten zurück ins Repository).
- **Die `kubeconfig`-Dateien** für jeden Kubernetes-Cluster.

### Umgebungsvariablen
Stelle sicher, dass die folgenden Umgebungsvariablen in deiner CI/CD-Pipeline (GitLab-Projekteinstellungen unter **Settings > CI/CD > Variables**) gesetzt sind:
- `fttc_tdf01_kubeconfig`, `fttc_tds01_kubeconfig`, `fttc_tf01_kubeconfig` etc., die das Base64-kodierte `kubeconfig` für jeden Cluster enthalten.
- `PUSH_BOM_PAGES` zur Authentifizierung und zum Pushen der generierten Markdown-Dateien zurück ins Repository.

### Installation

1. **Repository klonen**:
   ```bash
   git clone https://git.f-i-ts.de/devops-services/toolchain/develop/tc-cluster-crawler.git
   cd tc-cluster-crawler

2. **Abhängigkeiten installieren**:

Installiere die erforderlichen Abhängigkeiten für den Python-Parser:
```bash
pip3 install tabulate
```

Stelle sicher, dass `yq` verfügbar ist, entweder durch manuelle Installation oder durch automatische Installation über die CI/CD-Pipeline:
