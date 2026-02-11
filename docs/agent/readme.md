# Agent runtime playbook

Main gateway process is started directly by the container command:

- `node dist/index.js gateway run --allow-unconfigured --port 3000 --bind auto`

Startup sidecar scripts are loaded from the persistent volume (`/data/startup`) by `docker-entrypoint.sh`.
This means sidecar behavior can be changed in-place by editing files under `/data/startup`, and those changes persist across deploys/restarts.

## First checks in a new session

1. Read `/app/docs/agent/env.md`.
2. Check startup sidecar telemetry:
   - `tail -n 120 /data/logs/startup-scripts.log`
   - `sed -n '1,120p' /data/logs/startup-scripts.current.tsv`
3. Confirm gateway liveness:
   - `npx openclaw gateway health --url ws://127.0.0.1:3000 --token "$OPENCLAW_GATEWAY_TOKEN"`

## Startup sidecar conventions

- Directory: `/data/startup`
- Order: lexical filename order
- Only `.sh` regular files are considered
- Files with `.ignored.` in the filename are skipped
- Executable `.sh` files run directly
- Non-executable `.sh` files run via `bash`
- Scripts are launched as best-effort background sidecars
- A starter guide file is auto-created at `/data/startup/00-startup-directory-guide.ignored.sh`

### Example sidecar script

```bash
#!/usr/bin/env bash
set -euo pipefail

while true; do
  /app/custom/gmail2-triage.sh
  sleep 60
done
```

Save as `/data/startup/40-gmail-triage.sh` and run `chmod +x /data/startup/40-gmail-triage.sh`.

## Sidecar process telemetry

Startup script logs are machine-parseable:

- Startup PID snapshot: `/data/logs/startup-scripts.current.tsv`
- Script lifecycle + output: `/data/logs/startup-scripts.log`

Useful commands:

- Verify a PID is alive: `kill -0 <pid>`
- Stop a sidecar: `kill -TERM <pid>`
- Force stop only if needed: `kill -KILL <pid>`

## Keep context small while debugging

Never read full logs when they can be large. Prefer bounded reads:

- `tail -n 200 /data/logs/startup-scripts.log`
- `rg "event=skip|event=exit|stream=stderr|error|failed" /data/logs/startup-scripts.log`

When sharing findings, copy only the smallest relevant span.
