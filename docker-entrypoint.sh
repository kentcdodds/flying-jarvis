#!/usr/bin/env bash
set -euo pipefail

trim_value() {
  printf "%s" "${1:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

is_truthy() {
  case "$(trim_value "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_startup_log_line() {
  local line
  line="$1"
  printf '%s\n' "$line" >> "$STARTUP_SCRIPT_LOG"
}

write_startup_directory_guide() {
  local guide_file
  guide_file="${STARTUP_SCRIPT_DIR}/00-startup-directory-guide.ignored.sh"
  if [ -f "$guide_file" ]; then
    return
  fi

  cat > "$guide_file" <<'EOF'
#!/usr/bin/env bash
# Startup scripts directory guide
#
# This file is intentionally ignored because its filename contains ".ignored.".
# The startup loader in /app/docker-entrypoint.sh skips any file with ".ignored."
# in the filename.
#
# How /data/startup works:
# - All regular files with a ".sh" filename are launched at boot.
# - Executable ".sh" files run directly.
# - Non-executable ".sh" files run via "bash <file>".
# - Scripts are launched in lexical filename order as background sidecars.
# - Script output and lifecycle events are written to:
#     /data/logs/startup-scripts.log
# - Startup PID snapshot is written to:
#     /data/logs/startup-scripts.current.tsv
#
# Recommended naming:
# - 10-*.sh, 20-*.sh, 30-*.sh ... to control ordering.
# - Include ".ignored." in filename for notes/examples you do not want to run.
EOF
  chmod 0644 "$guide_file"
}

launch_startup_script() {
  local entry name pid started_at
  entry="$1"
  name="$(basename "$entry")"
  started_at="$(timestamp_utc)"

  (
    local status
    set +e
    if [ -x "$entry" ]; then
      "$entry"
      status="$?"
    else
      bash "$entry"
      status="$?"
    fi
    append_startup_log_line "$(printf '%s\tevent=exit\tname=%s\tpid=%s\tstatus=%s\tentry=%s' "$(timestamp_utc)" "$name" "$BASHPID" "$status" "$entry")"
    exit "$status"
  ) \
    > >(
      while IFS= read -r line || [ -n "$line" ]; do
        append_startup_log_line "$(printf '%s\tstream=stdout\tname=%s\tentry=%s\tmsg=%s' "$(timestamp_utc)" "$name" "$entry" "$line")"
      done
    ) \
    2> >(
      while IFS= read -r line || [ -n "$line" ]; do
        append_startup_log_line "$(printf '%s\tstream=stderr\tname=%s\tentry=%s\tmsg=%s' "$(timestamp_utc)" "$name" "$entry" "$line")"
      done
    ) &

  pid="$!"
  append_startup_log_line "$(printf '%s\tevent=start\tname=%s\tpid=%s\tentry=%s' "$started_at" "$name" "$pid" "$entry")"
  printf '%s\t%s\t%s\t%s\n' "$started_at" "$name" "$pid" "$entry" >> "$STARTUP_SCRIPT_PIDS_FILE"
}

start_startup_scripts() {
  local entries entry name
  mkdir -p "$STARTUP_SCRIPT_DIR" "$STARTUP_LOG_DIR"
  write_startup_directory_guide
  : > "$STARTUP_SCRIPT_LOG"
  : > "$STARTUP_SCRIPT_PIDS_FILE"
  printf '# started_at_utc\tname\tpid\tentry\n' >> "$STARTUP_SCRIPT_PIDS_FILE"

  shopt -s nullglob
  entries=("$STARTUP_SCRIPT_DIR"/*)
  shopt -u nullglob

  if [ "${#entries[@]}" -eq 0 ]; then
    append_startup_log_line "$(printf '%s\tevent=info\tmsg=%s' "$(timestamp_utc)" "no startup scripts found")"
    return
  fi

  mapfile -d '' entries < <(printf '%s\0' "${entries[@]}" | LC_ALL=C sort -z)
  for entry in "${entries[@]}"; do
    name="$(basename "$entry")"
    if [ ! -f "$entry" ]; then
      append_startup_log_line "$(printf '%s\tevent=skip\tname=%s\treason=%s\tentry=%s' "$(timestamp_utc)" "$name" "not-a-regular-file" "$entry")"
      continue
    fi
    if [[ "$name" == *".ignored."* ]]; then
      append_startup_log_line "$(printf '%s\tevent=skip\tname=%s\treason=%s\tentry=%s' "$(timestamp_utc)" "$name" "filename-ignored" "$entry")"
      continue
    fi
    if [[ "$name" != *.sh ]]; then
      append_startup_log_line "$(printf '%s\tevent=skip\tname=%s\treason=%s\tentry=%s' "$(timestamp_utc)" "$name" "not-shell-script" "$entry")"
      continue
    fi
    launch_startup_script "$entry"
  done
}

trim_gateway_token() {
  local raw trimmed
  raw="${OPENCLAW_GATEWAY_TOKEN:-}"
  if [ -z "$raw" ]; then
    return
  fi

  trimmed="$(trim_value "$raw")"
  if [ "$trimmed" != "$raw" ]; then
    echo "Trimming whitespace from OPENCLAW_GATEWAY_TOKEN."
    export OPENCLAW_GATEWAY_TOKEN="$trimmed"
  fi
}

start_cloudflare_tunnel() {
  if ! command -v cloudflared >/dev/null 2>&1; then
    return
  fi

  local token
  token="$(trim_value "${CLOUDFLARE_TUNNEL_TOKEN:-}")"
  if [ -z "$token" ]; then
    echo "Cloudflare tunnel token missing or blank; skipping cloudflared."
    return
  fi

  echo "Starting Cloudflare Tunnel..."
  cloudflared tunnel --no-autoupdate run --token "$token" &
}

CONFIG_DIR="${OPENCLAW_STATE_DIR:-/data}"
APP_DIR="${OPENCLAW_APP_DIR:-/app}"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
CREDENTIALS_DIR="$CONFIG_DIR/credentials"
SESSIONS_DIR="$CONFIG_DIR/agents/main/sessions"
WORKSPACE_SEED_DIR="/root/.openclaw/workspace"
PERSISTENT_WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-$CONFIG_DIR/workspace}"
STARTUP_SCRIPT_DIR="${STARTUP_DIR:-/data/startup}"
STARTUP_LOG_DIR="${STARTUP_LOG_DIR:-/data/logs}"
STARTUP_SCRIPT_LOG="${STARTUP_SCRIPT_LOG:-${STARTUP_LOG_DIR}/startup-scripts.log}"
STARTUP_SCRIPT_PIDS_FILE="${STARTUP_SCRIPT_PIDS_FILE:-${STARTUP_LOG_DIR}/startup-scripts.current.tsv}"

trim_gateway_token
start_cloudflare_tunnel

mkdir -p "$CONFIG_DIR" "$CREDENTIALS_DIR" "$SESSIONS_DIR"
chmod 700 "$CONFIG_DIR" "$CREDENTIALS_DIR" || true

if [ ! -d "$PERSISTENT_WORKSPACE" ]; then
  mkdir -p "$PERSISTENT_WORKSPACE"
  if [ -d "$WORKSPACE_SEED_DIR" ]; then
    # Seed copy is best-effort; startup should continue even if some files fail to copy.
    cp -r "$WORKSPACE_SEED_DIR"/. "$PERSISTENT_WORKSPACE"/ || true
  else
    echo "Workspace seed directory not found at $WORKSPACE_SEED_DIR; skipping seed copy."
  fi
fi

if is_truthy "${RESET_CONFIG:-}"; then
  if [ -f "$CONFIG_FILE" ]; then
    echo "RESET_CONFIG is set; removing existing config file..."
    rm -f "$CONFIG_FILE"
    echo "Existing config removed"
  else
    echo "RESET_CONFIG is set, but no config file exists at $CONFIG_FILE"
  fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found at $CONFIG_FILE"
  echo "Creating default config from template..."
  cp "$APP_DIR/default-config.json" "$CONFIG_FILE"
  echo "Default config created at $CONFIG_FILE"
fi

OPENCLAW_CONFIG_FILE="$CONFIG_FILE" OPENCLAW_STATE_DIR="$CONFIG_DIR" \
  node "$APP_DIR/scripts/sync-runtime-config.mjs"

if [ -f "$CONFIG_FILE" ]; then
  echo "OpenClaw config ready at $CONFIG_FILE"
else
  echo "Warning: Config file not found at $CONFIG_FILE"
fi

start_startup_scripts

exec "$@"
