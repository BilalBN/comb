#!/usr/bin/env bash
# Runs the Comb server from a test folder kept apart from the code.
#
#   tools/test-server.sh            install/refresh into ~/Comb-Project and start
#   tools/test-server.sh --reset    same, but wipe the test data first (new setup code)
#
# The code folder is never used for data; the test folder never holds code
# you edit. Set COMB_TEST_DIR to use another folder.
set -euo pipefail

CODE="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="${COMB_TEST_DIR:-$HOME/Comb-Project}"
PORT="${COMB_PORT:-8080}"

if [ "${1:-}" = "--reset" ]; then
  read -r -p "Delete all test data in $TEST_DIR/data? [y/N] " answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || { echo "Nothing deleted."; exit 1; }
  rm -rf "$TEST_DIR/data"
fi

mkdir -p "$TEST_DIR"
PY="$(command -v python3)"
"$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' || {
  echo "Comb needs Python 3.10 or newer. Found: $("$PY" --version)"; exit 1; }

if [ ! -x "$TEST_DIR/.venv/bin/python" ]; then
  echo "==> Creating $TEST_DIR/.venv"
  "$PY" -m venv "$TEST_DIR/.venv"
fi

echo "==> Installing the server from $CODE/server"
"$TEST_DIR/.venv/bin/pip" install -q --upgrade pip
"$TEST_DIR/.venv/bin/pip" install -q --force-reinstall --no-deps "$CODE/server"
"$TEST_DIR/.venv/bin/pip" install -q "$CODE/server"

if [ -f "$TEST_DIR/data/SETUP_CODE.txt" ]; then
  echo
  echo "One-time setup code for the app: $(cat "$TEST_DIR/data/SETUP_CODE.txt")"
elif [ ! -f "$TEST_DIR/data/comb.sqlite3" ]; then
  echo
  echo "First start: the one-time setup code appears in the log below."
fi
echo "==> Starting on http://127.0.0.1:$PORT  (Ctrl+C to stop)"
cd "$TEST_DIR"
COMB_DATA_DIR="$TEST_DIR/data" exec "$TEST_DIR/.venv/bin/python" -m comb_server serve --port "$PORT"
