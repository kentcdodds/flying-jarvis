#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="/opt/gordon-matrix/backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
tar czf "${BACKUP_DIR}/data-${TIMESTAMP}.tar.gz" -C /opt/gordon-matrix data
find "${BACKUP_DIR}" -name "data-*.tar.gz" -mtime +30 -delete
echo "[$(date)] Backup done: data-${TIMESTAMP}.tar.gz"
