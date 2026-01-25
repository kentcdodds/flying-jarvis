# flying-jarvis
Clawdbot running on fly.io

## Setup Instructions

This repository contains the configuration to deploy Clawdbot to Fly.io with automatic deployments via GitHub Actions.

### Prerequisites

- [flyctl CLI](https://fly.io/docs/hands-on/install-flyctl/) installed
- Fly.io account (free tier works)
- Anthropic API key (for Claude access)
- Optional: Discord bot token, Telegram token, etc. for channel integrations
- Optional: Cloudflare Zero Trust account (for tunnel access)

### Initial Deployment

1. **Create the Fly.io app:**
   ```bash
   flyctl apps create flying-jarvis
   ```

2. **Create a persistent volume:**
   ```bash
   flyctl volumes create clawdbot_data --region dfw --size 1
   ```

3. **Set up GitHub Actions secrets:**
   - Go to your repository Settings > Secrets and variables > Actions
   - Add the following repository secrets:
   
   **Required secrets:**
   - `FLY_API_TOKEN` - Get your token with: `flyctl auth token`
   - `FLY_APP_NAME` - Your Fly.io app name (e.g., `flying-jarvis`)
   - `FLY_REGION` - Your Fly.io region (e.g., `dfw`)
   - `CLAWDBOT_GATEWAY_TOKEN` - Generate with: `openssl rand -hex 32`
   - `ANTHROPIC_API_KEY` - Your Anthropic API key (e.g., `sk-ant-...`)
   
   **Optional secrets (add as needed):**
   - `OPENAI_API_KEY` - Your OpenAI API key
   - `GOOGLE_API_KEY` - Your Google API key
   - `DISCORD_BOT_TOKEN` - Your Discord bot token
   - `DISCORD_GUILD_ID` - Your Discord server/guild ID (automatically replaces `YOUR_GUILD_ID` placeholder in config)
   - Add other channel tokens as needed
   - `CLOUDFLARE_TUNNEL_TOKEN` - Cloudflare Tunnel token (for private access)
   - `CLAWDBOT_CONTROL_UI_ALLOW_INSECURE_AUTH` - Set to `true` to allow token-only Control UI auth over tunnels (skips device pairing)

4. **Deploy:**
   - Push to the `main` branch to trigger automatic deployment via GitHub Actions
   - The workflow will automatically sync all secrets to Fly.io and deploy

### Post-Deployment

After deployment, you can:

1. **Access the Control UI:**
   - If you configure Cloudflare Tunnel, use the hostname you attach to the tunnel
     (example: `https://jarvis.example.com/`).
   - Otherwise, use `flyctl open` or `https://{your-app-name}.fly.dev/`.
   
   The default config is automatically created on first run. You can customize it through the UI or by editing `/data/clawdbot.json` directly.

2. **View logs:**
   ```bash
   flyctl logs
   ```

3. **SSH into the machine (optional):**
   ```bash
   flyctl ssh console
   ```
   
   You can edit the config file at `/data/clawdbot.json` if needed. The default config includes:
   - Discord integration enabled (requires `DISCORD_BOT_TOKEN` environment variable)
   - Placeholder guild ID that needs to be replaced with your actual Discord server ID
   - Claude Opus 4.5 as primary model with Sonnet 4.5 and GPT-4o as fallbacks

### Customizing the Configuration

The application automatically creates a default config at `/data/clawdbot.json` on first startup. To customize:

1. **Via the Control UI** (recommended):
   - Access the UI at your Cloudflare Tunnel hostname (recommended), or
     `https://{your-app-name}.fly.dev/` if you are using the public app URL
   - Navigate to the configuration section
   - Make your changes through the interface

2. **Via SSH** (advanced):
   - SSH into the machine: `flyctl ssh console`
   - Edit the config: `vi /data/clawdbot.json`
   - Replace `YOUR_GUILD_ID` with your Discord server ID
   - Add or modify channels, agents, or other settings
   - Exit and the changes will take effect (may require restart)

### Troubleshooting

- **OOM/Memory Issues:** The fly.toml is configured with 2GB RAM (recommended). If issues persist, increase memory.
- **Gateway lock issues:** If the gateway won't start, delete lock files: `flyctl ssh console -C "rm -f /data/gateway.*.lock"`
- **Config not persisting:** Ensure `CLAWDBOT_STATE_DIR=/data` is set (already configured in fly.toml)
- **Cloudflare Tunnel not reachable:** Ensure `CLOUDFLARE_TUNNEL_TOKEN` is set and the tunnel
  points to `http://127.0.0.1:3000`
- **Control UI token rejected over tunnel:** Set `CLAWDBOT_CONTROL_UI_ALLOW_INSECURE_AUTH=true` and redeploy to allow token-only auth (skips device pairing).
- **Discord bot doesn't respond:**
  - Ensure `DISCORD_BOT_TOKEN` is set in secrets and the app was redeployed.
  - Ensure `DISCORD_GUILD_ID` is set (or replace `YOUR_GUILD_ID` in `/data/clawdbot.json`).
  - The default config uses `groupPolicy: "allowlist"` and a per-guild channel allowlist; add the target channel ID under `channels.discord.guilds.<guild-id>.channels` or switch the policy to open.
  - Restart the app after config changes.

For more details, see the [official Clawdbot Fly.io documentation](https://docs.clawd.bot/platforms/fly.md).
