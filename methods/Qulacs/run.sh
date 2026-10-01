#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec "$REPO_DIR/.venv/bin/python3" \
    "$SCRIPT_DIR/simulator.py" \
    "$1"