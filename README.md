# openclaw-fly-template

Deploy [OpenClaw](https://openclaw.ai/) to [Fly.io](https://fly.io/) with:

- GitHub Actions deploy automation
- persistent state volume
- Cloudflare Tunnel
- Cloudflare Zero Trust Access in front of Control UI

## Security model (recommended default)

This template is tuned for **private Fly deployment + Cloudflare Zero Trust**:

- The Fly app runs without a public Fly `http_service`.
- `cloudflared` makes outbound-only tunnel connections.
- Access to Control UI is through your Cloudflare hostname and Access policies.

Why this default:

- Cloudflare Tunnel uses outbound-only connectors from the origin.
- You can block inbound exposure to the Fly app and enforce identity-based access at Cloudflare Access.

References:

- OpenClaw Fly deployment docs: <https://docs.openclaw.ai/install/fly>
- OpenClaw Control UI docs: <https://docs.openclaw.ai/web/control-ui>
- Cloudflare Tunnel docs: <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/>
- Cloudflare Access policies: <https://developers.cloudflare.com/cloudflare-one/access-controls/policies/>

## Quick start

1. Create a Fly app and volume.
2. Add GitHub Actions secrets.
3. Push to `main` (or run workflow manually).
4. Access OpenClaw through your Cloudflare Access-protected hostname.

See [onboarding-and-operations.md](./onboarding-and-operations.md) for the complete runbook.

## Required GitHub Actions secrets

Set these in **Settings → Secrets and variables → Actions**:

- `FLY_API_TOKEN` — from `flyctl auth token`
- `FLY_APP_NAME` — Fly app name (for example `my-openclaw`)
- `FLY_REGION` — Fly primary region (for example `iad`, `dfw`, `lhr`)
- `OPENCLAW_GATEWAY_TOKEN` — `openssl rand -hex 32`
- at least one provider key:
  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - or `GOOGLE_API_KEY`
- `CLOUDFLARE_TUNNEL_TOKEN` — token for your Cloudflare Tunnel connector

Optional:

- `DISCORD_BOT_TOKEN`
- `DISCORD_GUILD_ID`
- `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` (set `true` only if you intentionally want token-only UI auth without pairing)

## Deploy workflow behavior

- Workflow: **Deploy to Fly.io**
- Trigger:
  - push to `main`
  - manual `workflow_dispatch`
- Build input:
  - `openclaw_version` (`latest` by default; can be `main`, tag, or commit SHA)
- Optional one-shot reset:
  - `reset_config = true` removes `/data/openclaw.json` before startup

The deploy workflow renders app name and primary region from secrets, so forks only need to set secrets and deploy.

## Build image locally

```bash
# latest release (default)
docker build --build-arg OPENCLAW_VERSION=latest -t openclaw-fly-template .

# main branch
docker build --build-arg OPENCLAW_VERSION=main -t openclaw-fly-template .

# specific tag
docker build --build-arg OPENCLAW_VERSION=v2026.1.29 -t openclaw-fly-template .

# specific commit
docker build --build-arg OPENCLAW_VERSION=abc1234 -t openclaw-fly-template .
```

## Additional references

- OpenClaw getting started: <https://docs.openclaw.ai/start/getting-started>
- OpenClaw environment variables: <https://docs.openclaw.ai/help/environment>
- OpenClaw gateway runbook: <https://docs.openclaw.ai/gateway>
