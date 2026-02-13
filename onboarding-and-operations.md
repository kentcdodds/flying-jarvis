# onboarding-and-operations

This runbook is for deploying OpenClaw on a VPS (Ubuntu 24.04 LTS) with Cloudflare Tunnel + Zero Trust Access.

## Fast path checklist

If you want the shortest reliable setup:

1. Set up the VPS (steps 1–8 in the VPS setup section).
2. Add required GitHub Actions secrets (`VPS_*`, gateway token, tunnel token, and at least one provider key). For internet webhook delivery, also set `OPENCLAW_HOOKS_TOKEN`.
3. Deploy with workflow input `reset_config=true` (first deploy or when changing core auth/channel config).
4. Open your Cloudflare hostname, then pair the browser/device once if prompted.
5. Re-deploy later with `reset_config=false` for normal updates.
6. For Discord, set `DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID` (optionally `DISCORD_CHANNEL_ID`) so startup auto-configures Discord with open guild-channel policy and a default channel entry.

## 1) Prerequisites

- VPS with Ubuntu 24.04 LTS (e.g. Hostinger KVM 4)
- Cloudflare Zero Trust account
- Tunnel created in Cloudflare with a tunnel token
- OpenClaw model provider API key(s)

Useful docs:

- OpenClaw Docker install: <https://docs.openclaw.ai/install/docker>
- OpenClaw Control UI: <https://docs.openclaw.ai/web/control-ui>
- Cloudflare Tunnel: <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/>
- Cloudflare Access policies: <https://developers.cloudflare.com/cloudflare-one/access-controls/policies/>

## 2) VPS setup

### Step 1: Create user `gordon`

```bash
sudo adduser --home /opt/gordon-matrix --shell /bin/bash gordon
sudo usermod -aG docker gordon
```

The user needs shell `/bin/bash` so GitHub Actions can SSH in. Protect with SSH key-only auth (no password).

### Step 2: Configure SSH key-only for `gordon`

```bash
sudo mkdir -p /opt/gordon-matrix/.ssh
# Add the public key corresponding to VPS_SSH_KEY
sudo tee /opt/gordon-matrix/.ssh/authorized_keys <<< "ssh-ed25519 AAAA..."
sudo chown -R gordon:gordon /opt/gordon-matrix/.ssh
sudo chmod 700 /opt/gordon-matrix/.ssh
sudo chmod 600 /opt/gordon-matrix/.ssh/authorized_keys
```

### Step 3: Install Docker Engine

Install Docker CE + docker-compose-plugin from the official Docker repository for Ubuntu 24.04.

### Step 3b: Harden the OS

```bash
# Disable root SSH login
sudo sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Install fail2ban (brute-force protection)
sudo apt install -y fail2ban
sudo systemctl enable fail2ban

# Enable automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### Step 4: Create directory structure

```bash
sudo mkdir -p /opt/gordon-matrix/{data,backups}
sudo chown -R gordon:gordon /opt/gordon-matrix
# The container runs as uid 1000 (node user); data dir must be writable by that uid.
sudo chown -R 1000:1000 /opt/gordon-matrix/data
sudo chmod 700 /opt/gordon-matrix/data
```

### Step 5: Clone repo

```bash
sudo -u gordon git clone https://github.com/sanchezcodes/gordon-matrix.git /opt/gordon-matrix/app
```

### Step 6: Systemd service

Create `/etc/systemd/system/gordon-matrix.service`:

```ini
[Unit]
Description=Gordon Matrix (OpenClaw Gateway)
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=gordon
Group=gordon
WorkingDirectory=/opt/gordon-matrix/app
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

The systemd service does NOT need a .env file — it just restarts the container that Docker already has configured with env vars from the last deploy.

```bash
sudo systemctl daemon-reload
sudo systemctl enable gordon-matrix.service
```

### Step 7: Firewall (UFW)

Verify only SSH (22), HTTP (80), and HTTPS (443) are open. Port 3000 must NOT be exposed.

### Step 8: Automated backup (cron)

```bash
# Generate backup encryption passphrase (one-time)
sudo -u gordon bash -c 'openssl rand -hex 32 > /opt/gordon-matrix/.backup-passphrase'
sudo chmod 600 /opt/gordon-matrix/.backup-passphrase
sudo chown gordon:gordon /opt/gordon-matrix/.backup-passphrase

# Install gpg if not already present
sudo apt install -y gnupg

sudo crontab -u gordon -e
# Add:
0 3 * * * /opt/gordon-matrix/app/backup.sh >> /opt/gordon-matrix/backups/backup.log 2>&1
```

To restore an encrypted backup:

```bash
gpg --batch --passphrase-file /opt/gordon-matrix/.backup-passphrase \
  -d /opt/gordon-matrix/backups/data-YYYYMMDD-HHMMSS.tar.gz.gpg \
  | tar xzf - -C /opt/gordon-matrix
```

## 3) Configure Cloudflare Tunnel ingress

Point your tunnel hostname to the OpenClaw process inside the Docker container:

- Service target: `http://127.0.0.1:3000`

Then protect that hostname with an Access application and an Allow policy for your users/groups.

Notes:

- Access is deny-by-default.
- Avoid permanent `Bypass` for internal admin surfaces.

## 4) Set GitHub Actions secrets

Required secrets:

- `VPS_HOST` — IP or hostname of the VPS
- `VPS_SSH_KEY` — SSH private key (ed25519) for the `gordon` user
- `VPS_SSH_KNOWN_HOSTS` — host key fingerprint (run `ssh-keyscan -p <port> <host>` from a trusted network)
- `OPENCLAW_GATEWAY_TOKEN`
- at least one provider key:
  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - or `GEMINI_API_KEY`
- `CLOUDFLARE_TUNNEL_TOKEN`

Optional:

- `VPS_SSH_PORT` (if not 22)
- `OPENCLAW_HOOKS_TOKEN` (required only when you want webhook endpoints enabled)
- `OPENCLAW_HOOKS_PATH` (defaults to `/hooks`)
- `OPENCLAW_HOOKS_ALLOWED_AGENT_IDS` (comma-separated allowlist for explicit `agentId`, defaults to `*`)
- `DISCORD_BOT_TOKEN`
- `DISCORD_GUILD_ID`
- `DISCORD_CHANNEL_ID` (defaults to `general` when Discord is auto-configured)
- `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` (defaults to `false` each deploy unless explicitly set)

Startup auto-wiring behaviors:

- Provider keys (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`) create matching `auth.profiles.*:default` entries when missing.
- Startup ensures both `main` and `hooks` agents exist; use `hooks` as the default target for webhook workloads.
- When `OPENCLAW_HOOKS_TOKEN` is set, startup enables top-level `hooks`, writes the shared token, and keeps webhook path/agent allowlist aligned with env defaults (`/hooks`, `*`).
- Startup selects `agents.defaults.model.primary` from available providers (priority: OpenAI, then Anthropic, then Google) and keeps fallbacks aligned with available provider keys.
- When both `DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID` are set, startup enables Discord plugin/binding, sets `channels.discord.groupPolicy="open"`, enables wildcard channel access, and seeds a default channel key (`DISCORD_CHANNEL_ID` or `general`).

### Secret value cookbook

Use these examples when you populate GitHub repository secrets:

| Secret | Required? | Example value | How to get it | Default if optional |
|---|---|---|---|---|
| `VPS_HOST` | Yes | `203.0.113.10` | IP of your VPS | n/a |
| `VPS_SSH_KEY` | Yes | `-----BEGIN OPENSSH...` | `ssh-keygen -t ed25519` | n/a |
| `VPS_SSH_PORT` | No | `22` | SSH port of your VPS | `22` |
| `VPS_SSH_KNOWN_HOSTS` | Yes | `203.0.113.10 ssh-ed25519 AAAA...` | Run `ssh-keyscan -p <port> <host>` from a trusted network | n/a |
| `OPENCLAW_GATEWAY_TOKEN` | Yes | `f0f57a7f...` (64 hex chars) | `openssl rand -hex 32` | n/a |
| `CLOUDFLARE_TUNNEL_TOKEN` | Yes | `eyJhIjoi...` | Cloudflare Zero Trust tunnel dashboard, or `cloudflared tunnel token <tunnel-name>` | n/a |
| `OPENCLAW_HOOKS_TOKEN` | No (Yes for webhooks) | `c0ffeec0...` (64 hex chars) | `openssl rand -hex 32` | Unset (webhooks disabled) |
| `OPENCLAW_HOOKS_PATH` | No | `/hooks` | Optional override for webhook base path | `/hooks` |
| `OPENCLAW_HOOKS_ALLOWED_AGENT_IDS` | No | `*` or `main` or `main,hooks` | Optional explicit `agentId` allowlist | `*` |
| `ANTHROPIC_API_KEY` | One provider key required | `sk-ant-...` | Anthropic Console | Unset unless you add it |
| `OPENAI_API_KEY` | One provider key required | `sk-proj-...` | OpenAI API keys page | Unset unless you add it |
| `GEMINI_API_KEY` | One provider key required | `AIza...` | Google AI Studio / Google Cloud credentials | Unset unless you add it |
| `DISCORD_BOT_TOKEN` | No | `MTA...` | Discord Developer Portal → Bot token | Unset |
| `DISCORD_GUILD_ID` | No | `123456789012345678` | Discord Developer Mode → copy server ID | Unset |
| `DISCORD_CHANNEL_ID` | No | `123456789012345678` | Discord Developer Mode → copy channel ID | `general` |
| `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` | No | `false` (recommended) or `true` | Set `true` only when you intentionally want token-only auth without pairing | `false` enforced by workflow when unset |

## 5) Deploy

Deploy by pushing to `main`, or manually run the **Deploy to VPS** workflow.

### Deploy flow

```
Push to main → GitHub Actions → SSH to VPS as gordon →
  git pull → docker compose up --build (env vars via SSH) →
  container running with secrets in Docker internal memory
```

**Secrets never touch the VPS disk.** GitHub Actions exports them as env vars in the SSH session, Docker Compose reads them from the shell environment, and Docker stores them internally in `/var/lib/docker/` (only accessible by root).

### Manual workflow inputs

- `openclaw_version`:
  - `main` (default)
  - specific tag or commit SHA
- `reset_config`:
  - set `true` to force a fresh `/data/openclaw.json` on startup
  - set `false` for normal deploys

Recommended for first setup: run once with `reset_config=true`.

## 6) Validate after deploy

```bash
docker ps --filter name=gordon-matrix          # container running
ss -tlnp | grep 3000                            # should be empty (not exposed to host)
docker logs gordon-matrix 2>&1 | grep tunnel    # tunnel connected
docker exec gordon-matrix curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000
```

Expected signs:

- OpenClaw gateway started on port `3000`
- cloudflared started with your tunnel token
- if `OPENCLAW_HOOKS_TOKEN` is set, `/hooks/wake` and `/hooks/agent` are enabled

Then open your Cloudflare-protected hostname and sign in through Access.

### Validate webhook endpoint through Cloudflare Tunnel

If you set `OPENCLAW_HOOKS_TOKEN`, test from any internet-reachable client with:

```bash
curl -X POST "https://<your-hostname>/hooks/wake" \
  -H "CF-Access-Client-Id: <your-access-service-token-id>" \
  -H "CF-Access-Client-Secret: <your-access-service-token-secret>" \
  -H "Authorization: Bearer <OPENCLAW_HOOKS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"text":"Webhook test from Cloudflare","mode":"now"}'
```

And for an isolated agent run:

```bash
curl -X POST "https://<your-hostname>/hooks/agent" \
  -H "CF-Access-Client-Id: <your-access-service-token-id>" \
  -H "CF-Access-Client-Secret: <your-access-service-token-secret>" \
  -H "Authorization: Bearer <OPENCLAW_HOOKS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"message":"Summarize recent alerts","name":"Webhook","agentId":"hooks","wakeMode":"now"}'
```

Session behavior notes:

- `/hooks/agent` already defaults to a fresh random `sessionKey` per call when `sessionKey` is omitted.
- For unrelated webhook events (like independent emails), omit `sessionKey` so each run stays isolated.
- Only set a stable `sessionKey` when you intentionally want multi-turn continuity (for example, one key per email thread).

### First remote Control UI connection (pairing expected)

If Control UI shows `disconnected (1008): pairing required`, this is expected for first-time remote devices.

Approve the pending device request from inside the container:

```bash
docker exec -it gordon-matrix sh
npx openclaw devices list
npx openclaw devices approve <request-id>
```

Then refresh the UI and connect again.

### Channel and provider sanity check

Run from the VPS after deploy:

```bash
docker exec gordon-matrix npx openclaw status --deep
docker exec gordon-matrix npx openclaw channels list
```

If `channels list` shows no channels or no auth providers, re-check secrets and run a one-time deploy with `reset_config=true`.

## 7) Operations

### View logs

```bash
docker logs gordon-matrix                       # container logs
docker logs gordon-matrix --tail 100 -f         # follow last 100 lines
journalctl -t gordon-matrix                     # via journald (logging driver)
```

### Shell into container

```bash
docker exec -it gordon-matrix sh
```

### Inspect config

```bash
docker exec gordon-matrix sh -c 'head -240 /data/openclaw.json'
```

### Restart container

```bash
cd /opt/gordon-matrix/app && docker compose restart
# Or via systemd:
sudo systemctl restart gordon-matrix
```

### Run one-shot commands

```bash
docker exec gordon-matrix npx openclaw status --deep
docker exec gordon-matrix npx openclaw channels list
docker exec gordon-matrix npx openclaw gateway health --url ws://127.0.0.1:3000 --token "$OPENCLAW_GATEWAY_TOKEN"
```

## 8) Common troubleshooting

### Tunnel not reachable

- Confirm `CLOUDFLARE_TUNNEL_TOKEN` is present in GitHub Secrets and you redeployed.
- Confirm tunnel ingress target is `http://127.0.0.1:3000`.
- Check Cloudflare Zero Trust dashboard for connector health.

### Webhook calls fail

- Confirm `OPENCLAW_HOOKS_TOKEN` is set in GitHub Secrets and redeploy if newly added.
- Confirm your request includes both Cloudflare Access service-token headers and a valid OpenClaw hook token (`Authorization: Bearer <OPENCLAW_HOOKS_TOKEN>`).
- Confirm the webhook path matches your config (`/hooks` by default, or `OPENCLAW_HOOKS_PATH` override).
- If calling `/hooks/agent` with `agentId`, confirm it is included in `OPENCLAW_HOOKS_ALLOWED_AGENT_IDS` (or set `*`).

### Discord not responding

- Confirm `DISCORD_BOT_TOKEN` is set in GitHub Secrets.
- Confirm `DISCORD_GUILD_ID` matches the target Discord server.
- Optionally set `DISCORD_CHANNEL_ID` to seed your preferred default channel key (otherwise `general`).
- Confirm `/data/openclaw.json` includes the auto-configured Discord plugin/channel entries after startup.
- Verify gateway reachability:

```bash
docker exec gordon-matrix npx openclaw gateway probe
docker exec gordon-matrix npx openclaw status --deep
docker exec gordon-matrix npx openclaw gateway health --url ws://127.0.0.1:3000 --token "$OPENCLAW_GATEWAY_TOKEN"
```

- If health/probe reports `connect ECONNREFUSED`, start in foreground mode:

```bash
docker exec gordon-matrix npx openclaw gateway run --allow-unconfigured --port 3000 --bind auto
```

- Re-check channels:

```bash
docker exec gordon-matrix npx openclaw channels list
docker exec gordon-matrix npx openclaw status
```

- If you intentionally use `--force`, ensure `lsof` is installed in the image.

### Control UI auth issues

- Verify `OPENCLAW_GATEWAY_TOKEN` is set.
- If you see `disconnected (1008): pairing required`, run:

```bash
docker exec -it gordon-matrix sh
npx openclaw devices list
npx openclaw devices approve <request-id>
```

- Only use `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true` when you intentionally accept token-only auth behavior.

### Gateway lock file issue

```bash
docker exec gordon-matrix rm -f /data/gateway.*.lock
```

### Config reset behavior

- Use workflow input `reset_config=true` for one deploy when needed.
- Subsequent deploys should keep it `false`.

## 9) Agent bootstrap prompts

When first opening an in-container agent session, useful prompts are:

1. `Read /app/docs/agent/readme.md and /app/docs/agent/env.md, then summarize key paths and runtime conventions.`
2. `Use bounded log reads to diagnose gateway startup and identify the first fatal event.`
3. `Check gateway health and channel status, then summarize any blocking errors.`
