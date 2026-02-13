#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/opt/gordon-matrix/backups"
PASSPHRASE_FILE="/opt/gordon-matrix/.backup-passphrase"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/data-${TIMESTAMP}.tar.gz.gpg"

if [ ! -f "$PASSPHRASE_FILE" ]; then
  echo "[$(date)] ERROR: Passphrase file not found at ${PASSPHRASE_FILE}" >&2
  echo "Create it once with: openssl rand -hex 32 > ${PASSPHRASE_FILE} && chmod 600 ${PASSPHRASE_FILE}" >&2
  exit 1
fi

tar czf - -C /opt/gordon-matrix data \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSPHRASE_FILE" \
        -o "$BACKUP_FILE"

find "${BACKUP_DIR}" -name "data-*.tar.gz.gpg" -mtime +30 -delete
echo "[$(date)] Encrypted backup done: $(basename "$BACKUP_FILE")"
