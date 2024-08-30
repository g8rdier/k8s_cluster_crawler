import json
import os
import argparse
from datetime import datetime
from tabulate import tabulate
import logging

# Erwartete Cluster-Präfixe, die verarbeitet werden sollen
EXPECTED_CLUSTERS = {"fttc", "ftctl"}

def configure_logging(detailed):
    """
    Konfiguriert das Logging-Level basierend auf der Benutzerauswahl.
    
    :param detailed: Boolesche Option, um detailliertes Logging zu aktivieren oder zu deaktivieren
    """
    if detailed:
        logging.basicConfig(level=logging.INFO)
    else:
        logging.basicConfig(level=logging.WARNING)

def read_json_file(file_path):
    """
    Liest eine JSON-Datei und gibt die Daten als Python-Datenstruktur zurück.
    
    :param file_path: Pfad zur JSON-Datei
    :return: Inhalt der JSON-Datei als Python-Datenstruktur
    """
    with open(file_path, 'r', encoding='utf-8') as file:
        return json.load(file)

def extract_ingress_info(json_data):
    """
    Extrahiert relevante Ingress-Informationen aus den gegebenen JSON-Daten und führt Validierungsprüfungen durch.
    
    :param json_data: JSON-Daten, die Ingress-Informationen enthalten
    :return: Liste mit extrahierten Ingress-Informationen
    """
    ingress_info = []
    for item in json_data['items']:
        namespace = item['metadata']['namespace']
        name = item['metadata']['name']
        
        logging.info(f"Extrahiere Daten für Namespace: {namespace}, Name: {name}")
        
        # Extrahiert die Hosts, wobei fehlende 'host'-Schlüssel als 'N/A' gekennzeichnet werden
        hosts = ", ".join(rule.get('host', 'N/A') for rule in item.get('spec', {}).get('rules', []))
        
        if 'N/A' in hosts or not hosts:
            logging.warning(f"Warnung: Fehlende Hosts für Ingress '{name}' im Namespace '{namespace}'.")
        
        # Extrahiert die IP-Adresse der LoadBalancer, falls vorhanden, sonst 'N/A'
        address = ", ".join(lb.get('ip', 'N/A') for lb in item.get('status', {}).get('loadBalancer', {}).get('ingress', []))
        
        if not address:
            logging.warning(f"Warnung: Fehlende IP-Adresse für Ingress '{name}' im Namespace '{namespace}'.")
        
        # Bestimmt die Ports, die durch diesen Ingress genutzt werden
        ports = set()
        if 'tls' in item.get('spec', {}):
            ports.add("443")  # Standardmäßig Port 443 hinzufügen, wenn TLS verwendet wird
        for rule in item.get('spec', {}).get('rules', []):
            for path in rule.get('http', {}).get('paths', []):
                service_port = path.get('backend', {}).get('service', {}).get('port', {}).get('number', '80')
                ports.add(str(service_port))
        
        ports_str = ", ".join(ports) if ports else "80"
        
        if not ports_str:
            logging.warning(f"Warnung: Keine Ports für Ingress '{name}' im Namespace '{namespace}' gefunden.")
        
        ingress_info.append([namespace, name, hosts, address, ports_str])
    return ingress_info

def generate_markdown_table(ingress_info, cluster_name, output_dir):
    """
    Generiert eine Markdown-Datei mit einer Tabelle, die die extrahierten Ingress-Informationen darstellt.
    
    :param ingress_info: Liste mit den extrahierten Ingress-Informationen
    :param cluster_name: Name des Clusters, für den die Tabelle generiert wird
    :param output_dir: Verzeichnis, in dem die Markdown-Datei gespeichert wird
    """
    headers = ["Namespace", "Name", "Hosts", "Adresse", "Ports"]
    table = []
    
    for entry in ingress_info:
        if 'N/A' in entry[2]:
            entry[2] += " (Warnung: Fehlende Hosts)"
        if 'N/A' in entry[3]:
            entry[3] += " (Warnung: Fehlende Adresse)"
        
        table.append(entry)
    
    markdown_table = tabulate(table, headers, tablefmt="pipe")
    markdown_content = f"# Ingress-Übersicht für Cluster: {cluster_name}\n\n{markdown_table}\n"
    
    output_file = os.path.join(output_dir, f"{cluster_name}_ingress.md")
    with open(output_file, 'w', encoding='utf-8') as file:
        file.write(markdown_content)
    
    print(f"Markdown-Datei für Cluster '{cluster_name}' erstellt.")

def process_all_clusters(info_cache_dir, results_dir):
    """
    Verarbeitet alle Cluster im angegebenen Cache-Verzeichnis, extrahiert die Ingress-Informationen 
    und erstellt Markdown-Dateien für jeden Cluster. Führt zudem eine Überprüfung durch, ob alle erwarteten Cluster verarbeitet wurden.
    
    :param info_cache_dir: Verzeichnis, das die Cache-Dateien für die Cluster enthält
    :param results_dir: Verzeichnis, in dem die Ergebnisse (Markdown-Dateien) gespeichert werden
    """
    if not os.path.exists(results_dir):
        os.makedirs(results_dir)
    
    processed_clusters = set()
    issues = []

    for filename in os.listdir(info_cache_dir):
        if filename.endswith("_ingress.json"):
            cluster_name = filename.split("_")[0]
            file_path = os.path.join(info_cache_dir, filename)
            cluster_prefix = cluster_name.split('-')[0]
            processed_clusters.add(cluster_prefix)
            json_data = read_json_file(file_path)
            ingress_info = extract_ingress_info(json_data)
            
            for info in ingress_info:
                if 'N/A' in info[2] or 'N/A' in info[3]:
                    issues.append((cluster_name, info))
            
            generate_markdown_table(ingress_info, cluster_name, results_dir)
    
    missed_clusters = EXPECTED_CLUSTERS - processed_clusters
    if missed_clusters:
        print(f"Warnung: Die folgenden erwarteten Cluster wurden nicht verarbeitet: {', '.join(missed_clusters)}")
    else:
        print("Alle erwarteten Cluster wurden verarbeitet.")
    
    if issues:
        print("\nZusammenfassung der Ingresses mit Problemen:")
        for cluster_name, issue in issues:
            print(f"Cluster: {cluster_name}, Namespace: {issue[0]}, Name: {issue[1]}, Hosts: {issue[2]}, Adresse: {issue[3]}")
    else:
        print("Keine Probleme in den Ingresses gefunden.")

    print("\nHinweis: Du kannst detailliertes Logging aktivieren, indem du das Skript mit der Option '--dl' ausführst.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Verarbeitet Kubernetes Ingress-Daten und generiert Markdown-Berichte.")
    parser.add_argument('--dl', action='store_true', help="Aktiviert detailliertes Logging.")
    args = parser.parse_args()

    configure_logging(args.dl)

    today_date = datetime.now().strftime("%Y%m%d")
    base_cache_dir = "info_cache_"
    cache_dirs = [d for d in os.listdir('.') if d.startswith(base_cache_dir)]
    latest_cache_dir = max(cache_dirs, default=f"{base_cache_dir}{today_date}")
    INFO_CACHE_DIR = latest_cache_dir
    RESULTS_DIR = "ergebnisse"

    try:
        process_all_clusters(INFO_CACHE_DIR, RESULTS_DIR)
    except FileNotFoundError as e:
        print(f"Fehler: {e}. Das Verzeichnis '{INFO_CACHE_DIR}' existiert nicht. Bitte überprüfen Sie das Datum oder den Verzeichnispfad.")

