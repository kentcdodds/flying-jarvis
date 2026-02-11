# Agent environment reference

## Startup runner paths

- Runner executable: `/app/bin/startup-runner.sh`
- Startup script directory: `/data/startup`
- Runner log directory: `/data/logs`

## Runner output files

- Runner + startup script output:
  - `/data/logs/startup-runner.log`
  - rotated backups: `/data/logs/startup-runner.log.1` ... `.N`
- Daemon process events:
  - `/data/logs/startup-processes.log`
  - rotated backups: `/data/logs/startup-processes.log.1` ... `.N`
- Current daemon snapshot:
  - `/data/logs/startup-daemons.current.tsv`

## Key environment variables

- `STARTUP_DIR` (default: `/data/startup`)
- `STARTUP_LOG_DIR` (default: `/data/logs`)
- `STARTUP_RUNNER_LOG` (default: `${STARTUP_LOG_DIR}/startup-runner.log`)
- `STARTUP_PROCESS_LOG` (default: `${STARTUP_LOG_DIR}/startup-processes.log`)
- `STARTUP_ACTIVE_DAEMONS_FILE` (default: `${STARTUP_LOG_DIR}/startup-daemons.current.tsv`)
- `STARTUP_LOG_MAX_BYTES` (default: `1048576`)
- `STARTUP_LOG_BACKUPS` (default: `5`)
- `STARTUP_BOOTSTRAP_OPENCLAW` (default: `1`)
- `STARTUP_BOOTSTRAP_EXAMPLE` (default: `1`)

## Bootstrapping behavior

On first boot, if `/data/startup` does not exist, the runner creates it.

If `STARTUP_BOOTSTRAP_EXAMPLE=1`, the runner also writes:

- `/data/startup/_example-openclaw.daemon.sh`

That file starts with `_`, so it is ignored until renamed and marked executable.

If `STARTUP_BOOTSTRAP_OPENCLAW=1`, the runner writes:

- `/data/startup/80-openclaw.daemon.sh`

This keeps first boot working without requiring a manual script drop-in.
