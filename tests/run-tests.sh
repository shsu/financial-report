#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
./test-positions.sh
./test-indicators.sh
echo "ALL OFFLINE TESTS PASS"
