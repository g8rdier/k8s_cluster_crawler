# Kubernetes Cluster Crawler

This project is a Kubernetes cluster crawler and data collection pipeline that gathers information about Kubernetes pods and ingresses from multiple clusters. The data is collected, formatted in Markdown, and stored in the repository for later analysis.

## Features

- Scrapes Kubernetes cluster data (Pods, Ingresses) from multiple clusters
- Parses collected data into structured Markdown format
- Automatic daily execution at 3 AM UTC via GitHub Actions
- Detailed logging for transparency during scraping process
- Stores data for each cluster with corresponding timestamps
- Supports manual and automated execution via GitHub Actions
- Cross-platform support (Linux, macOS, Windows)

## Components

### 1. crawler.sh
The main script responsible for:
- Retrieving data from each Kubernetes cluster (Pods and Ingresses)
- Calling the Python parser to convert raw data to Markdown format
- Storing output in specified directories
- Automatically pushing collected data to GitHub repository with timestamped commits

### 2. parser.py
A Python script that:
- Processes collected JSON data from Kubernetes clusters
- Extracts relevant information about Pods and Ingresses
- Formats data into Markdown tables
- Includes timestamp indicating when data was collected

### 3. GitHub Actions Workflow
Handles automated execution:
- Runs daily at 3 AM UTC
- Manages dependencies via Poetry
- Collects and commits data automatically

## Installation

### Prerequisites

1. **Git**:
   - **Windows**: Download from [git-scm.com](https://git-scm.com/download/win)
   - **macOS**: `brew install git` or download from [git-scm.com](https://git-scm.com/download/mac)
   - **Linux**: 
     ```bash
     # Debian/Ubuntu
     sudo apt-get install git
     # Fedora
     sudo dnf install git
     # Arch Linux
     sudo pacman -S git
     ```

2. **Python 3.11+**:
   - **Windows**: 
     - Download from [Python.org](https://www.python.org/downloads/) or
     - Use winget: `winget install Python.3.11`
   - **macOS**: 
     - `brew install python@3.11` or
     - Download from [Python.org](https://www.python.org/downloads/mac)
   - **Linux**:
     ```bash
     # Debian/Ubuntu
     sudo apt-get install python3.11
     # Fedora
     sudo dnf install python3.11
     # Arch Linux
     sudo pacman -S python
     ```

3. **kubectl**:
   - **Windows**:
     ```powershell
     # Using chocolatey
     choco install kubernetes-cli
     # Or using winget
     winget install Kubernetes.kubectl
     ```
   - **macOS**:
     ```bash
     brew install kubectl
     ```
   - **Linux**:
     ```bash
     # Debian/Ubuntu
     sudo apt-get install kubectl
     # Fedora
     sudo dnf install kubectl
     # Arch Linux
     sudo pacman -S kubectl
     ```

4. **Poetry**:
   - **All platforms**:
     ```bash
     # Windows (PowerShell)
     (Invoke-WebRequest -Uri https://install.python-poetry.org -UseBasicParsing).Content | python -

     # macOS/Linux
     curl -sSL https://install.python-poetry.org | python3 -
     ```

### Setup

1. Clone the repository:
```bash
git clone https://github.com/g8rdier/k8s_cluster_crawler.git
cd k8s_cluster_crawler
```

2. Install dependencies:
```bash
# Windows/macOS/Linux
poetry install --no-root
```

3. Configure your clusters in `scripts/docs/cluster_map.yaml`

## Usage

### Running Locally

#### Linux/macOS
```bash
./scripts/docs/cluster_crawler.sh -dl
```

#### Windows (PowerShell)
```powershell
# First time only: Make script executable
chmod +x ./scripts/docs/cluster_crawler.sh

# Run the crawler
bash ./scripts/docs/cluster_crawler.sh -dl
```

### Development & Testing

#### Local GitHub Actions Testing

1. Install `act`:
   - **Windows**: 
     ```powershell
     choco install act-cli
     # Or
     scoop install act
     ```
   - **macOS**: 
     ```bash
     brew install act
     ```
   - **Linux**:
     ```bash
     # Using curl
     curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
     # Or using snap
     sudo snap install act
     ```

2. Start Docker:
   - **Windows/macOS**: Start Docker Desktop
   - **Linux**: `sudo systemctl start docker`

3. Run the workflow:
```bash
# For amd64 systems (most computers)
act -j collect_data --container-architecture linux/amd64

# For arm64 systems (M1/M2 Macs, some Linux)
act -j collect_data --container-architecture linux/arm64
```

## Configuration

The `scripts/docs/cluster_map.yaml` contains cluster configurations:
```yaml
clusters:
  prod-cluster-1:
    uuid: cluster-prod-1-uuid
  stage-cluster-1:
    uuid: cluster-stage-1-uuid
  # ... add your clusters here
```

## Troubleshooting

### Windows
- If you get line ending errors:
  ```powershell
  git config --global core.autocrlf false
  ```
- If PowerShell blocks script execution:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

### Linux
- If you get permission denied for Docker:
  ```bash
  sudo usermod -aG docker $USER
  newgrp docker
  ```

### macOS
- If you get "command not found" errors:
  ```bash
  export PATH="$HOME/.local/bin:$PATH"  # For Poetry
  ```

## License

MIT License - see LICENSE file for details

## Development Setup

### IDE Configuration

This project includes VS Code settings for optimal Python development. When using VS Code:

1. Install the Python extension
2. Open the project
3. VS Code should automatically:
   - Detect the Poetry virtual environment
   - Enable proper import resolution
   - Configure Python path settings

For other IDEs, ensure they are configured to use the Poetry virtual environment at:
```bash
$(poetry env info --path)
```




