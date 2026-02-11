# openclaw-fly-template

Deploy [OpenClaw](https://openclaw.ai/) to [Fly.io](https://fly.io/) with:

- GitHub Actions deploy automation
- persistent state volume
- Cloudflare Tunnel
- Cloudflare Zero Trust Access in front of Control UI

This README is intentionally high-level. Use the runbook as the source of truth for setup and operations:

- [onboarding-and-operations.md](./onboarding-and-operations.md)

## Recommended security model

This template is tuned for **private Fly deployment + Cloudflare Zero Trust**:

- The Fly app runs without a public Fly `http_service`.
- `cloudflared` makes outbound-only tunnel connections.
- Access to Control UI is through your Cloudflare hostname and Access policies.

## Quick start

1. Complete prerequisites and Cloudflare Tunnel setup.
2. Add required GitHub Actions secrets.
3. Deploy by pushing to `main` or running the workflow manually (recommended first deploy: `reset_config=true`).
4. Validate deploy health and access OpenClaw via your Cloudflare-protected hostname.
5. If the Control UI shows `disconnected (1008): pairing required`, approve the pending device request from inside the Fly machine.
6. For Discord setup, set `DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID` (optionally `DISCORD_CHANNEL_ID`); startup auto-configures Discord with open guild-channel policy and seeds a default channel key (`DISCORD_CHANNEL_ID` or `general`).

For exact commands and values, follow the runbook sections:

- prerequisites: [`1) Prerequisites`](./onboarding-and-operations.md#1-prerequisites)
- Fly app + region: [`2) Choose Fly app + region`](./onboarding-and-operations.md#2-choose-fly-app--region)
- tunnel + access: [`3) Configure Cloudflare Tunnel ingress`](./onboarding-and-operations.md#3-configure-cloudflare-tunnel-ingress)
- secrets: [`4) Set GitHub Actions secrets`](./onboarding-and-operations.md#4-set-github-actions-secrets)
- deployment: [`5) Deploy`](./onboarding-and-operations.md#5-deploy)
- validation: [`6) Validate after deploy`](./onboarding-and-operations.md#6-validate-after-deploy)
- operations + troubleshooting: [`7) Operations`](./onboarding-and-operations.md#7-operations) and [`8) Common troubleshooting`](./onboarding-and-operations.md#8-common-troubleshooting)

## Startup sidecar model

Gateway startup is process-managed from git, while sidecars are volume-managed:

- Main app process: `node dist/index.js gateway run --allow-unconfigured --port 3000 --bind auto`
- Persistent startup scripts: `/data/startup`
- Persistent startup script logs: `/data/logs/startup-scripts.log`
- Startup script PID snapshot: `/data/logs/startup-scripts.current.tsv`

At boot, `docker-entrypoint.sh` runs all `.sh` files in `/data/startup` as best-effort background sidecars.
Use `.ignored.` in a startup filename to keep notes/examples in the directory without executing them.
The image also auto-creates `/data/startup/00-startup-directory-guide.ignored.sh` with quick usage docs.

Agent docs shipped in the image:

- `/app/docs/agent/readme.md`
- `/app/docs/agent/env.md`

## Recommended bootstrap prompts for Jarvis

Use prompts like:

1. `Read /app/docs/agent/readme.md and /app/docs/agent/env.md, then summarize the startup model and log locations.`
2. `Diagnose startup issues using only bounded log reads (tail/rg), and show the current startup script snapshot from /data/logs/startup-scripts.current.tsv.`
3. `Add or update a startup sidecar script in /data/startup, then verify it appears in /data/logs/startup-scripts.log and /data/logs/startup-scripts.current.tsv.`

## Reference docs

- OpenClaw Fly deployment docs: <https://docs.openclaw.ai/install/fly>
- OpenClaw Control UI docs: <https://docs.openclaw.ai/web/control-ui>
- OpenClaw getting started: <https://docs.openclaw.ai/start/getting-started>
- OpenClaw environment variables: <https://docs.openclaw.ai/help/environment>
- OpenClaw gateway runbook: <https://docs.openclaw.ai/gateway>
- Cloudflare Tunnel docs: <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/>
- Cloudflare Access policies: <https://developers.cloudflare.com/cloudflare-one/access-controls/policies/>
