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

## Development & Testing

### Local Testing with `act`

To test the GitHub Actions workflow locally, first install `act`:

#### macOS
```bash
brew install act
```

#### Linux
```bash
# Using curl
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Or using snap
sudo snap install act
```

#### Windows
```powershell
# Using Chocolatey
choco install act-cli

# Or using scoop
scoop install act
```

### Prerequisites

1. Docker:
   - **Windows**: Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)
   - **macOS**: Install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop)
   - **Linux**: Install Docker using your distribution's package manager:
     ```bash
     # Ubuntu/Debian
     sudo apt-get update
     sudo apt-get install docker.io

     # Fedora
     sudo dnf install docker

     # Arch Linux
     sudo pacman -S docker
     ```

2. Python 3.11+:
   - **Windows**: Download from [Python.org](https://www.python.org/downloads/) or use winget:
     ```powershell
     winget install Python.3.11
     ```
   - **macOS**:
     ```bash
     brew install python@3.11
     ```
   - **Linux**:
     ```bash
     # Ubuntu/Debian
     sudo apt-get install python3.11

     # Fedora
     sudo dnf install python3.11

     # Arch Linux
     sudo pacman -S python
     ```

3. Poetry:
   ```bash
   # All platforms (in bash/powershell)
   curl -sSL https://install.python-poetry.org | python3 -
   ```

### Running Tests

1. Start Docker:
   - **Windows/macOS**: Start Docker Desktop
   - **Linux**: 
     ```bash
     sudo systemctl start docker
     ```

2. Run the GitHub Actions workflow locally:
```bash
# For Windows/macOS/Linux on amd64
act -j collect_data --container-architecture linux/amd64

# For Linux on arm64
act -j collect_data --container-architecture linux/arm64
```

### Manual Testing

1. Install dependencies:
```bash
# All platforms
poetry install --no-root
```

2. Run the crawler:
```bash
# Linux/macOS
./scripts/cluster_crawler.sh -dl

# Windows (PowerShell)
.\scripts\cluster_crawler.sh -dl
```

### Test Configuration

The `scripts/docs/cluster_map.yaml` contains example cluster configurations for testing:
- Production clusters (prod-cluster-1, prod-cluster-2, etc.)
- Staging clusters (stage-cluster-1, stage-cluster-2)
- Development clusters (dev-cluster-1, dev-cluster-2)
- Test clusters (test-cluster-1, test-cluster-2)

Replace these with your actual cluster configurations for production use.

### Troubleshooting

- **Windows**: If you encounter line ending issues, configure Git:
  ```bash
  git config --global core.autocrlf false
  ```

- **Linux**: If you get permission denied for Docker:
  ```bash
  sudo usermod -aG docker $USER
  newgrp docker
  ```

- **All Platforms**: If Poetry isn't found in PATH:
  - **Windows**: Add `%APPDATA%\Python\Scripts` to PATH
  - **Linux/macOS**: Add `$HOME/.local/bin` to PATH




