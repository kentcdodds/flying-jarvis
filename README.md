# gordon-matrix

Deploy [OpenClaw](https://openclaw.ai/) to a VPS (Ubuntu 24.04 LTS) with:

- GitHub Actions deploy automation via SSH
- Docker Compose container orchestration
- persistent data volume
- Cloudflare Tunnel
- Cloudflare Zero Trust Access in front of Control UI
- optional internet webhooks (`/hooks/*`) guarded by Cloudflare Access + OpenClaw hook token
- systemd service for auto-restart on reboot
- automated daily backups

This README is intentionally high-level. Use the runbook as the source of truth for setup and operations:

- [onboarding-and-operations.md](./onboarding-and-operations.md)

## Recommended security model

This template is tuned for **private VPS deployment + Cloudflare Zero Trust**:

- The Docker container runs without exposed ports.
- `cloudflared` makes outbound-only tunnel connections.
- Access to Control UI is through your Cloudflare hostname and Access policies.
- Secrets are passed via SSH environment variables and stored only in Docker internal memory — they never touch the VPS disk as files.

## Quick start

1. Complete prerequisites and VPS setup (create `gordon` user, install Docker, configure systemd service).
2. Configure Cloudflare Tunnel ingress pointing to `http://127.0.0.1:3000`.
3. Add required GitHub Actions secrets (`VPS_HOST`, `VPS_SSH_KEY`, gateway token, tunnel token, and at least one provider key). For internet webhook delivery, also set `OPENCLAW_HOOKS_TOKEN`.
4. Deploy by pushing to `main` or running the workflow manually (recommended first deploy: `reset_config=true`).
5. Validate deploy health and access OpenClaw via your Cloudflare-protected hostname.
6. If the Control UI shows `disconnected (1008): pairing required`, approve the pending device request from inside the container: `docker exec -it gordon-matrix sh`.
7. For Discord setup, set `DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID` (optionally `DISCORD_CHANNEL_ID`); startup auto-configures Discord with open guild-channel policy and seeds a default channel key (`DISCORD_CHANNEL_ID` or `general`).
8. For webhook setup, set `OPENCLAW_HOOKS_TOKEN` (optionally `OPENCLAW_HOOKS_PATH` and `OPENCLAW_HOOKS_ALLOWED_AGENT_IDS`), and target `agentId: "hooks"` in `/hooks/agent` payloads.

For exact commands and values, follow the runbook sections:

- prerequisites: [`1) Prerequisites`](./onboarding-and-operations.md#1-prerequisites)
- VPS setup: [`2) VPS setup`](./onboarding-and-operations.md#2-vps-setup)
- tunnel + access: [`3) Configure Cloudflare Tunnel ingress`](./onboarding-and-operations.md#3-configure-cloudflare-tunnel-ingress)
- secrets: [`4) Set GitHub Actions secrets`](./onboarding-and-operations.md#4-set-github-actions-secrets)
- deployment: [`5) Deploy`](./onboarding-and-operations.md#5-deploy)
- validation: [`6) Validate after deploy`](./onboarding-and-operations.md#6-validate-after-deploy)
- operations + troubleshooting: [`7) Operations`](./onboarding-and-operations.md#7-operations) and [`8) Common troubleshooting`](./onboarding-and-operations.md#8-common-troubleshooting)

Agent docs shipped in the image:

- `/app/docs/agent/readme.md`
- `/app/docs/agent/env.md`

## Recommended bootstrap prompts for Jarvis

Use prompts like:

1. `Read /app/docs/agent/readme.md and /app/docs/agent/env.md, then summarize runtime commands and key paths.`
2. `Diagnose startup issues using bounded app log reads and identify the first fatal error.`
3. `Verify gateway liveness on ws://127.0.0.1:3000 and summarize channel status.`

## Reference docs

- OpenClaw Docker deployment docs: <https://docs.openclaw.ai/install/docker>
- OpenClaw Control UI docs: <https://docs.openclaw.ai/web/control-ui>
- OpenClaw getting started: <https://docs.openclaw.ai/start/getting-started>
- OpenClaw environment variables: <https://docs.openclaw.ai/help/environment>
- OpenClaw gateway runbook: <https://docs.openclaw.ai/gateway>
- Cloudflare Tunnel docs: <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/>
- Cloudflare Access policies: <https://developers.cloudflare.com/cloudflare-one/access-controls/policies/>
