# Agent environment reference

## Runtime model

- Main process: `node dist/index.js gateway run --allow-unconfigured --port 3000 --bind auto`
- Entrypoint: `/app/docker-entrypoint.sh`
- Startup sidecar script directory: `/data/startup`
- Startup sidecar log directory: `/data/logs`

## Startup sidecar output files

- Script lifecycle + output:
  - `/data/logs/startup-scripts.log`
- Startup script PID snapshot:
  - `/data/logs/startup-scripts.current.tsv`

`startup-scripts.log` lines are structured for parsing:

- events: `event=start|skip|exit`, `name=...`, `pid=...`, `status=...`, `entry=...`
- script output streams: `stream=stdout|stderr`, `name=...`, `entry=...`, `msg=...`

## Key environment variables

- `OPENCLAW_STATE_DIR` (default: `/data`)
- `OPENCLAW_WORKSPACE_DIR` (default: `${OPENCLAW_STATE_DIR}/workspace`)
- `OPENCLAW_CONFIG_FILE` (set by entrypoint to `${OPENCLAW_STATE_DIR}/openclaw.json`)
- `STARTUP_DIR` (default: `/data/startup`)
- `STARTUP_LOG_DIR` (default: `/data/logs`)
- `STARTUP_SCRIPT_LOG` (default: `${STARTUP_LOG_DIR}/startup-scripts.log`)
- `STARTUP_SCRIPT_PIDS_FILE` (default: `${STARTUP_LOG_DIR}/startup-scripts.current.tsv`)

## Startup sidecar behavior

- only `.sh` regular files from `/data/startup` are considered
- lexical filename order controls launch order
- files containing `.ignored.` in the filename are skipped
- executable scripts run directly; non-executable scripts run via `bash`
- scripts are launched as background sidecars and do not block gateway startup
- `/data/startup/00-startup-directory-guide.ignored.sh` is auto-created on first boot
