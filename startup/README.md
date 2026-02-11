# Startup hooks

Container startup is controlled by `bin/startup-runner.sh`, which scans `STARTUP_DIR` (default: `/app/startup`) and runs executable files in lexical order.

## Conventions

- **Ordering:** lexical by filename (`00-...`, `50-...`, `99-...`).
- **File type:** only regular, executable files are run.
- **Ignore rule:** files starting with `_` are skipped.
- **Oneshot:** executable filename does **not** contain `.daemon.`.
  - Runs synchronously.
  - Any non-zero exit fails startup.
- **Daemon:** executable filename **does** contain `.daemon.`.
  - Runs in background.
  - Runner waits on daemons to keep PID 1 alive.

## Environment variables

- `STARTUP_DIR`: startup directory to scan (default `/app/startup`).

## Minimal daemon example

Create `startup/95-example-worker.daemon.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

exec node /app/example-worker/index.js
```

Then make it executable (`chmod +x startup/95-example-worker.daemon.sh`). No Dockerfile or CMD changes are needed.
