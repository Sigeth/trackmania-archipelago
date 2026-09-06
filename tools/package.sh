#!/usr/bin/env bash
# Build the two release artifacts into dist/.
#   dist/Archipelago.op          -- Openplanet plugin (info.toml + src/)
#   dist/trackmania_turbo.apworld -- Archipelago world (apworld/trackmania_turbo/, minus test/)
# Run from the repo root. Used by semantic-release and reproducible by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf dist build
mkdir -p dist build

zip -r dist/Archipelago.op info.toml src -x '*.DS_Store' >/dev/null

rsync -a --exclude='__pycache__' --exclude='*.pyc' --exclude='test/' \
  apworld/trackmania_turbo build/
( cd build && zip -r -9 ../dist/trackmania_turbo.apworld trackmania_turbo >/dev/null )

rm -rf build
echo "built:"
ls -l dist
