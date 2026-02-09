# onboarding-and-operations

This runbook is for deploying OpenClaw on Fly with Cloudflare Tunnel + Zero Trust Access.

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
- region (`FLY_REGION`)

The workflow will create the app and volume automatically if missing.
Defaults:

- volume name: `openclaw_data` (override with `FLY_VOLUME_NAME`)
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
- `FLY_REGION`
- `OPENCLAW_GATEWAY_TOKEN`
- at least one provider key:
  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - or `GOOGLE_API_KEY`
- `CLOUDFLARE_TUNNEL_TOKEN`

Optional:

- `DISCORD_BOT_TOKEN`
- `DISCORD_GUILD_ID`
- `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH`
- `FLY_ORG`
- `FLY_VOLUME_NAME`
- `FLY_VOLUME_SIZE_GB`

## 5) Deploy

Deploy by pushing to `main`, or manually run the **Deploy to Fly.io** workflow.

Manual workflow inputs:

- `openclaw_version`:
  - `latest` (default)
  - `main`
  - specific tag or commit
- `reset_config`:
  - set `true` to force a fresh `/data/openclaw.json` on startup

## 6) Validate after deploy

```bash
flyctl status -a <your-fly-app-name>
flyctl logs -a <your-fly-app-name>
```

Expected signs:

- OpenClaw gateway started on port `3000`
- cloudflared started with your tunnel token

Then open your Cloudflare-protected hostname and sign in through Access.

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
cat /data/openclaw.json
```

### Restart machine

```bash
flyctl machines list -a <your-fly-app-name>
flyctl machine restart <machine-id> -a <your-fly-app-name>
```

## 8) Common troubleshooting

### Tunnel not reachable

- Confirm `CLOUDFLARE_TUNNEL_TOKEN` is present in Fly secrets.
- Confirm tunnel ingress target is `http://127.0.0.1:3000`.
- Check Cloudflare Zero Trust dashboard for connector health.

### Control UI auth issues

- Verify `OPENCLAW_GATEWAY_TOKEN` is set.
- Pair new devices if required (see Control UI docs).
- Only use `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true` when you intentionally accept token-only auth behavior.

### Gateway lock file issue

```bash
flyctl ssh console -a <your-fly-app-name> -C "rm -f /data/gateway.*.lock"
```

### Config reset behavior

- Use workflow input `reset_config=true` for one deploy when needed.
- Subsequent deploys should keep it `false`.
