# Agent runtime playbook

This image includes a startup runner at `/app/bin/startup-runner.sh`.

The runner executes scripts from the persistent volume (`/data/startup`), not from git-tracked files. This means runtime behavior can be changed in-place by editing files under `/data/startup`, and those changes persist across deploys/restarts.

On first boot, if `/data/startup` is missing, the runner creates it and bootstraps `/data/startup/80-openclaw.daemon.sh` by default.

## First checks in a new session

1. Read `/app/docs/agent/env.md`.
2. Check runner health:
   - `tail -n 120 /data/logs/startup-runner.log`
   - `tail -n 120 /data/logs/startup-processes.log`
3. Check active daemons:
   - `sed -n '1,120p' /data/logs/startup-daemons.current.tsv`

## Startup script conventions

- Directory: `/data/startup`
- Order: lexical filename order
- Ignore: files starting with `_`
- Only regular + executable files run
- Oneshot: executable filename does **not** contain `.daemon.`
  - Runs synchronously
  - Non-zero exit fails startup
- Daemon: executable filename **does** contain `.daemon.`
  - Runs in background
  - Runner waits so PID 1 stays alive

### Example daemon script

```bash
#!/usr/bin/env bash
set -euo pipefail

exec openclaw gateway run --allow-unconfigured --port 3000 --bind auto
```

Save as `/data/startup/80-openclaw.daemon.sh` and run `chmod +x /data/startup/80-openclaw.daemon.sh`.

## Process management

The runner writes daemon process metadata and events:

- Active daemon snapshot: `/data/logs/startup-daemons.current.tsv`
- Process lifecycle events: `/data/logs/startup-processes.log`
- Combined runner + startup-script output: `/data/logs/startup-runner.log`

Useful commands:

- Verify a PID is alive: `kill -0 <pid>`
- Stop a daemon: `kill -TERM <pid>`
- Force stop only if needed: `kill -KILL <pid>`

## Keep context small while debugging

Never read full logs when they can be large. Prefer bounded reads:

- `tail -n 200 /data/logs/startup-runner.log`
- `tail -n 200 /data/logs/startup-processes.log`
- `rg "\\[startup\\]|error|failed|non-zero" /data/logs/startup-runner.log`

When sharing findings, copy only the smallest relevant span.
