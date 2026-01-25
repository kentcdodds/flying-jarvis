#!/bin/bash
set -e

trim_value() {
  printf "%s" "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

is_truthy() {
  local raw trimmed
  raw="${1:-}"
  trimmed="$(trim_value "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$trimmed" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

maybe_trim_gateway_token() {
  local raw trimmed
  raw="${CLAWDBOT_GATEWAY_TOKEN:-}"
  if [ -z "$raw" ]; then
    return
  fi
  trimmed="$(trim_value "$raw")"
  if [ "$trimmed" != "$raw" ]; then
    echo "Trimming whitespace from CLAWDBOT_GATEWAY_TOKEN."
  fi
  export CLAWDBOT_GATEWAY_TOKEN="$trimmed"
}

maybe_enable_insecure_control_ui() {
  if ! is_truthy "${CLAWDBOT_CONTROL_UI_ALLOW_INSECURE_AUTH:-}"; then
    return
  fi
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found at $CONFIG_FILE; skipping insecure control UI toggle."
    return
  fi

  CONFIG_FILE="$CONFIG_FILE" node - <<'NODE'
const fs = require("fs");

const configPath = process.env.CONFIG_FILE;
if (!configPath) {
  console.error("CONFIG_FILE not set; skipping insecure control UI toggle.");
  process.exit(0);
}
if (!fs.existsSync(configPath)) {
  console.error(`Config file not found at ${configPath}; skipping insecure control UI toggle.`);
  process.exit(0);
}

let raw;
try {
  raw = fs.readFileSync(configPath, "utf8");
} catch (err) {
  console.error(`Failed to read config at ${configPath}: ${err}`);
  process.exit(1);
}

let config;
try {
  config = JSON.parse(raw);
} catch (err) {
  console.error(`Failed to parse config JSON at ${configPath}: ${err}`);
  process.exit(1);
}

config.gateway = config.gateway ?? {};
config.gateway.controlUi = config.gateway.controlUi ?? {};
if (config.gateway.controlUi.allowInsecureAuth !== true) {
  config.gateway.controlUi.allowInsecureAuth = true;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log("Enabled gateway.controlUi.allowInsecureAuth in config.");
} else {
  console.log("gateway.controlUi.allowInsecureAuth already true; leaving config as-is.");
}
NODE
}

# Start Cloudflare Tunnel if configured
if command -v cloudflared >/dev/null 2>&1; then
  cloudflare_token_raw="${CLOUDFLARE_TUNNEL_TOKEN:-}"
  cloudflare_token_trimmed="$(trim_value "$cloudflare_token_raw")"
  if [ -n "$cloudflare_token_trimmed" ]; then
    echo "Starting Cloudflare Tunnel..."
    cloudflared tunnel --no-autoupdate run --token "$cloudflare_token_trimmed" &
  else
    echo "Cloudflare tunnel token missing or blank; skipping cloudflared."
  fi
fi

maybe_trim_gateway_token

# Initialize config file if it doesn't exist
CONFIG_DIR="${CLAWDBOT_STATE_DIR:-/data}"
CONFIG_FILE="$CONFIG_DIR/clawdbot.json"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Handle config reset if requested
if is_truthy "${RESET_CONFIG:-}"; then
  if [ -f "$CONFIG_FILE" ]; then
    echo "RESET_CONFIG is set; removing existing config file..."
    rm -f "$CONFIG_FILE"
    echo "Existing config removed"
  else
    echo "RESET_CONFIG is set, but no config file exists at $CONFIG_FILE"
  fi
fi

# Copy default config if config file doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found at $CONFIG_FILE"
  echo "Creating default config from template..."
  cp /app/default-config.json "$CONFIG_FILE"
  echo "Default config created at $CONFIG_FILE"
  echo "You can customize this config via the UI or by editing the file directly"
fi

# Replace placeholder values with environment variables if set
# This runs on every startup to ensure placeholders get replaced
if [ -n "${DISCORD_GUILD_ID}" ]; then
  if grep -q "YOUR_GUILD_ID" "$CONFIG_FILE"; then
    echo "Replacing YOUR_GUILD_ID placeholder with Discord Guild ID from environment variable..."
    sed -i "s/YOUR_GUILD_ID/${DISCORD_GUILD_ID}/g" "$CONFIG_FILE"
    echo "Discord Guild ID updated in config"
  fi
fi

maybe_enable_insecure_control_ui

# Log the clawdbot config file on startup
if [ -f "$CONFIG_FILE" ]; then
  echo "=== Clawdbot Config File ($CONFIG_FILE) ==="
  cat "$CONFIG_FILE"
  echo "=== End of Clawdbot Config File ==="
else
  echo "Warning: Config file not found at $CONFIG_FILE"
fi

# Execute the CMD from Dockerfile
exec "$@"
