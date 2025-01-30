#!/usr/bin/env python3

import json
import os
import sys
from datetime import datetime, timezone
from typing import Dict, List

try:
    from tabulate import tabulate
except ImportError:
    print("Error: tabulate package not found. Please install it using: poetry install")
    sys.exit(1)


def generate_markdown_table(headers: List[str], data: List[List[str]]) -> str:
    """Generate a markdown table manually if tabulate fails."""
    if not data:
        return "No data available\n"
    
    # Create header
    table = "| " + " | ".join(headers) + " |\n"
    # Add separator
    table += "| " + " | ".join(["---" for _ in headers]) + " |\n"
    # Add data
    for row in data:
        table += "| " + " | ".join(str(cell) for cell in row) + " |\n"
    
    return table


def load_json_file(file_path: str) -> Dict:
    """Load and parse a JSON file."""
    try:
        with open(file_path, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading JSON file {file_path}: {e}")
        return {}


def format_timestamp() -> str:
    """Get current timestamp in Berlin timezone."""
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def parse_pods(pods_data: Dict) -> List[List[str]]:
    """Parse pods data into a table format."""
    table_data = []
    if not pods_data.get("items"):
        return table_data

    for pod in pods_data["items"]:
        metadata = pod.get("metadata", {})
        status = pod.get("status", {})
        
        name = metadata.get("name", "N/A")
        namespace = metadata.get("namespace", "N/A")
        phase = status.get("phase", "N/A")
        pod_ip = status.get("podIP", "N/A")
        
        table_data.append([name, namespace, phase, pod_ip])
    
    return table_data


def parse_ingresses(ingress_data: Dict) -> List[List[str]]:
    """Parse ingress data into a table format."""
    table_data = []
    if not ingress_data.get("items"):
        return table_data

    for ingress in ingress_data["items"]:
        metadata = ingress.get("metadata", {})
        spec = ingress.get("status", {}).get("loadBalancer", {}).get("ingress", [{}])[0]
        
        name = metadata.get("name", "N/A")
        namespace = metadata.get("namespace", "N/A")
        hostname = spec.get("hostname", "N/A")
        ip = spec.get("ip", "N/A")
        
        table_data.append([name, namespace, hostname, ip])
    
    return table_data


def create_markdown_table(headers: List[str], data: List[List[str]]) -> str:
    """Create a markdown table with headers and data."""
    try:
        return tabulate(data, headers=headers, tablefmt="pipe")
    except Exception:
        return generate_markdown_table(headers, data)


def main():
    if len(sys.argv) != 4:
        print("Usage: parser.py <pods_json> <ingress_json> <output_md>")
        sys.exit(1)

    pods_file = sys.argv[1]
    ingress_file = sys.argv[2]
    output_file = sys.argv[3]

    # Load JSON data
    pods_data = load_json_file(pods_file)
    ingress_data = load_json_file(ingress_file)

    # Parse data
    pods_table = parse_pods(pods_data)
    ingress_table = parse_ingresses(ingress_data)

    # Create markdown content
    content = f"# Cluster Status Report\n\n"
    content += f"Generated: {format_timestamp()}\n\n"
    
    content += "## Pods\n\n"
    content += create_markdown_table(
        ["Name", "Namespace", "Status", "IP"],
        pods_table
    )
    content += "\n\n"
    
    content += "## Ingresses\n\n"
    content += create_markdown_table(
        ["Name", "Namespace", "Hostname", "IP"],
        ingress_table
    )

    # Write to file
    try:
        os.makedirs(os.path.dirname(output_file), exist_ok=True)
        with open(output_file, "w") as f:
            f.write(content)
    except Exception as e:
        print(f"Error writing markdown file: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

