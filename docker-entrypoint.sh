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
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
CREDENTIALS_DIR="$CONFIG_DIR/credentials"
SESSIONS_DIR="$CONFIG_DIR/agents/main/sessions"
WORKSPACE_SEED_DIR="/root/.openclaw/workspace"
PERSISTENT_WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-$CONFIG_DIR/workspace}"

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
  cp /app/default-config.json "$CONFIG_FILE"
  echo "Default config created at $CONFIG_FILE"
fi

OPENCLAW_CONFIG_FILE="$CONFIG_FILE" OPENCLAW_STATE_DIR="$CONFIG_DIR" \
  node /app/scripts/sync-runtime-config.mjs

if [ -f "$CONFIG_FILE" ]; then
  echo "OpenClaw config ready at $CONFIG_FILE"
else
  echo "Warning: Config file not found at $CONFIG_FILE"
fi

exec "$@"
