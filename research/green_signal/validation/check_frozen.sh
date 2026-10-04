#!/usr/bin/env bash
# Proves the detector files used for the validation are the frozen ones.
set -euo pipefail
cd "$(dirname "$0")/.."
sha256sum -c FROZEN.sha256
