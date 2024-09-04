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
    """
    if detailed:
        logging.basicConfig(level=logging.INFO)
    else:
        logging.basicConfig(level=logging.WARNING)

def read_json_file(file_path):
    """
    Liest eine JSON-Datei und gibt die Daten als Python-Datenstruktur zurück.
    """
    with open(file_path, 'r', encoding='utf-8') as file:
        return json.load(file)

def extract_ingress_info(json_data):
    """
    Extrahiert relevante Ingress-Informationen aus den gegebenen JSON-Daten und führt Validierungsprüfungen durch.
    """
    ingress_info = []
    for item in json_data['items']:
        namespace = item['metadata']['namespace']
        name = item['metadata']['name']
        
        logging.info(f"Extrahiere Daten für Namespace: {namespace}, Name: {name}")
        
        hosts = ", ".join(rule.get('host', 'N/A') for rule in item.get('spec', {}).get('rules', []))
        if 'N/A' in hosts or not hosts:
            logging.warning(f"Warnung: Fehlende Hosts für Ingress '{name}' im Namespace '{namespace}'.")

        address = ", ".join(lb.get('ip', 'N/A') for lb in item.get('status', {}).get('loadBalancer', {}).get('ingress', []))
        if not address:
            logging.warning(f"Warnung: Fehlende IP-Adresse für Ingress '{name}' im Namespace '{namespace}'.")

        ports = set()
        if 'tls' in item.get('spec', {}):
            ports.add("443")
        for rule in item.get('spec', {}).get('rules', []):
            for path in rule.get('http', {}).get('paths', []):
                service_port = path.get('backend', {}).get('service', {}).get('port', {}).get('number', '80')
                ports.add(str(service_port))
        
        ports_str = ", ".join(ports) if ports else "80"
        if not ports_str:
            logging.warning(f"Warnung: Keine Ports für Ingress '{name}' im Namespace '{namespace}' gefunden.")
        
        ingress_info.append([namespace, name, hosts, address, ports_str])
    return ingress_info
    
def get_kubernetes_version():
    """
    Ruft die Kubernetes-Server-Version mit 'kubectl' ab.
    """
    try:
        result = subprocess.run(["kubectl", "version", "--output=json"], capture_output=True, text=True)
        version_info = json.loads(result.stdout)
        return version_info['serverVersion']['gitVersion']
    except Exception as e:
        logging.warning(f"Fehler beim Abrufen der Kubernetes-Version: {e}")
        return "N/A"

def extract_pod_info(json_data):
    """
    Extrahiert relevante Pod-Informationen aus den gegebenen JSON-Daten.
    """
    pod_info = [] 
    for item in json_data['items']:
        namespace = item['metadata']['namespace']
        name = item['metadata']['name']
        node_name = item['spec'].get('nodeName', 'N/A')
        containers = item['spec'].get('containers', [])
        images = ", ".join(container.get('image', 'N/A') for container in containers)
        kubernetes_version = item.get('kubernetesVersion', 'N/A')
        
        logging.info(f"Extrahiere Pod-Daten für Namespace: {namespace}, Name: {name}, Node: {node_name}, Image(s): {images}")
        
        pod_info.append([namespace, name, images, node_name, kubernetes_version])
    return pod_info


def generate_markdown_table(data, headers, cluster_name, output_dir, suffix):
    """
    Generiert eine Markdown-Datei mit einer Tabelle, die die extrahierten Informationen darstellt.
    
    :param data: Liste mit den extrahierten Informationen
    :param headers: Tabellen-Header
    :param cluster_name: Name des Clusters, für den die Tabelle generiert wird
    :param output_dir: Verzeichnis, in dem die Markdown-Datei gespeichert wird
    :param suffix: Suffix für den Dateinamen ("_ingress" oder "_pods")
    """
    table = tabulate(data, headers, tablefmt="pipe")
    markdown_content = f"# Übersicht für Cluster: {cluster_name} ({suffix.strip('_')})\n\n{table}\n"
    
    output_file = os.path.join(output_dir, f"{cluster_name}{suffix}.md")
    with open(output_file, 'w', encoding='utf-8') as file:
        file.write(markdown_content)
    
    print(f"Markdown-Datei für Cluster '{cluster_name}' ({suffix.strip('_')}) erstellt.")

def process_all_clusters(info_cache_dir, results_dir):
    """
    Verarbeitet alle Cluster im angegebenen Cache-Verzeichnis, extrahiert die Ingress- und Pod-Informationen 
    und erstellt separate Markdown-Dateien für Ingress und Pods für jeden Cluster.
    """
    if not os.path.exists(results_dir):
        os.makedirs(results_dir)
    
    processed_clusters = set()
    issues = []

    for filename in os.listdir(info_cache_dir):
        if filename.endswith("_ingress.json"):
            cluster_name = filename.split("_")[0]
            ingress_file_path = os.path.join(info_cache_dir, filename)
            pod_file_path = os.path.join(info_cache_dir, filename.replace("_ingress", "_pods"))
            
            cluster_prefix = cluster_name.split('-')[0]
            processed_clusters.add(cluster_prefix)
            
            ingress_json_data = read_json_file(ingress_file_path)
            pod_json_data = read_json_file(pod_file_path) if os.path.exists(pod_file_path) else None
            
            ingress_info = extract_ingress_info(ingress_json_data)
            pod_info = extract_pod_info(pod_json_data) if pod_json_data else []
            
            for info in ingress_info:
                if 'N/A' in info[2] or 'N/A' in info[3]:
                    issues.append((cluster_name, info))
            
            generate_markdown_table(ingress_info, ["Namespace", "Name", "Hosts", "Adresse", "Ports"], cluster_name, results_dir, "_ingress")
            if pod_info:
                generate_markdown_table(pod_info, ["Namespace", "Pod Name", "Image", "Node Name", "Kubernetes Version"], cluster_name, results_dir, "_pods")
    
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

    print("\nHinweis: Du kannst detailliertes Logging aktivieren, indem du das Skript mit der Option '-dl' ausführst.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Verarbeitet Kubernetes Ingress- und Pod-Daten und generiert separate Markdown-Berichte.")
    parser.add_argument('-dl', action='store_true', help="Aktiviert detailliertes Logging.")
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

