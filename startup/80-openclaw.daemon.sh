#!/usr/bin/env bash
set -euo pipefail

exec openclaw gateway run --allow-unconfigured --port 3000 --bind auto
