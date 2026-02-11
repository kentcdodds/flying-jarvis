#!/usr/bin/env bash
set -euo pipefail

STARTUP_DIR="${STARTUP_DIR:-/app/startup}"

echo "[startup] startup dir: ${STARTUP_DIR}"

if [ ! -d "$STARTUP_DIR" ]; then
  echo "[startup] startup dir does not exist; skipping: ${STARTUP_DIR}"
  exit 0
fi

shopt -s nullglob
entries=("$STARTUP_DIR"/*)
shopt -u nullglob

if [ "${#entries[@]}" -eq 0 ]; then
  echo "[startup] no startup files found; nothing to run"
  exit 0
fi

mapfile -d '' sorted_entries < <(printf '%s\0' "${entries[@]}" | LC_ALL=C sort -z)

daemon_pids=()
daemon_names=()

for entry in "${sorted_entries[@]}"; do
  name="$(basename "$entry")"

  if [[ "$name" == _* ]]; then
    echo "[startup] skip ${name} (leading underscore)"
    continue
  fi

  if [ ! -f "$entry" ]; then
    echo "[startup] skip ${name} (not a regular file)"
    continue
  fi

  if [ ! -x "$entry" ]; then
    echo "[startup] skip ${name} (not executable)"
    continue
  fi

  if [[ "$name" == *".daemon."* ]]; then
    echo "[startup] daemon ${name}"
    "$entry" &
    pid="$!"
    daemon_pids+=("$pid")
    daemon_names+=("$name")
    echo "[startup] daemon started ${name} (pid=${pid})"
    continue
  fi

  echo "[startup] oneshot ${name}"
  "$entry"
  echo "[startup] oneshot complete ${name}"
done

if [ "${#daemon_pids[@]}" -eq 0 ]; then
  echo "[startup] no daemon files started; startup complete"
  exit 0
fi

echo "[startup] waiting for ${#daemon_pids[@]} daemon(s)"
if wait -n -p exited_pid; then
  status=0
else
  status="$?"
fi

exited_name="unknown"
for index in "${!daemon_pids[@]}"; do
  pid="${daemon_pids[$index]}"
  if [ "$pid" -eq "$exited_pid" ]; then
    exited_name="${daemon_names[$index]}"
    break
  fi
done

if [ "$status" -eq 0 ]; then
  echo "[startup] daemon exited cleanly ${exited_name} (pid=${exited_pid})"
else
  echo "[startup] daemon exited non-zero ${exited_name} (pid=${exited_pid}, status=${status})"
fi

exit "$status"
