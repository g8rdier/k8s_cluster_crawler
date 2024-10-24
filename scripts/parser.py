#!/usr/bin/env python3
import json
import os
import argparse
import logging
import sys
from tabulate import tabulate

def configure_logging(detailed):
    """
    Configures the logging level based on user selection.
    """
    if detailed:
        logging.basicConfig(level=logging.INFO)
    else:
        logging.basicConfig(level=logging.WARNING)

def extract_ingress_info(json_data, timestamp):
    """
    Extracts relevant Ingress information from the given JSON data.
    """
    ingress_info = []
    for item in json_data.get('items', []):
        metadata = item.get('metadata', {})
        spec = item.get('spec', {})
        status = item.get('status', {})

        namespace = metadata.get('namespace', 'N/A')
        name = metadata.get('name', 'N/A')

        logging.info(f"Extracting data for Namespace: {namespace}, Name: {name}")

        hosts = ", ".join(rule.get('host', 'N/A') for rule in spec.get('rules', []))
        if not hosts:
            logging.warning(f"Warning: Missing Hosts for Ingress '{name}' in Namespace '{namespace}'.")

        address = ", ".join(lb.get('ip', 'N/A') for lb in status.get('loadBalancer', {}).get('ingress', []))
        if not address:
            logging.warning(f"Warning: Missing IP Address for Ingress '{name}' in Namespace '{namespace}'.")

        ports = set()
        if 'tls' in spec:
            ports.add("443")
        for rule in spec.get('rules', []):
            http_paths = rule.get('http', {}).get('paths', [])
            for path in http_paths:
                backend = path.get('backend', {})
                service = backend.get('service', {})
                port = service.get('port', {}).get('number', '80')
                ports.add(str(port))

        ports_str = ", ".join(ports) if ports else "80"

        ingress_info.append([namespace, name, hosts, address, ports_str, timestamp])
    return ingress_info

def extract_pod_info(json_data, timestamp):
    """
    Extracts relevant Pod information from the given JSON data.
    """
    pod_info = []
    for item in json_data.get('items', []):
        metadata = item.get('metadata', {})
        spec = item.get('spec', {})
        status = item.get('status', {})

        namespace = metadata.get('namespace', 'N/A')
        name = metadata.get('name', 'N/A')
        node_name = spec.get('nodeName', 'N/A')
        containers = spec.get('containers', [])
        images = ", ".join(container.get('image', 'N/A') for container in containers)
        kubernetes_version = status.get('kubernetesVersion', 'N/A')

        logging.info(f"Extracting Pod data for Namespace: {namespace}, Name: {name}, Node: {node_name}, Image(s): {images}")

        pod_info.append([namespace, name, images, node_name, kubernetes_version, timestamp])
    return pod_info

def generate_markdown_table(data, headers, output_file, title):
    """
    Generates a Markdown file with a table displaying the extracted information.

    :param data: List of extracted information
    :param headers: Table headers
    :param output_file: Path to the output Markdown file
    :param title: Title for the Markdown content
    """
    if not data:
        logging.warning(f"No data to generate the Markdown file for {title}.")
        return

    table = tabulate(data, headers, tablefmt="pipe")
    markdown_content = f"# {title}\n\n{table}\n"

    with open(output_file, 'w', encoding='utf-8') as file:
        file.write(markdown_content)

    logging.info(f"Markdown file created at {output_file}.")

def main():
    parser = argparse.ArgumentParser(description="Parses Kubernetes JSON data and generates Markdown output.")
    parser.add_argument('--pods', action='store_true', help="Process pod data.")
    parser.add_argument('--ingress', action='store_true', help="Process ingress data.")
    parser.add_argument('-dl', action='store_true', help="Enable detailed logging.")
    parser.add_argument('--output_file', required=True, help="Path to the output Markdown file.")
    parser.add_argument('--cluster_name', required=False, help="Name of the cluster.")
    parser.add_argument('--timestamp', required=False, help="Timestamp of data collection.")
    args = parser.parse_args()

    configure_logging(args.dl)

    # Read JSON input from stdin
    try:
        json_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        logging.error(f"Failed to parse JSON input: {e}")
        sys.exit(1)

    if args.pods:
        pod_info = extract_pod_info(json_data, args.timestamp)
        title = args.cluster_name if args.cluster_name else "Cluster Information"
        generate_markdown_table(
            pod_info,
            ["Namespace", "Pod Name", "Image", "Node Name", "Kubernetes Version", "Zeitstempel"],
            output_file=args.output_file,
            title=title
        )
    elif args.ingress:
        ingress_info = extract_ingress_info(json_data, args.timestamp)
        title = args.cluster_name if args.cluster_name else "Cluster Information"
        generate_markdown_table(
            ingress_info,
            ["Namespace", "Name", "Hosts", "Address", "Ports", "Zeitstempel"],
            output_file=args.output_file,
            title=title
        )
    else:
        logging.error("No data type specified. Use --pods or --ingress.")
        sys.exit(1)

if __name__ == "__main__":
    main()

