#!/usr/bin/env bash
set -euo pipefail

MOTO_ENDPOINT="${SQS_ENDPOINT:-http://localhost:3456}"
PORT="${MOTO_ENDPOINT##*:}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_REGION="${AWS_REGION:-us-east-1}"

is_moto() { curl -sSf "${MOTO_ENDPOINT}/" >/dev/null 2>&1; }

if is_moto; then
  echo "[moto] Moto already running at ${MOTO_ENDPOINT}. Not starting another."
  # Keep the process alive so Foreman doesn't shut everything down
  exec tail -f /dev/null
fi

# If port is in use but not by Moto, abort clearly
if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :${PORT} )" | grep -q LISTEN; then
  echo "[moto] ERROR: Port ${PORT} is in use by another program (not Moto). Change SQS_ENDPOINT or free the port."
  exit 1
fi

echo "[moto] Starting Moto on ${MOTO_ENDPOINT} ..."

# Quiet by default. Set MOTO_QUIET=false to see every WSGI access-log line.
MOTO_QUIET="${MOTO_QUIET:-true}"

# Check if moto_server is available, if not try to activate venv
if ! command -v moto_server >/dev/null 2>&1; then
  echo "[moto] moto_server not found in PATH, looking for virtual environment..."

  # Try common venv locations (relative to app/ directory where script runs)
  for venv_path in "../.venv" ".venv" "../venv" "venv"; do
    if [ -f "${venv_path}/bin/activate" ]; then
      echo "[moto] Found venv at ${venv_path}, activating..."
      source "${venv_path}/bin/activate"
      break
    fi
  done

  # Check again after attempting activation
  if ! command -v moto_server >/dev/null 2>&1; then
    echo "[moto] ERROR: moto_server not found. Please install moto:"
    echo "  python3 -m venv .venv"
    echo "  source .venv/bin/activate"
    echo "  pip install 'moto[server]'"
    exit 1
  fi
fi

if [ "${MOTO_QUIET}" = "true" ]; then
  # `--line-buffered` keeps grep flushing each line so foreman renders in real time.
  # `set +o pipefail` so a non-matching line doesn't kill the script via grep's exit 1
  # (we only care about moto_server's exit status).
  set +o pipefail
  # Filter only 2xx access lines; 4xx / 5xx (and anything that isn't a routine
  # success) still surface in the foreman console.
  moto_server -p "${PORT}" 2>&1 | grep --line-buffered -vE '"(GET|POST|PUT|DELETE|HEAD|PATCH|OPTIONS) .+ HTTP/1\.[01]" 2[0-9]{2} '
else
  exec moto_server -p "${PORT}"
fi
