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
  raw="${OPENCLAW_GATEWAY_TOKEN:-}"
  if [ -z "$raw" ]; then
    return
  fi
  trimmed="$(trim_value "$raw")"
  if [ "$trimmed" != "$raw" ]; then
    echo "Trimming whitespace from OPENCLAW_GATEWAY_TOKEN."
  fi
  export OPENCLAW_GATEWAY_TOKEN="$trimmed"
}

maybe_sync_insecure_control_ui() {
  if [ -z "${OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH+x}" ]; then
    return
  fi

  local desired
  desired="false"
  if is_truthy "${OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH:-}"; then
    desired="true"
  fi

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found at $CONFIG_FILE; skipping control UI auth sync."
    return
  fi

  CONFIG_FILE="$CONFIG_FILE" OPENCLAW_ALLOW_INSECURE_AUTH="$desired" node - <<'NODE'
const fs = require("fs");

const configPath = process.env.CONFIG_FILE;
const desiredAllowInsecureAuth = process.env.OPENCLAW_ALLOW_INSECURE_AUTH === "true";
if (!configPath) {
  console.error("CONFIG_FILE not set; skipping control UI auth sync.");
  process.exit(0);
}
if (!fs.existsSync(configPath)) {
  console.error(`Config file not found at ${configPath}; skipping control UI auth sync.`);
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
if (config.gateway.controlUi.allowInsecureAuth !== desiredAllowInsecureAuth) {
  config.gateway.controlUi.allowInsecureAuth = desiredAllowInsecureAuth;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log(`Set gateway.controlUi.allowInsecureAuth=${desiredAllowInsecureAuth} in config.`);
} else {
  console.log(`gateway.controlUi.allowInsecureAuth already ${desiredAllowInsecureAuth}; leaving config as-is.`);
}
NODE
}

maybe_sync_gateway_port() {
  local desired_port_raw desired_port
  desired_port_raw="${OPENCLAW_GATEWAY_PORT:-}"
  if [ -z "$desired_port_raw" ]; then
    return
  fi

  if ! [[ "$desired_port_raw" =~ ^[0-9]+$ ]]; then
    echo "OPENCLAW_GATEWAY_PORT is not numeric ($desired_port_raw); skipping gateway port sync."
    return
  fi
  desired_port="$desired_port_raw"

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found at $CONFIG_FILE; skipping gateway port sync."
    return
  fi

  CONFIG_FILE="$CONFIG_FILE" OPENCLAW_GATEWAY_PORT="$desired_port" node - <<'NODE'
const fs = require("fs");

const configPath = process.env.CONFIG_FILE;
const desiredPort = Number(process.env.OPENCLAW_GATEWAY_PORT);
if (!configPath || Number.isNaN(desiredPort)) {
  console.error("Missing CONFIG_FILE or OPENCLAW_GATEWAY_PORT; skipping gateway port sync.");
  process.exit(0);
}
if (!fs.existsSync(configPath)) {
  console.error(`Config file not found at ${configPath}; skipping gateway port sync.`);
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
if (config.gateway.port !== desiredPort) {
  config.gateway.port = desiredPort;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log(`Set gateway.port=${desiredPort} in config.`);
} else {
  console.log(`gateway.port already ${desiredPort}; leaving config as-is.`);
}
NODE
}

maybe_sync_discord_plugin_enabled() {
  if [ -z "${DISCORD_BOT_TOKEN+x}" ]; then
    return
  fi

  local desired
  desired="false"
  if [ -n "$(trim_value "${DISCORD_BOT_TOKEN:-}")" ]; then
    desired="true"
  fi

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found at $CONFIG_FILE; skipping discord plugin sync."
    return
  fi

  CONFIG_FILE="$CONFIG_FILE" OPENCLAW_DISCORD_PLUGIN_ENABLED="$desired" node - <<'NODE'
const fs = require("fs");

const configPath = process.env.CONFIG_FILE;
const shouldEnable = process.env.OPENCLAW_DISCORD_PLUGIN_ENABLED === "true";
if (!configPath) {
  console.error("CONFIG_FILE not set; skipping discord plugin sync.");
  process.exit(0);
}
if (!fs.existsSync(configPath)) {
  console.error(`Config file not found at ${configPath}; skipping discord plugin sync.`);
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

config.plugins = config.plugins ?? {};
config.plugins.entries = config.plugins.entries ?? {};
config.plugins.entries.discord = config.plugins.entries.discord ?? {};

if (config.plugins.entries.discord.enabled !== shouldEnable) {
  config.plugins.entries.discord.enabled = shouldEnable;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log(`Set plugins.entries.discord.enabled=${shouldEnable} in config.`);
} else {
  console.log(`plugins.entries.discord.enabled already ${shouldEnable}; leaving config as-is.`);
}
NODE
}

maybe_sync_workspace_path() {
  local desired_workspace
  desired_workspace="${OPENCLAW_WORKSPACE_DIR:-$CONFIG_DIR/workspace}"

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found at $CONFIG_FILE; skipping workspace path sync."
    return
  fi

  CONFIG_FILE="$CONFIG_FILE" OPENCLAW_WORKSPACE_PATH="$desired_workspace" node - <<'NODE'
const fs = require("fs");

const configPath = process.env.CONFIG_FILE;
const desiredWorkspace = process.env.OPENCLAW_WORKSPACE_PATH;
if (!configPath || !desiredWorkspace) {
  console.error("Missing CONFIG_FILE or OPENCLAW_WORKSPACE_PATH; skipping workspace path sync.");
  process.exit(0);
}
if (!fs.existsSync(configPath)) {
  console.error(`Config file not found at ${configPath}; skipping workspace path sync.`);
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

config.agents = config.agents ?? {};
config.agents.defaults = config.agents.defaults ?? {};
if (config.agents.defaults.workspace !== desiredWorkspace) {
  config.agents.defaults.workspace = desiredWorkspace;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log(`Set agents.defaults.workspace=${desiredWorkspace} in config.`);
} else {
  console.log(`agents.defaults.workspace already ${desiredWorkspace}; leaving config as-is.`);
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
CONFIG_DIR="${OPENCLAW_STATE_DIR:-/data}"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
CREDENTIALS_DIR="$CONFIG_DIR/credentials"
SESSIONS_DIR="$CONFIG_DIR/agents/main/sessions"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR" || true

# Persist agent workspace files in the same volume that stores config/session state.
WORKSPACE_SEED_DIR="/root/.openclaw/workspace"
PERSISTENT_WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-$CONFIG_DIR/workspace}"

# First run: seed persistent workspace with default files.
if [ ! -d "$PERSISTENT_WORKSPACE" ]; then
  mkdir -p "$PERSISTENT_WORKSPACE"
  cp -rn "$WORKSPACE_SEED_DIR"/* "$PERSISTENT_WORKSPACE"/ 2>/dev/null || true
fi

# Ensure required runtime directories exist with restrictive permissions.
mkdir -p "$CREDENTIALS_DIR" "$SESSIONS_DIR"
chmod 700 "$CREDENTIALS_DIR" || true

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

maybe_sync_insecure_control_ui
maybe_sync_gateway_port
maybe_sync_discord_plugin_enabled
maybe_sync_workspace_path

# Log config path on startup (without dumping contents)
if [ -f "$CONFIG_FILE" ]; then
  echo "OpenClaw config ready at $CONFIG_FILE"
else
  echo "Warning: Config file not found at $CONFIG_FILE"
fi

# Execute the CMD from Dockerfile
exec "$@"
