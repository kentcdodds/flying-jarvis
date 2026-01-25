# flying-jarvis
Clawdbot running on fly.io

## Setup Instructions

This repository contains the configuration to deploy Clawdbot to Fly.io with automatic deployments via GitHub Actions.

### Prerequisites

- [flyctl CLI](https://fly.io/docs/hands-on/install-flyctl/) installed
- Fly.io account (free tier works)
- Anthropic API key (for Claude access)
- Optional: Discord bot token, Telegram token, etc. for channel integrations

### Initial Deployment

1. **Create the Fly.io app:**
   ```bash
   flyctl apps create flying-jarvis
   ```

2. **Create a persistent volume:**
   ```bash
   flyctl volumes create clawdbot_data --region iad --size 1
   ```

3. **Set up secrets:**
   ```bash
   # Required: Gateway token (for security)
   flyctl secrets set CLAWDBOT_GATEWAY_TOKEN=$(openssl rand -hex 32)
   
   # Required: Model provider API key
   flyctl secrets set ANTHROPIC_API_KEY=sk-ant-...
   
   # Optional: Other providers
   flyctl secrets set OPENAI_API_KEY=sk-...
   flyctl secrets set GOOGLE_API_KEY=...
   
   # Optional: Channel tokens
   flyctl secrets set DISCORD_BOT_TOKEN=MTQ...
   ```

4. **Set up GitHub Actions:**
   - Go to your repository Settings > Secrets and variables > Actions
   - Add a new repository secret: `FLY_API_TOKEN`
   - Get your token with: `flyctl auth token`

5. **Deploy:**
   - Push to the `main` branch to trigger automatic deployment via GitHub Actions
   - Or manually deploy with: `flyctl deploy`

### Post-Deployment

After deployment, you can:

1. **Access the Control UI:**
   ```bash
   flyctl open
   ```
   Or visit: `https://flying-jarvis.fly.dev/`

2. **View logs:**
   ```bash
   flyctl logs
   ```

3. **SSH into the machine to configure:**
   ```bash
   flyctl ssh console
   ```

4. **Create a config file** (if needed):
   See the [Fly.io deployment guide](https://docs.clawd.bot/platforms/fly.md) for detailed configuration options.

### Troubleshooting

- **OOM/Memory Issues:** The fly.toml is configured with 2GB RAM (recommended). If issues persist, increase memory.
- **Gateway lock issues:** If the gateway won't start, delete lock files: `flyctl ssh console -C "rm -f /data/gateway.*.lock"`
- **Config not persisting:** Ensure `CLAWDBOT_STATE_DIR=/data` is set (already configured in fly.toml)

For more details, see the [official Clawdbot Fly.io documentation](https://docs.clawd.bot/platforms/fly.md).
