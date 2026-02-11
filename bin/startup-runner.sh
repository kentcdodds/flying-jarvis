#!/usr/bin/env bash
set -euo pipefail

STARTUP_DIR="${STARTUP_DIR:-/data/startup}"
STARTUP_LOG_DIR="${STARTUP_LOG_DIR:-/data/logs}"
STARTUP_RUNNER_LOG="${STARTUP_RUNNER_LOG:-${STARTUP_LOG_DIR}/startup-runner.log}"
STARTUP_PROCESS_LOG="${STARTUP_PROCESS_LOG:-${STARTUP_LOG_DIR}/startup-processes.log}"
STARTUP_ACTIVE_DAEMONS_FILE="${STARTUP_ACTIVE_DAEMONS_FILE:-${STARTUP_LOG_DIR}/startup-daemons.current.tsv}"
STARTUP_LOG_MAX_BYTES="${STARTUP_LOG_MAX_BYTES:-1048576}"
STARTUP_LOG_BACKUPS="${STARTUP_LOG_BACKUPS:-5}"
STARTUP_BOOTSTRAP_EXAMPLE="${STARTUP_BOOTSTRAP_EXAMPLE:-1}"
STARTUP_BOOTSTRAP_OPENCLAW="${STARTUP_BOOTSTRAP_OPENCLAW:-1}"

is_positive_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

normalize_log_config() {
  if ! is_positive_integer "$STARTUP_LOG_MAX_BYTES"; then
    STARTUP_LOG_MAX_BYTES=1048576
  fi
  if ! is_positive_integer "$STARTUP_LOG_BACKUPS"; then
    STARTUP_LOG_BACKUPS=5
  fi
}

rotate_file_if_needed() {
  local file file_size idx
  file="$1"
  if [ ! -f "$file" ]; then
    return
  fi

  file_size="$(wc -c < "$file" | tr -d '[:space:]')"
  if ! is_positive_integer "$file_size"; then
    return
  fi
  if [ "$file_size" -lt "$STARTUP_LOG_MAX_BYTES" ]; then
    return
  fi

  if [ "$STARTUP_LOG_BACKUPS" -ge 1 ]; then
    rm -f "${file}.${STARTUP_LOG_BACKUPS}"
    for ((idx=STARTUP_LOG_BACKUPS-1; idx>=1; idx--)); do
      if [ -f "${file}.${idx}" ]; then
        mv "${file}.${idx}" "${file}.$((idx+1))"
      fi
    done
    mv "$file" "${file}.1"
  fi
  : > "$file"
}

append_log_line() {
  local file line
  file="$1"
  line="$2"
  rotate_file_if_needed "$file"
  printf '%s\n' "$line" >> "$file"
}

log() {
  local message line
  message="[startup] $*"
  line="$(timestamp_utc) ${message}"
  printf '%s\n' "$message"
  append_log_line "$STARTUP_RUNNER_LOG" "$line"
}

log_process_event() {
  local event name pid status entry
  event="$1"
  name="$2"
  pid="$3"
  status="${4:-}"
  entry="${5:-}"
  append_log_line \
    "$STARTUP_PROCESS_LOG" \
    "$(timestamp_utc)\tevent=${event}\tname=${name}\tpid=${pid}\tstatus=${status}\tentry=${entry}"
}

run_entry_with_mirrored_logs() {
  local entry
  entry="$1"
  "$entry" \
    > >(mirror_stream_to_runner_log "stdout") \
    2> >(mirror_stream_to_runner_log "stderr" >&2)
}

mirror_stream_to_runner_log() {
  local stream line
  stream="$1"
  while IFS= read -r line || [ -n "$line" ]; do
    append_log_line "$STARTUP_RUNNER_LOG" "$(timestamp_utc) [startup:${stream}] ${line}"
    printf '%s\n' "$line"
  done
}

write_bootstrap_example() {
  local example_file
  example_file="${STARTUP_DIR}/_example-openclaw.daemon.sh"
  if [ -f "$example_file" ]; then
    return
  fi

  cat > "$example_file" <<'EOF'
#!/usr/bin/env bash
# set -euo pipefail
#
# This file is ignored because it starts with "_".
# To enable it:
#   mv /data/startup/_example-openclaw.daemon.sh /data/startup/80-openclaw.daemon.sh
#   chmod +x /data/startup/80-openclaw.daemon.sh
#
# Files containing ".daemon." run in background.
# Other executable files run synchronously as oneshots.
#
# exec openclaw gateway start
EOF
  chmod 0644 "$example_file"
  log "wrote bootstrap example script: ${example_file}"
}

write_bootstrap_openclaw_daemon() {
  local daemon_file
  daemon_file="${STARTUP_DIR}/80-openclaw.daemon.sh"
  if [ -f "$daemon_file" ]; then
    return
  fi

  cat > "$daemon_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec openclaw gateway start
EOF
  chmod +x "$daemon_file"
  log "wrote bootstrap daemon script: ${daemon_file}"
}

normalize_log_config
mkdir -p "$STARTUP_LOG_DIR"
touch "$STARTUP_RUNNER_LOG" "$STARTUP_PROCESS_LOG"
rotate_file_if_needed "$STARTUP_RUNNER_LOG"
rotate_file_if_needed "$STARTUP_PROCESS_LOG"

log "startup dir: ${STARTUP_DIR}"
if [ ! -d "$STARTUP_DIR" ]; then
  mkdir -p "$STARTUP_DIR"
  log "created startup dir: ${STARTUP_DIR}"
  if [ "$STARTUP_BOOTSTRAP_OPENCLAW" = "1" ]; then
    write_bootstrap_openclaw_daemon
  fi
  if [ "$STARTUP_BOOTSTRAP_EXAMPLE" = "1" ]; then
    write_bootstrap_example
  fi
fi

shopt -s nullglob
entries=("$STARTUP_DIR"/*)
shopt -u nullglob

if [ "${#entries[@]}" -eq 0 ]; then
  log "no startup files found; nothing to run"
  exit 0
fi

mapfile -d '' sorted_entries < <(printf '%s\0' "${entries[@]}" | LC_ALL=C sort -z)

daemon_pids=()
daemon_names=()
daemon_entries=()
daemon_started_at=()
daemon_active=()

write_active_daemons_file() {
  local temp_file index
  temp_file="${STARTUP_ACTIVE_DAEMONS_FILE}.tmp"
  {
    printf '# started_at_utc\tname\tpid\tentry\n'
    for index in "${!daemon_pids[@]}"; do
      if [ "${daemon_active[$index]}" != "1" ]; then
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' \
        "${daemon_started_at[$index]}" \
        "${daemon_names[$index]}" \
        "${daemon_pids[$index]}" \
        "${daemon_entries[$index]}"
    done
  } > "$temp_file"
  mv "$temp_file" "$STARTUP_ACTIVE_DAEMONS_FILE"
}

write_active_daemons_file

for entry in "${sorted_entries[@]}"; do
  name="$(basename "$entry")"

  if [[ "$name" == _* ]]; then
    log "skip ${name} (leading underscore)"
    continue
  fi

  if [ ! -f "$entry" ]; then
    log "skip ${name} (not a regular file)"
    continue
  fi

  if [ ! -x "$entry" ]; then
    log "skip ${name} (not executable)"
    continue
  fi

  if [[ "$name" == *".daemon."* ]]; then
    log "daemon ${name}"
    run_entry_with_mirrored_logs "$entry" &
    pid="$!"
    daemon_pids+=("$pid")
    daemon_names+=("$name")
    daemon_entries+=("$entry")
    daemon_started_at+=("$(timestamp_utc)")
    daemon_active+=("1")
    log_process_event "start" "$name" "$pid" "" "$entry"
    write_active_daemons_file
    log "daemon started ${name} (pid=${pid})"
    continue
  fi

  log "oneshot ${name}"
  if run_entry_with_mirrored_logs "$entry"; then
    log "oneshot complete ${name}"
  else
    status="$?"
    log "oneshot failed ${name} (status=${status})"
    exit "$status"
  fi
done

if [ "${#daemon_pids[@]}" -eq 0 ]; then
  log "no daemon files started; startup complete"
  exit 0
fi

log "daemon status file: ${STARTUP_ACTIVE_DAEMONS_FILE}"
log "process event log: ${STARTUP_PROCESS_LOG}"
log "waiting for ${#daemon_pids[@]} daemon(s)"
wait_status=0
for index in "${!daemon_pids[@]}"; do
  pid="${daemon_pids[$index]}"
  name="${daemon_names[$index]}"
  entry="${daemon_entries[$index]}"

  if wait "$pid"; then
    daemon_active[$index]="0"
    write_active_daemons_file
    log_process_event "exit" "$name" "$pid" "0" "$entry"
    log "daemon exited cleanly ${name} (pid=${pid})"
    continue
  fi

  status="$?"
  daemon_active[$index]="0"
  write_active_daemons_file
  log_process_event "exit" "$name" "$pid" "$status" "$entry"
  log "daemon exited non-zero ${name} (pid=${pid}, status=${status})"
  if [ "$wait_status" -eq 0 ]; then
    wait_status="$status"
  fi
done

exit "$wait_status"
