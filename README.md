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
6. For Discord setup, set both `DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID`; startup auto-configures a working default Discord binding.

For exact commands and values, follow the runbook sections:

- prerequisites: [`1) Prerequisites`](./onboarding-and-operations.md#1-prerequisites)
- Fly app + region: [`2) Choose Fly app + region`](./onboarding-and-operations.md#2-choose-fly-app--region)
- tunnel + access: [`3) Configure Cloudflare Tunnel ingress`](./onboarding-and-operations.md#3-configure-cloudflare-tunnel-ingress)
- secrets: [`4) Set GitHub Actions secrets`](./onboarding-and-operations.md#4-set-github-actions-secrets)
- deployment: [`5) Deploy`](./onboarding-and-operations.md#5-deploy)
- validation: [`6) Validate after deploy`](./onboarding-and-operations.md#6-validate-after-deploy)
- operations + troubleshooting: [`7) Operations`](./onboarding-and-operations.md#7-operations) and [`8) Common troubleshooting`](./onboarding-and-operations.md#8-common-troubleshooting)

## Reference docs

- OpenClaw Fly deployment docs: <https://docs.openclaw.ai/install/fly>
- OpenClaw Control UI docs: <https://docs.openclaw.ai/web/control-ui>
- OpenClaw getting started: <https://docs.openclaw.ai/start/getting-started>
- OpenClaw environment variables: <https://docs.openclaw.ai/help/environment>
- OpenClaw gateway runbook: <https://docs.openclaw.ai/gateway>
- Cloudflare Tunnel docs: <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/>
- Cloudflare Access policies: <https://developers.cloudflare.com/cloudflare-one/access-controls/policies/>
