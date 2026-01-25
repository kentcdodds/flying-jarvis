#!/bin/bash
set -e

# Initialize config file if it doesn't exist
CONFIG_DIR="${CLAWDBOT_STATE_DIR:-/data}"
CONFIG_FILE="$CONFIG_DIR/clawdbot.json"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Copy default config if config file doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found at $CONFIG_FILE"
  echo "Creating default config from template..."
  cp /app/default-config.json "$CONFIG_FILE"
  
  # Replace placeholder values with environment variables if set
  if [ -n "${DISCORD_GUILD_ID}" ]; then
    echo "Setting Discord Guild ID from environment variable..."
    sed -i "s/YOUR_GUILD_ID/${DISCORD_GUILD_ID}/g" "$CONFIG_FILE"
  fi
  
  echo "Default config created at $CONFIG_FILE"
  echo "You can customize this config via the UI or by editing the file directly"
fi

# Execute the CMD from Dockerfile
exec "$@"
