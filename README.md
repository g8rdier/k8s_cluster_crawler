# Kubernetes Cluster Crawler

A tool designed to collect data from multiple Kubernetes clusters and generate detailed Markdown reports. The process involves two main scripts.

## Features

- **Crawls Kubernetes Cluster Data** (Pods, Ingresses) from multiple clusters
- **Parses collected data** into structured Markdown files (`.md`)
- **Automated daily execution** (at 3 AM) via CI/CD pipeline
- **Detailed logging** for transparency during the crawling process
- **Stores data** for each cluster with associated timestamps
- **Supports manual and automated triggers** of the CI/CD pipeline on `main` branch changes

## Components

### 1. `crawler.sh`
The main script responsible for:
- Fetching data from each Kubernetes cluster (pods and ingresses)
- Calling the Python parser to convert raw data to Markdown format
- Storing outputs in specified directories
- Automatically pushing collected data to the repository with timestamped commit messages

### 2. `parser.py`
A Python script that:
- Processes collected JSON data from Kubernetes clusters
- Extracts relevant information about pods and ingresses
- Formats data into Markdown tables
- Adds timestamps indicating when data was collected

## Setup

### Prerequisites
- **Access to multiple Kubernetes clusters**
- **Required tools:** `kubectl`, `yq`, `python3`, `pip3`
- **Git repository for automation**
- **Git Personal Access Token** (for pushing data back to repository)
- **`kubeconfig` files** for each Kubernetes cluster

### Environment Variables
Ensure the following environment variables are set in your CI/CD pipeline:
- `CLUSTER_1_KUBECONFIG`, `CLUSTER_2_KUBECONFIG`, etc., containing Base64-encoded `kubeconfig` for each cluster
- `PUSH_TOKEN` for authentication and pushing generated Markdown files back to repository

### Installation

1. **Clone Repository**:
```bash
git clone https://github.com/g8rdier/k8s_cluster_crawler.git
cd k8s_cluster_crawler
```

2. **Install Dependencies**:
```bash
pip3 install tabulate
```

Ensure `yq` is available:
```bash
wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64
chmod +x /usr/local/bin/yq
```

## Usage

1. **Local Manual Execution**:
```bash
./scripts/cluster_crawler.sh -dl
```

2. **Output Structure**:
The crawler generates Markdown files (`.md`) for each cluster containing:

Pod Information:
- Namespace
- Pod Name
- Image
- Node Name
- Kubernetes Version

Ingress Information:
- Namespace
- Name
- Hosts
- Address
- Ports

Each file includes a timestamp indicating when the data was collected.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.




