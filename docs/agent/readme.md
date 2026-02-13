# Agent runtime playbook

Main gateway process is started directly by the container command:

- `node dist/index.js gateway run --allow-unconfigured --port 3000 --bind auto`

## First checks in a new session

1. Read `/app/docs/agent/env.md`.
2. Confirm gateway liveness:
   - `npx openclaw gateway health --url ws://127.0.0.1:3000 --token "$OPENCLAW_GATEWAY_TOKEN"`
3. Check current channel state:
   - `npx openclaw channels list`
4. Use bounded app logs:
   - `docker logs gordon-matrix --tail 200`

## Keep context small while debugging

Prefer bounded reads and copy only the smallest relevant span in findings.
