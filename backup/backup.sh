#!/usr/bin/env bash

# Bash Settings For Safety And DevOps Best Practices
set -euo pipefail
IFS=$'\n\t'

# Configuration Variables
STACK_DIR="/home/ubuntu/lemma/observability-stack"

# Load environment variables if .env file exists
if [ -f "${STACK_DIR}/.env" ]; then
  # shellcheck disable=SC1090
  source "${STACK_DIR}/.env"
fi

BACKUP_DIR="${STACK_DIR}/backup/archive"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Target Volumes to Backup
VOLUMES=(
  "lemma_prometheus_data"
  "lemma_loki_data"
  "lemma_grafana_data"
)

# Colors For Log Output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]$(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]$(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]$(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

# Print Colored ASCII Banner
print_banner() {
  echo -e "${CYAN}"
  echo "  _      ______ __  __ __  __          "
  echo " | |    |  ____|  \/  |  \/  |   /\    "
  echo " | |    | |__  | \  / | \  / |  /  \   "
  echo " | |    |  __| | |\/| | |\/| | / /\ \  "
  echo " | |____| |____| |  | | |  | |/ ____ \ "
  echo " |______|______|_|  |_|_|  |_/_/    \_\ "
  echo "            Observability Stack        "
  echo -e "${NC}"
}

# Initialization
mkdir -p "${BACKUP_DIR}"

# Function: Backup Configuration Files
backup_configs() {
  log_info "Starting configuration files backup..."
  local config_archive="${BACKUP_DIR}/config_${TIMESTAMP}.tar.gz"
  
  tar -czf "${config_archive}" \
    -C "${STACK_DIR}" \
    .env \
    docker-compose.yml \
    prometheus/ \
    loki/ \
    promtail/ \
    grafana/ \
    dashboards/
    
  log_info "Config backup saved to: ${config_archive}"
}

# Function: Backup Docker Volumes
backup_volumes() {
  log_info "Starting Docker volumes backup..."
  
  for vol in "${VOLUMES[@]}"; do
    # Verify If Volume Exists
    if ! docker volume inspect "${vol}" >/dev/null 2>&1; then
      log_warn "Volume ${vol} does not exist. Skipping."
      continue
    fi
    
    log_info "Backing up volume: ${vol}..."
    local vol_archive="${BACKUP_DIR}/${vol}_${TIMESTAMP}.tar.gz"
    
    # Run A Temporary Alpine Container to Compress Data Safely
    docker run --rm \
      -v "${vol}:/volume_data:ro" \
      -v "${BACKUP_DIR}:/backup_dest" \
      alpine tar -czf "/backup_dest/$(basename "${vol_archive}")" -C /volume_data .
      
    log_info "Volume backup saved to: ${vol_archive}"
  done
}

# Function: Prune Old Backups
prune_old_backups() {
  log_info "Pruning backups older than ${RETENTION_DAYS} days..."
  find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +"${RETENTION_DAYS}" -exec rm -f {} \;
  log_info "Pruning completed."
}

# Execution
main() {
  print_banner
  log_info "Starting Lemma Observability Stack Backup Routine"
  
  # Ensure Docker Is Accessible
  if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH. Volumes cannot be backed up."
    exit 1
  fi
  
  backup_configs
  backup_volumes
  prune_old_backups
  
  log_info "Lemma Observability Stack Backup Routine Finished Successfully"
}

main "$@"
