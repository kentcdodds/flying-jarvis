# onboarding-and-operations

This runbook is for deploying OpenClaw on Fly with Cloudflare Tunnel + Zero Trust Access.

## Fast path checklist

If you want the shortest reliable setup:

1. Set required GitHub Actions secrets (`FLY_*`, gateway token, tunnel token, and at least one provider key).
2. Deploy with workflow input `reset_config=true` (first deploy or when changing core auth/channel config).
3. Open your Cloudflare hostname, then pair the browser/device once if prompted.
4. Re-deploy later with `reset_config=false` for normal updates.
5. Configure optional channels (such as Discord) in Control UI after first login.

## 1) Prerequisites

- Fly account + `flyctl`
- Cloudflare Zero Trust account
- Tunnel created in Cloudflare with a tunnel token
- OpenClaw model provider API key(s)

Useful docs:

- OpenClaw Fly install: <https://docs.openclaw.ai/install/fly>
- OpenClaw Control UI: <https://docs.openclaw.ai/web/control-ui>
- Cloudflare Tunnel: <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/>
- Cloudflare Access policies: <https://developers.cloudflare.com/cloudflare-one/access-controls/policies/>

## 2) Choose Fly app + region

Pick values for:

- app name (`FLY_APP_NAME`)
- region (`FLY_REGION`, optional; defaults to `iad`)

The workflow will create the app and volume automatically if missing.
Defaults:

- volume name: `openclaw_data` (fixed in this template)
- volume size: `1` GB (override with `FLY_VOLUME_SIZE_GB`)
- optional org selector: `FLY_ORG`

## 3) Configure Cloudflare Tunnel ingress

Point your tunnel hostname to your local OpenClaw process inside the Fly machine:

- Service target: `http://127.0.0.1:3000`

Then protect that hostname with an Access application and an Allow policy for your users/groups.

Notes:

- Access is deny-by-default.
- Avoid permanent `Bypass` for internal admin surfaces.

## 4) Set GitHub Actions secrets

Required secrets:

- `FLY_API_TOKEN`
- `FLY_APP_NAME`
- `OPENCLAW_GATEWAY_TOKEN`
- at least one provider key:
  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - or `GOOGLE_API_KEY`
- `CLOUDFLARE_TUNNEL_TOKEN`

Optional:

- `DISCORD_BOT_TOKEN`
- `DISCORD_GUILD_ID`
- `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` (defaults to `false` each deploy unless explicitly set)
- `FLY_REGION` (defaults to `iad`)
- `FLY_ORG`
- `FLY_VOLUME_SIZE_GB`

`DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID` are only passed through as runtime secrets. This template no longer auto-wires Discord bindings/channels in the default config.

### Secret value cookbook

Use these examples when you populate GitHub repository secrets:

| Secret | Required? | Example value | How to get it | Default if optional |
|---|---|---|---|---|
| `FLY_API_TOKEN` | Yes | `fo1_...` | `flyctl auth login` then `flyctl auth token` | n/a |
| `FLY_APP_NAME` | Yes | `my-openclaw` | Choose a unique app name you want on Fly | n/a |
| `FLY_REGION` | No | `iad` | `fly platform regions` | `iad` |
| `OPENCLAW_GATEWAY_TOKEN` | Yes | `f0f57a7f...` (64 hex chars) | `openssl rand -hex 32` | n/a |
| `CLOUDFLARE_TUNNEL_TOKEN` | Yes | `eyJhIjoi...` | Cloudflare Zero Trust tunnel dashboard, or `cloudflared tunnel token <tunnel-name>` | n/a |
| `ANTHROPIC_API_KEY` | One provider key required | `sk-ant-...` | Anthropic Console | Unset unless you add it |
| `OPENAI_API_KEY` | One provider key required | `sk-proj-...` | OpenAI API keys page | Unset unless you add it |
| `GOOGLE_API_KEY` | One provider key required | `AIza...` | Google AI Studio / Google Cloud credentials | Unset unless you add it |
| `DISCORD_BOT_TOKEN` | No | `MTA...` | Discord Developer Portal → Bot token | Unset |
| `DISCORD_GUILD_ID` | No | `123456789012345678` | Discord Developer Mode → copy server ID | Unset |
| `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` | No | `false` (recommended) or `true` | Set `true` only when you intentionally want token-only auth without pairing | `false` enforced by workflow when unset |
| `FLY_ORG` | No | `personal` | `fly orgs list` | Unset (Fly default org context) |
| `FLY_VOLUME_SIZE_GB` | No | `1` | Optional integer GB size (`>= 1`) | `1` |

## 5) Deploy

Deploy by pushing to `main`, or manually run the **Deploy to Fly.io** workflow.

Manual workflow inputs:

- `openclaw_version`:
  - `main` (default)
  - specific tag or commit
- `reset_config`:
  - set `true` to force a fresh `/data/openclaw.json` on startup
  - the workflow clears `RESET_CONFIG` after deploy so the reset remains one-shot

Recommended for first setup: run once with `reset_config=true`.

## 6) Validate after deploy

```bash
flyctl status -a <your-fly-app-name>
flyctl logs -a <your-fly-app-name> --no-tail
```

Expected signs:

- OpenClaw gateway started on port `3000`
- cloudflared started with your tunnel token

Then open your Cloudflare-protected hostname and sign in through Access.

### First remote Control UI connection (pairing expected)

If Control UI shows `disconnected (1008): pairing required`, this is expected for first-time remote devices.

Approve the pending device request from inside the Fly machine:

```bash
flyctl ssh console -a <your-fly-app-name>
npx openclaw devices list
npx openclaw devices approve <request-id>
```

Then refresh the UI and connect again.

### Channel and provider sanity check

Run this from inside the Fly machine after deploy:

```bash
npx openclaw status --deep
npx openclaw channels list
```

If `channels list` shows no channels or no auth providers, re-check secrets and run a one-time deploy with `reset_config=true`.

## 7) Operations

### View logs

```bash
flyctl logs -a <your-fly-app-name>
```

### SSH into machine

```bash
flyctl ssh console -a <your-fly-app-name>
```

### Inspect config

```bash
sed -n '1,240p' /data/openclaw.json
```

### Restart machine

```bash
flyctl machines list -a <your-fly-app-name>
flyctl machine restart <machine-id> -a <your-fly-app-name>
```

### Run one-shot commands safely over Fly SSH

When using `flyctl ssh console -C`, wrap commands in a shell so pipes/loops/expansions work reliably:

```bash
flyctl ssh console -a <your-fly-app-name> -C 'sh -lc "npx openclaw status --deep"'
```

## 8) Common troubleshooting

### Tunnel not reachable

- Confirm `CLOUDFLARE_TUNNEL_TOKEN` is present in Fly secrets.
- Confirm tunnel ingress target is `http://127.0.0.1:3000`.
- Check Cloudflare Zero Trust dashboard for connector health.

### Discord not responding

- Confirm `DISCORD_BOT_TOKEN` is set in Fly secrets.
- Confirm `DISCORD_GUILD_ID` matches the target Discord server.
- Confirm Discord plugin/channel bindings were configured in Control UI or `/data/openclaw.json`.
- Verify gateway reachability:

```bash
npx openclaw gateway probe
npx openclaw status --deep
npx openclaw gateway health --url ws://127.0.0.1:3000 --token "$OPENCLAW_GATEWAY_TOKEN"
```

- If health/probe reports `connect ECONNREFUSED`, start in foreground mode:

```bash
npx openclaw gateway run --allow-unconfigured --port 3000 --bind auto
```

- Re-check channels:

```bash
npx openclaw channels list
npx openclaw status
```

- If you intentionally use `--force`, ensure `lsof` is installed in the image.

### Control UI auth issues

- Verify `OPENCLAW_GATEWAY_TOKEN` is set.
- If you see `disconnected (1008): pairing required`, run:

```bash
flyctl ssh console -a <your-fly-app-name>
npx openclaw devices list
npx openclaw devices approve <request-id>
```

- Only use `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true` when you intentionally accept token-only auth behavior.

### Gateway lock file issue

```bash
flyctl ssh console -a <your-fly-app-name> -C "rm -f /data/gateway.*.lock"
```

### Config reset behavior

- Use workflow input `reset_config=true` for one deploy when needed.
- Subsequent deploys should keep it `false`.
