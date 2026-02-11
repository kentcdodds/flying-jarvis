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
STARTUP_TERM_GRACE_SECONDS="${STARTUP_TERM_GRACE_SECONDS:-10}"
OPENCLAW_APP_DIR="${OPENCLAW_APP_DIR:-/app}"
RUNNER_PID="$$"

prepend_path_if_dir() {
  local dir
  dir="$1"
  if [ -d "$dir" ]; then
    case ":${PATH:-}:" in
      *":${dir}:"*) ;;
      *) PATH="${dir}:${PATH:-}" ;;
    esac
  fi
}

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
  if ! is_positive_integer "$STARTUP_TERM_GRACE_SECONDS"; then
    STARTUP_TERM_GRACE_SECONDS=10
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
    "$(printf '%s\tevent=%s\tname=%s\tpid=%s\tstatus=%s\tentry=%s' \
      "$(timestamp_utc)" \
      "$event" \
      "$name" \
      "$pid" \
      "$status" \
      "$entry")"
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

is_pid_running() {
  local pid
  pid="$1"
  kill -0 "$pid" >/dev/null 2>&1
}

is_pid_child_of_runner() {
  local pid ppid
  pid="$1"
  if ! command -v ps >/dev/null 2>&1; then
    return 0
  fi
  ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$ppid" ] && [ "$ppid" = "$RUNNER_PID" ]
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
# exec openclaw gateway run --allow-unconfigured --port 3000 --bind auto
EOF
  chmod 0644 "$example_file"
  log "wrote bootstrap example script: ${example_file}"
}

render_bootstrap_openclaw_daemon() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Managed by /app/bin/startup-runner.sh when STARTUP_BOOTSTRAP_OPENCLAW=1.
# Edit this file to customize startup behavior.
if command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_BIN="$(command -v openclaw)"
elif [ -x "${OPENCLAW_APP_DIR:-/app}/node_modules/.bin/openclaw" ]; then
  OPENCLAW_BIN="${OPENCLAW_APP_DIR:-/app}/node_modules/.bin/openclaw"
elif [ -x "${OPENCLAW_APP_DIR:-/app}/openclaw.mjs" ]; then
  OPENCLAW_BIN="${OPENCLAW_APP_DIR:-/app}/openclaw.mjs"
else
  echo "openclaw binary not found on PATH or at ${OPENCLAW_APP_DIR:-/app}/node_modules/.bin/openclaw or ${OPENCLAW_APP_DIR:-/app}/openclaw.mjs" >&2
  exit 127
fi

exec "$OPENCLAW_BIN" gateway run --allow-unconfigured --port 3000 --bind auto
EOF
}

render_legacy_bootstrap_openclaw_daemon_v1() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec openclaw gateway run --allow-unconfigured --port 3000 --bind auto
EOF
}

render_legacy_bootstrap_openclaw_daemon_v2() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_BIN="$(command -v openclaw)"
elif [ -x "/app/node_modules/.bin/openclaw" ]; then
  OPENCLAW_BIN="/app/node_modules/.bin/openclaw"
else
  echo "openclaw binary not found on PATH or at /app/node_modules/.bin/openclaw" >&2
  exit 127
fi

exec "$OPENCLAW_BIN" gateway run --allow-unconfigured --port 3000 --bind auto
EOF
}

render_legacy_bootstrap_openclaw_daemon_v3() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Managed by /app/bin/startup-runner.sh when STARTUP_BOOTSTRAP_OPENCLAW=1.
# Edit this file to customize startup behavior.
if command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_BIN="$(command -v openclaw)"
elif [ -x "/app/node_modules/.bin/openclaw" ]; then
  OPENCLAW_BIN="/app/node_modules/.bin/openclaw"
else
  echo "openclaw binary not found on PATH or at /app/node_modules/.bin/openclaw" >&2
  exit 127
fi

exec "$OPENCLAW_BIN" gateway run --allow-unconfigured --port 3000 --bind auto
EOF
}

sha256_of_file() {
  local file
  file="$1"
  sha256sum "$file" | awk '{print $1}'
}

sha256_of_stdin() {
  sha256sum | awk '{print $1}'
}

write_bootstrap_openclaw_daemon() {
  local daemon_file existing_hash managed_hash legacy_hash_v1 legacy_hash_v2 legacy_hash_v3
  daemon_file="${STARTUP_DIR}/80-openclaw.daemon.sh"

  managed_hash="$(render_bootstrap_openclaw_daemon | sha256_of_stdin)"
  legacy_hash_v1="$(render_legacy_bootstrap_openclaw_daemon_v1 | sha256_of_stdin)"
  legacy_hash_v2="$(render_legacy_bootstrap_openclaw_daemon_v2 | sha256_of_stdin)"
  legacy_hash_v3="$(render_legacy_bootstrap_openclaw_daemon_v3 | sha256_of_stdin)"

  if [ -f "$daemon_file" ]; then
    existing_hash="$(sha256_of_file "$daemon_file")"
    if [ "$existing_hash" = "$managed_hash" ]; then
      return
    fi
    if [ "$existing_hash" = "$legacy_hash_v1" ] || [ "$existing_hash" = "$legacy_hash_v2" ] || [ "$existing_hash" = "$legacy_hash_v3" ]; then
      render_bootstrap_openclaw_daemon > "$daemon_file"
      chmod +x "$daemon_file"
      log "updated legacy bootstrap daemon script: ${daemon_file}"
      return
    fi
    log "preserving existing custom daemon script: ${daemon_file}"
    return
  fi

  render_bootstrap_openclaw_daemon > "$daemon_file"
  chmod +x "$daemon_file"
  log "wrote bootstrap daemon script: ${daemon_file}"
}

prepend_path_if_dir "${OPENCLAW_APP_DIR}/node_modules/.bin"
prepend_path_if_dir "/root/.bun/bin"
export PATH

normalize_log_config
mkdir -p "$STARTUP_LOG_DIR"
touch "$STARTUP_RUNNER_LOG" "$STARTUP_PROCESS_LOG"
rotate_file_if_needed "$STARTUP_RUNNER_LOG"
rotate_file_if_needed "$STARTUP_PROCESS_LOG"

log "startup dir: ${STARTUP_DIR}"
startup_dir_created=0
if [ ! -d "$STARTUP_DIR" ]; then
  mkdir -p "$STARTUP_DIR"
  startup_dir_created=1
  log "created startup dir: ${STARTUP_DIR}"
fi
if [ "$STARTUP_BOOTSTRAP_OPENCLAW" = "1" ]; then
  write_bootstrap_openclaw_daemon
fi
if [ "$startup_dir_created" = "1" ] && [ "$STARTUP_BOOTSTRAP_EXAMPLE" = "1" ]; then
  write_bootstrap_example
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
wait_status=0
shutdown_requested=0
shutdown_signal=""
shutdown_in_progress=0

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

daemon_index_by_pid() {
  local target_pid index
  target_pid="$1"
  for index in "${!daemon_pids[@]}"; do
    if [ "${daemon_pids[$index]}" = "$target_pid" ]; then
      printf '%s\n' "$index"
      return
    fi
  done
  printf '%s\n' "-1"
}

active_daemon_count() {
  local active index
  active=0
  for index in "${!daemon_active[@]}"; do
    if [ "${daemon_active[$index]}" = "1" ]; then
      active=$((active + 1))
    fi
  done
  printf '%s\n' "$active"
}

forward_signal_to_active_daemons() {
  local signal index pid
  signal="$1"
  for index in "${!daemon_pids[@]}"; do
    if [ "${daemon_active[$index]}" != "1" ]; then
      continue
    fi
    pid="${daemon_pids[$index]}"
    if is_pid_running "$pid"; then
      kill "-${signal}" "$pid" >/dev/null 2>&1 || true
    fi
  done
}

record_daemon_exit() {
  local index status pid name entry
  index="$1"
  status="$2"

  if [ "${daemon_active[$index]}" != "1" ]; then
    return
  fi

  pid="${daemon_pids[$index]}"
  name="${daemon_names[$index]}"
  entry="${daemon_entries[$index]}"
  daemon_active[$index]="0"
  write_active_daemons_file
  log_process_event "exit" "$name" "$pid" "$status" "$entry"
  if [ "$status" -eq 0 ]; then
    log "daemon exited cleanly ${name} (pid=${pid})"
  else
    log "daemon exited non-zero ${name} (pid=${pid}, status=${status})"
  fi
  if [ "$status" -gt "$wait_status" ]; then
    wait_status="$status"
  fi
}

record_non_running_active_daemons() {
  local fallback_status index pid status progress
  fallback_status="$1"
  progress=0
  for index in "${!daemon_pids[@]}"; do
    if [ "${daemon_active[$index]}" != "1" ]; then
      continue
    fi
    pid="${daemon_pids[$index]}"
    if is_pid_running "$pid"; then
      continue
    fi

    if wait "$pid"; then
      status=0
    else
      status="$?"
    fi
    if [ "$status" -eq 127 ]; then
      status="$fallback_status"
    fi
    record_daemon_exit "$index" "$status"
    progress=1
  done
  if [ "$progress" -eq 1 ]; then
    return 0
  fi
  return 1
}

terminate_active_daemons() {
  local reason initial_signal watchdog_pid exited_pid status daemon_index index pid progress_made fallback_status kill_deadline
  reason="$1"
  initial_signal="${2:-TERM}"
  if [ "$(active_daemon_count)" -eq 0 ]; then
    return
  fi

  log "${reason}; requesting daemon shutdown with signal ${initial_signal}"
  forward_signal_to_active_daemons "$initial_signal"
  kill_deadline=$((SECONDS + STARTUP_TERM_GRACE_SECONDS))

  (
    sleep "$STARTUP_TERM_GRACE_SECONDS"
    log "grace period elapsed; force-killing remaining daemons"
    for index in "${!daemon_pids[@]}"; do
      if [ "${daemon_active[$index]}" != "1" ]; then
        continue
      fi
      pid="${daemon_pids[$index]}"
      if is_pid_running "$pid" && is_pid_child_of_runner "$pid"; then
        kill -KILL "$pid" >/dev/null 2>&1 || true
      fi
    done
  ) &
  watchdog_pid="$!"

  while [ "$(active_daemon_count)" -gt 0 ]; do
    exited_pid=""
    if wait -n -p exited_pid; then
      status=0
    else
      status="$?"
    fi
    if [ -z "${exited_pid:-}" ]; then
      fallback_status=0
      if [ "$SECONDS" -ge "$kill_deadline" ]; then
        fallback_status=137
      fi
      if record_non_running_active_daemons "$fallback_status"; then
        progress_made=1
      else
        progress_made=0
      fi
      if [ "$progress_made" -eq 0 ]; then
        sleep 1
      fi
      continue
    fi
    daemon_index="$(daemon_index_by_pid "${exited_pid:-}")"
    if [ "$daemon_index" -ge 0 ]; then
      record_daemon_exit "$daemon_index" "$status"
    fi
  done

  if is_pid_running "$watchdog_pid"; then
    kill "$watchdog_pid" >/dev/null 2>&1 || true
  fi
  wait "$watchdog_pid" >/dev/null 2>&1 || true
}

handle_shutdown_signal() {
  local signal
  signal="$1"
  if [ "$shutdown_in_progress" -eq 1 ]; then
    return
  fi
  shutdown_in_progress=1
  shutdown_requested=1
  shutdown_signal="$signal"
}

write_active_daemons_file
trap 'handle_shutdown_signal TERM' TERM
trap 'handle_shutdown_signal INT' INT
trap 'handle_shutdown_signal QUIT' QUIT

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
    rotate_file_if_needed "$STARTUP_RUNNER_LOG"
    "$entry" \
      > >(mirror_stream_to_runner_log "stdout") \
      2> >(mirror_stream_to_runner_log "stderr" >&2) &
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
    terminate_active_daemons "oneshot failure" TERM
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

while [ "$(active_daemon_count)" -gt 0 ]; do
  if [ "$shutdown_requested" -eq 1 ]; then
    terminate_active_daemons "shutdown requested via SIG${shutdown_signal}" "${shutdown_signal}"
    break
  fi

  exited_pid=""
  if wait -n -p exited_pid; then
    status=0
  else
    status="$?"
  fi

  if [ "$shutdown_requested" -eq 1 ]; then
    terminate_active_daemons "shutdown requested via SIG${shutdown_signal}" "${shutdown_signal}"
    break
  fi

  if [ -z "${exited_pid:-}" ]; then
    if record_non_running_active_daemons 0; then
      progress_made=1
    else
      progress_made=0
    fi
    if [ "$progress_made" -eq 0 ]; then
      sleep 1
    fi
    continue
  fi

  daemon_index="$(daemon_index_by_pid "${exited_pid:-}")"
  if [ "$daemon_index" -lt 0 ]; then
    continue
  fi
  record_daemon_exit "$daemon_index" "$status"
done

exit "$wait_status"
